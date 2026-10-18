import Client
import Contract
import Foundation
import Observation
import os

/// The one observable store behind every view. It applies the snapshot and the events the sync
/// loop delivers, runs the actions an item offers, and tracks what the server has not yet
/// settled (ADR 0001, 0002).
///
/// An action marks its item pending and nothing more. Only the server's event moves the item, and
/// the event that carries the action's correlation id clears the mark.
@MainActor
@Observable
public final class IanStore {
  public enum Phase: Equatable, Sendable {
    /// Not started, or stopped.
    case stopped
    /// Syncing, or trying to.
    case running
    /// No usable token. `message` says why when sign-in has already failed.
    case signInRequired(message: String?)
    /// The server wants a newer client. There is no data in this state.
    case upgradeRequired(minimumVersion: String?)
  }

  public enum Connection: Equatable, Sendable {
    case connecting
    case live
    /// The stream is down. Data stays on screen with its age, and actions are disabled.
    case offline
  }

  /// An action sent and not yet settled by an event.
  public struct Pending: Equatable, Sendable {
    public let actionID: String
    /// Nil until the server's answer arrives.
    public fileprivate(set) var correlationID: String?
  }

  /// Something the principal should see on an item.
  public enum Notice: Equatable, Sendable {
    /// An action failed, with the reason.
    case failed(String)
    /// The item changed on the server before the action arrived. The item shown is the new one.
    case changed
  }

  public private(set) var phase: Phase = .stopped
  public private(set) var connection: Connection = .connecting
  public private(set) var state = StoreState()
  /// Item id to its unsettled action.
  public private(set) var pending: [String: Pending] = [:]
  public private(set) var notices: [String: Notice] = [:]
  /// When the server last confirmed the data: a snapshot, an event or a heartbeat.
  public private(set) var lastUpdatedAt: Date?

  public let profile: EnvironmentProfile

  /// Actions work only while the data is current (spec section 4: no queue, no stale actions).
  public var actionsEnabled: Bool { phase == .running && connection == .live }

  private static let log = Logger(subsystem: "ai.valliance.ian.desktop", category: "store")
  private static let rememberedCorrelations = 32

  private let service: any DesktopService
  private let appVersion: SemanticVersion
  private let clock: any SyncClock
  private let timing: SyncEngine.Timing
  private let jitter: @Sendable () -> Double
  private let now: @Sendable () -> Date
  private var syncTask: Task<Void, Never>?
  private var signInAttempted = false
  /// Correlation ids from events that arrived while an action's answer was still in flight.
  private var earlyCorrelations: [String] = []

  public init(
    service: any DesktopService,
    profile: EnvironmentProfile,
    appVersion: SemanticVersion,
    clock: any SyncClock = SystemSyncClock(),
    timing: SyncEngine.Timing = SyncEngine.Timing(),
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.service = service
    self.profile = profile
    self.appVersion = appVersion
    self.clock = clock
    self.timing = timing
    self.jitter = jitter
    self.now = now
  }

  /// How old the data is. Nil before the first snapshot.
  public func dataAge(at date: Date = Date()) -> TimeInterval? {
    lastUpdatedAt.map { max(0, date.timeIntervalSince($0)) }
  }

  // MARK: Lifecycle

  /// Starts syncing. Does nothing when already running.
  public func start() {
    guard syncTask == nil else { return }
    phase = .running
    connection = .connecting
    let engine = SyncEngine(
      service: service, appVersion: appVersion, clock: clock, timing: timing, jitter: jitter)
    syncTask = Task { [weak self] in
      for await update in engine.updates() {
        guard let self else { return }
        self.apply(update)
      }
    }
  }

  public func stop() {
    syncTask?.cancel()
    syncTask = nil
    if phase == .running { phase = .stopped }
  }

  /// Signs in, which opens the system browser for `lance-dev`, then starts syncing.
  public func signIn() async {
    stop()
    do {
      try await service.signIn()
      start()
    } catch {
      phase = .signInRequired(message: error.localizedDescription)
    }
  }

  /// Clears the credentials and every piece of data.
  public func signOut() async {
    stop()
    await service.signOut()
    reset()
    signInAttempted = false
    phase = .signInRequired(message: nil)
  }

  // MARK: Updates

  private func apply(_ update: SyncUpdate) {
    switch update {
    case .me(let me):
      state.me = me
    case .snapshot(let snapshot):
      state.apply(snapshot: snapshot)
      dropPendingMarksForMissingItems()
      lastUpdatedAt = now()
    case .connected:
      connection = .live
      lastUpdatedAt = now()
    case .disconnected:
      connection = .offline
    case .event(let id, let event):
      apply(event: event, id: id)
    case .failed(let error):
      handle(error)
    }
  }

  private func apply(event: Components.Schemas.StreamEvent, id: String?) {
    let effects = state.apply(event: event, id: id)
    guard effects.applied else { return }
    lastUpdatedAt = now()
    if let removed = effects.removedItemID {
      pending[removed] = nil
      notices[removed] = nil
    }
    if let correlationID = effects.correlationID { settle(correlationID: correlationID) }
    if let minimum = effects.deprecatedBelow,
      let required = SemanticVersion(minimum), required > appVersion
    {
      requireUpgrade(minimumVersion: minimum)
    }
  }

  /// Clears the pending mark the event's correlation id belongs to.
  private func settle(correlationID: String) {
    if let itemID = pending.first(where: { $0.value.correlationID == correlationID })?.key {
      pending[itemID] = nil
    } else if pending.values.contains(where: { $0.correlationID == nil }) {
      earlyCorrelations.append(correlationID)
      earlyCorrelations = Array(earlyCorrelations.suffix(Self.rememberedCorrelations))
    }
  }

  private func dropPendingMarksForMissingItems() {
    pending = pending.filter { state.items[$0.key] != nil }
    notices = notices.filter { state.items[$0.key] != nil }
  }

  // MARK: Actions

  /// Runs one of the item's own actions. `until` and `note` are sent only when the action's
  /// `input` asks for them. The item is marked pending, never done.
  public func run(
    actionID: String, on itemID: String, until: Date? = nil, note: String? = nil
  ) async {
    guard let item = state.items[itemID],
      let action = item.actions.first(where: { $0.id == actionID })
    else { return }
    guard pending[itemID] == nil else { return }
    guard actionsEnabled else {
      notices[itemID] = .failed(DesktopError.offline.localizedDescription)
      return
    }
    let input = (
      until: action.input == .until ? until : nil, note: action.input == .note ? note : nil
    )
    switch action.input {
    case .until where input.until == nil:
      notices[itemID] = .failed("Choose a time for \"\(action.label)\" first.")
      return
    case .note where input.note == nil:
      notices[itemID] = .failed("Add a note for \"\(action.label)\" first.")
      return
    default:
      break
    }

    notices[itemID] = nil
    pending[itemID] = Pending(actionID: actionID, correlationID: nil)
    do {
      let correlationID = try await service.runAction(
        itemID: itemID, actionID: actionID, version: item.version, until: input.until,
        note: input.note)
      attach(correlationID: correlationID, to: itemID)
    } catch {
      handleActionFailure(error, itemID: itemID)
    }
  }

  private func attach(correlationID: String, to itemID: String) {
    guard pending[itemID] != nil else { return }
    if earlyCorrelations.contains(correlationID) {
      pending[itemID] = nil
    } else {
      pending[itemID]?.correlationID = correlationID
    }
  }

  private func handleActionFailure(_ error: any Error, itemID: String) {
    pending[itemID] = nil
    guard let failure = error as? DesktopError else {
      notices[itemID] = .failed(error.localizedDescription)
      return
    }
    switch failure {
    case .conflict(let current):
      state.items[current.id] = current
      notices[itemID] = .changed
    case .unauthorised, .upgradeRequired:
      handle(failure)
    default:
      notices[itemID] = .failed(failure.localizedDescription)
    }
  }

  public func dismissNotice(for itemID: String) {
    notices[itemID] = nil
  }

  // MARK: Failures

  private func handle(_ error: DesktopError) {
    switch error {
    case .unauthorised:
      requireSignIn()
    case .upgradeRequired(let minimum):
      requireUpgrade(minimumVersion: minimum)
    default:
      Self.log.error("sync stopped: \(String(describing: error), privacy: .public)")
    }
  }

  /// A `401`: clear the token and ask for sign-in. The first time in a session Ian opens the
  /// sign-in itself, since the principal launched the app to use it. After that the principal
  /// asks, so a token the server keeps refusing cannot loop.
  private func requireSignIn() {
    syncTask?.cancel()
    syncTask = nil
    reset()
    phase = .signInRequired(message: nil)
    let attemptSignIn = !signInAttempted
    signInAttempted = true
    // A fresh task, because the sync task that reported the failure is cancelled above.
    Task { [service] in
      await service.signOut()
      if attemptSignIn { await signIn() }
    }
  }

  private func requireUpgrade(minimumVersion: String?) {
    syncTask?.cancel()
    syncTask = nil
    reset()
    phase = .upgradeRequired(minimumVersion: minimumVersion)
  }

  private func reset() {
    state = StoreState()
    pending = [:]
    notices = [:]
    earlyCorrelations = []
    lastUpdatedAt = nil
    connection = .connecting
  }
}
