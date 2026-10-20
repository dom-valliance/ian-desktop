import Client
import Foundation
import Observation
import Store

/// Sends the session heartbeat: every interval, and at once when `active` or `suppressed`
/// changes or the principal returns from idle. It decides nothing about delivery; Lance does.
///
/// It reads the Mac through `ActivityMonitoring` and suppression through a closure, and hands
/// each reading to `send`. While `session` is nil (signed out, not yet synced or offline) nothing
/// is sent and nothing is queued. When the session changes, as after a sign-out or a profile
/// switch, the first heartbeat of the new one goes at once, with the same device id.
@MainActor
public final class HeartbeatReporter {
  /// A random id made once per process and held in memory only (contract `SessionHeartbeat`).
  public let deviceID: UUID

  private let timing: HeartbeatTiming
  private let clock: any SyncClock
  private let activity: any ActivityMonitoring
  private let suppressed: @MainActor () -> Bool
  private let session: @MainActor () -> Int?
  private let send: @MainActor (UUID, HeartbeatReading) async -> Void

  private var policy: HeartbeatPolicy
  private var lastSession: Int?
  private var loop: Task<Void, Never>?
  /// The latest send, so each one starts after the one before it and Lance sees them in order.
  private var tail: Task<Void, Never>?

  public init(
    deviceID: UUID = UUID(),
    timing: HeartbeatTiming = HeartbeatTiming(),
    clock: any SyncClock = SystemSyncClock(),
    activity: any ActivityMonitoring,
    suppressed: @escaping @MainActor () -> Bool,
    session: @escaping @MainActor () -> Int?,
    send: @escaping @MainActor (UUID, HeartbeatReading) async -> Void
  ) {
    self.deviceID = deviceID
    self.timing = timing
    self.clock = clock
    self.activity = activity
    self.suppressed = suppressed
    self.session = session
    self.send = send
    self.policy = HeartbeatPolicy(timing: timing)
  }

  /// Reports through the store's `sendHeartbeat`, which owns the failure paths.
  public convenience init(
    store: IanStore,
    deviceID: UUID = UUID(),
    timing: HeartbeatTiming = HeartbeatTiming(),
    clock: any SyncClock = SystemSyncClock(),
    activity: any ActivityMonitoring,
    suppressed: @escaping @MainActor () -> Bool
  ) {
    self.init(
      deviceID: deviceID, timing: timing, clock: clock, activity: activity, suppressed: suppressed,
      session: { store.heartbeatSession },
      send: { deviceID, reading in
        await store.sendHeartbeat(
          deviceID: deviceID, active: reading.active, suppressed: reading.suppressed,
          idleSeconds: reading.idleSeconds)
      })
  }

  public func start() {
    guard loop == nil else { return }
    activity.start { [weak self] in self?.inputsChanged() }
    observeInputs()
    loop = Task { [weak self] in
      while !Task.isCancelled {
        guard let wait = await self?.evaluate() else { return }
        try? await self?.clock.sleep(for: wait)
      }
    }
  }

  public func stop() {
    loop?.cancel()
    loop = nil
    activity.stop()
  }

  /// Looks at the inputs now, without waiting for the next check.
  func inputsChanged() {
    Task { await evaluate() }
  }

  /// Sends when the policy says so, and returns how long to wait before looking again.
  @discardableResult
  func evaluate() async -> Duration {
    let now = await clock.now()
    guard let current = session() else { return timing.checkInterval }
    if current != lastSession {
      policy.reset()
      lastSession = current
    }
    let reading = HeartbeatReading(
      active: activity.isActive, suppressed: suppressed(), idleSeconds: activity.idleSeconds)
    if policy.decide(reading, at: now) { enqueue(reading) }
    return policy.untilNextLook(at: now)
  }

  private func enqueue(_ reading: HeartbeatReading) {
    let previous = tail
    let deviceID = deviceID
    tail = Task { [send] in
      await previous?.value
      await send(deviceID, reading)
    }
  }

  /// Watches what the heartbeat depends on, so a change is reported at once. The store's session
  /// and suppression are observable; the activity monitor reports its own changes.
  private func observeInputs() {
    withObservationTracking {
      _ = suppressed()
      _ = session()
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, self.loop != nil else { return }
        self.inputsChanged()
        self.observeInputs()
      }
    }
  }
}
