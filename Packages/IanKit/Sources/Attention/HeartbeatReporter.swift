import Foundation
import Observation
import Store

/// Time for the reporter, injected so tests never wait for real. `now` is a monotonic reading
/// and only differences between readings mean anything.
public struct HeartbeatTime: Sendable {
  public let now: @Sendable () async -> Duration
  public let sleep: @Sendable (Duration) async throws -> Void

  public init(
    now: @escaping @Sendable () async -> Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.now = now
    self.sleep = sleep
  }

  public static var system: HeartbeatTime {
    let clock = ContinuousClock()
    let origin = clock.now
    return HeartbeatTime(
      now: { origin.duration(to: clock.now) }, sleep: { try await clock.sleep(for: $0) })
  }
}

/// Sends the session heartbeat: every interval, and at once when `active` or `suppressed`
/// changes or the principal returns from idle. It decides nothing about delivery; Lance does.
///
/// It reads the Mac through `ActivityMonitoring` and suppression through a closure, and hands
/// each reading to `send`, which says whether Lance recorded it. While `session` is nil (signed
/// out, not yet synced or offline) nothing is sent and nothing is queued, and the reporter stops
/// looking until the session returns. A failed send is retried after 5, 10, 20 and 40 seconds and
/// then every interval, and a success starts the count again; a change still sends at once.
/// When the session changes, as after a sign-out or a profile switch, the first heartbeat of the
/// new one goes at once, with the same device id.
///
/// One send is in flight at a time. Changes that arrive meanwhile share one waiting send, which
/// reads the inputs when its turn comes, so a slow request never delivers old readings late.
@MainActor
public final class HeartbeatReporter {
  /// A random id made once per process and held in memory only (contract `SessionHeartbeat`).
  public let deviceID: UUID

  private let timing: HeartbeatTiming
  private let time: HeartbeatTime
  private let activity: any ActivityMonitoring
  private let suppressed: @MainActor () -> Bool
  private let session: @MainActor () -> Int?
  private let send: @MainActor (UUID, HeartbeatReading) async -> Bool

  private var policy: HeartbeatPolicy
  private var lastSession: Int?
  private var isRunning = false
  private var looking: Task<Void, Never>?
  private var sender: Task<Void, Never>?
  private var sendWaits = false
  private var failures = 0
  /// Rises with each start and stop, so work left over from an earlier run does nothing.
  private var run = 0

  public init(
    deviceID: UUID = UUID(),
    timing: HeartbeatTiming = HeartbeatTiming(),
    time: HeartbeatTime = .system,
    activity: any ActivityMonitoring,
    suppressed: @escaping @MainActor () -> Bool,
    session: @escaping @MainActor () -> Int?,
    send: @escaping @MainActor (UUID, HeartbeatReading) async -> Bool
  ) {
    self.deviceID = deviceID
    self.timing = timing
    self.time = time
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
    time: HeartbeatTime = .system,
    activity: any ActivityMonitoring,
    suppressed: @escaping @MainActor () -> Bool
  ) {
    self.init(
      deviceID: deviceID, timing: timing, time: time, activity: activity, suppressed: suppressed,
      session: { store.heartbeatSession },
      send: { deviceID, reading in
        await store.sendHeartbeat(
          deviceID: deviceID, active: reading.active, suppressed: reading.suppressed,
          idleSeconds: reading.idleSeconds)
      })
  }

  public func start() {
    guard !isRunning else { return }
    isRunning = true
    run += 1
    activity.start { [weak self] in self?.look() }
    observeInputs(run: run)
    look()
  }

  public func stop() {
    isRunning = false
    run += 1
    failures = 0
    looking?.cancel()
    looking = nil
    sender?.cancel()
    sender = nil
    sendWaits = false
    activity.stop()
  }

  /// Looks now, then keeps looking at the times the policy asks for, until there is no session.
  /// Restarting replaces the wait that was running. `delay` holds the first look back.
  func look(after delay: Duration? = nil) {
    guard isRunning else { return }
    looking?.cancel()
    looking = Task { [weak self] in
      if let delay, let self { try? await self.time.sleep(delay) }
      while !Task.isCancelled {
        guard let self, let wait = await self.evaluate() else { return }
        try? await self.time.sleep(wait)
      }
    }
  }

  /// Sends when the policy says so, and returns how long to wait before looking again, or nil
  /// while there is no session.
  func evaluate() async -> Duration? {
    let now = await time.now()
    guard let current = session() else { return nil }
    if current != lastSession {
      policy.reset()
      lastSession = current
    }
    let reading = currentReading()
    if policy.decide(reading, at: now) { requestSend() }
    return policy.untilNextLook(at: now, reading: reading)
  }

  private func currentReading() -> HeartbeatReading {
    HeartbeatReading(
      active: activity.isActive, suppressed: suppressed(), idleSeconds: activity.idleSeconds)
  }

  private func requestSend() {
    if sender != nil {
      sendWaits = true
      return
    }
    let run = run
    sender = Task { [weak self] in await self?.drain(run: run) }
  }

  /// Sends, then sends once more with fresh readings if something changed meanwhile. A failure
  /// with nothing waiting moves the next send out by the backoff; with a change waiting, the
  /// change goes at once.
  private func drain(run: Int) async {
    defer { if run == self.run { sender = nil } }
    while true {
      sendWaits = false
      let reading = currentReading()
      policy.amendSent(reading)
      let delivered = await send(deviceID, reading)
      guard run == self.run, !Task.isCancelled else { return }
      if delivered {
        failures = 0
      } else if !sendWaits {
        await backOff()
      }
      guard sendWaits else { return }
    }
  }

  private func backOff() async {
    failures += 1
    let step = timing.checkInterval * (1 << min(failures - 1, 10))
    policy.sendFailed(at: await time.now(), retryIn: min(step, timing.interval))
    look()
  }

  /// Watches what the heartbeat depends on, so a change is reported at once. The store's session
  /// and suppression are observable; the activity monitor reports its own changes.
  private func observeInputs(run: Int) {
    withObservationTracking {
      _ = suppressed()
      _ = session()
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, self.run == run else { return }
        self.look()
        self.observeInputs(run: run)
      }
    }
  }
}
