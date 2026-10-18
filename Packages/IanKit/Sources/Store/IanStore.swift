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
    /// The item's version when the action was sent. A snapshot holding a higher one means the
    /// item moved on and the event that would have cleared the mark was missed.
    public let sentVersion: Int
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
  /// A sign-in is open, in the browser or on its way, so a second one is not started.
  public private(set) var isSigningIn = false

  public let profile: EnvironmentProfile

  /// Actions work only while the data is current (spec section 4: no queue, no stale actions).
  public var actionsEnabled: Bool { phase == .running && connection == .live }

  private static let log = Logger(subsystem: "ai.valliance.ian.desktop", category: "store")
  private static let rememberedCorrelations = 32

  private let service: any DesktopService
  public let appVersion: SemanticVersion
  private let clock: any SyncClock
  private let timing: SyncEngine.Timing
  private let jitter: @Sendable () -> Double
  private let now: @Sendable () -> Date
  private var syncTask: Task<Void, Never>?
  /// Stamps each sync task, so updates a cancelled one had already buffered are not applied.
  private var generation = 0
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
    generation += 1
    let mine = generation
    syncTask = Task { [weak self] in
      for await update in engine.updates() {
        guard let self, self.generation == mine, !Task.isCancelled else { return }
        self.apply(update)
      }
    }
  }

  public func stop() {
    cancelSync()
    if phase == .running { phase = .stopped }
  }

  /// Signs in, which opens the system browser for `lance-dev`, then starts syncing.
  public func signIn() async {
    guard !isSigningIn else { return }
    isSigningIn = true
    defer { isSigningIn = false }
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
    pending = pending.filter { itemID, mark in
      guard let item = state.items[itemID] else { return false }
      return item.version <= mark.sentVersion
    }
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
    pending[itemID] = Pending(actionID: actionID, correlationID: nil, sentVersion: item.version)
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
      // Only a newer copy of an item still on screen replaces it; the problem body may be older
      // than an event already applied, and a removed item stays removed.
      guard let held = state.items[current.id] else { return }
      if current.version > held.version { state.items[current.id] = current }
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
    case .failed(let message):
      cancelSync()
      reset()
      phase = .signInRequired(message: message)
    default:
      Self.log.error("sync stopped: \(error.kind, privacy: .public)")
    }
  }

  /// A `401`: clear the token and ask for sign-in. The first time in a session Ian opens the
  /// sign-in itself, since the principal launched the app to use it. After that the principal
  /// asks, so a token the server keeps refusing cannot loop.
  private func requireSignIn() {
    cancelSync()
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
    cancelSync()
    reset()
    phase = .upgradeRequired(minimumVersion: minimumVersion)
  }

  private func cancelSync() {
    syncTask?.cancel()
    syncTask = nil
    generation += 1
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

extension IanStore {
  /// Builds the store the app runs: the profile the launch argument or saved setting names (or
  /// `mock`), its token provider, the HTTP service and the app's version.
  /// - Parameters:
  ///   - profileName: The requested profile, or nil for `mock`. An unknown name logs and falls
  ///     back to `mock`.
  ///   - info: The Info.plist, carrying the `lance-dev` sign-in settings.
  ///   - shortVersion: `CFBundleShortVersionString`.
  ///   - openURL: Opens the sign-in page in the system browser. AppKit is the app's to import.
  public static func make(
    profileName: String?,
    info: [String: Any],
    bundleIdentifier: String,
    shortVersion: String?,
    openURL: @escaping @Sendable (URL) async -> Void
  ) -> IanStore {
    let profile: EnvironmentProfile
    do {
      profile = try EnvironmentProfile.resolve(requested: profileName, info: info)
    } catch {
      log.error("\(error.localizedDescription, privacy: .private) Starting on the mock profile.")
      profile = .mock
    }
    let version =
      shortVersion.flatMap(SemanticVersion.init) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    let tokens = profile.makeTokenProvider(bundleIdentifier: bundleIdentifier, openURL: openURL)
    let service = DesktopAPI(profile: profile, tokens: tokens, clientVersion: version.description)
    return IanStore(service: service, profile: profile, appVersion: version)
  }

  /// The store for the running app, read from its bundle and `UserDefaults`.
  public static func live(
    bundle: Bundle = .main,
    defaults: UserDefaults = .standard,
    openURL: @escaping @Sendable (URL) async -> Void
  ) -> IanStore {
    make(
      profileName: defaults.string(forKey: EnvironmentProfile.defaultsKey),
      info: bundle.infoDictionary ?? [:],
      bundleIdentifier: bundle.bundleIdentifier ?? "ai.valliance.ian.desktop",
      shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      openURL: openURL)
  }
}
