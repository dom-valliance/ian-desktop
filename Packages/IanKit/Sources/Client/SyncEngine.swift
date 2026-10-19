import Contract
import Foundation
import os

/// What the sync loop reports to the store, in the order it happens.
public enum SyncUpdate: Sendable, Equatable {
  /// `GET /me`, fetched once at the start.
  case me(Components.Schemas.Me)
  /// How far the server's clock is ahead of this Mac's, in seconds, estimated from `GET /me`.
  /// Only sent when the engine was given a wall clock.
  case clockOffset(TimeInterval)
  /// A full snapshot, from the start, after a `410`, or from polling while the stream is down.
  case snapshot(Components.Schemas.Snapshot)
  /// The stream is open.
  case connected
  /// One event. `id` is nil for `heartbeat`.
  case event(id: String?, Components.Schemas.StreamEvent)
  /// The stream is down. The loop keeps trying, and polls the snapshot after a minute.
  case disconnected
  /// The loop stopped for a reason retrying cannot fix: `unauthorised`, `upgradeRequired`, or
  /// `failed`, such as a Keychain refusal.
  case failed(DesktopError)
}

/// Exponential backoff with jitter, capped (spec section 4, step 5).
public struct Backoff: Sendable, Equatable {
  public var base: Duration
  public var cap: Duration

  public init(base: Duration = .seconds(1), cap: Duration = .seconds(30)) {
    self.base = base
    self.cap = cap
  }

  /// The wait before retry number `attempt` (from 0). It lies between half of the exponential
  /// ceiling and the ceiling, which never exceeds `cap`. `jitter` is a fraction from 0 to 1.
  public func delay(attempt: Int, jitter: Double) -> Duration {
    let ceiling = min(cap, base * Double(1 << min(max(attempt, 0), 20)))
    return ceiling * (0.5 + 0.5 * min(max(jitter, 0), 1))
  }
}

/// Keeps the store's data current: `me`, a snapshot, then the event stream resumed from the last
/// id, with reconnection, a `410` refetch, silence detection and the offline snapshot poll
/// (spec section 4). It decides nothing about the data; it passes it on.
public struct SyncEngine: Sendable {
  public struct Timing: Sendable, Equatable {
    /// A stream silent for this long is dead. The server sends a heartbeat every 25 seconds, so
    /// this is a little over two.
    public var silenceLimit: Duration = .seconds(55)
    /// Time without the stream before the snapshot poll starts.
    public var pollAfter: Duration = .seconds(60)
    public var pollInterval: Duration = .seconds(60)
    /// A connection that lasted this long counts as healthy, which resets the backoff.
    public var stableAfter: Duration = .seconds(10)
    public var backoff = Backoff()

    public init() {}
  }

  private let service: any DesktopService
  private let appVersion: SemanticVersion
  private let clock: any SyncClock
  private let timing: Timing
  private let jitter: @Sendable () -> Double
  private let wallClock: (@Sendable () -> Date)?

  /// - Parameter appVersion: The app's version. When `GET /me` reports a `minClientVersion`
  ///   above it, the loop fails with `upgradeRequired` before it fetches any data (spec section 4,
  ///   step 2).
  public init(
    service: any DesktopService,
    appVersion: SemanticVersion,
    clock: any SyncClock = SystemSyncClock(),
    timing: Timing = Timing(),
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
    wallClock: (@Sendable () -> Date)? = nil
  ) {
    self.service = service
    self.appVersion = appVersion
    self.clock = clock
    self.timing = timing
    self.jitter = jitter
    self.wallClock = wallClock
  }

  /// Runs until the consumer stops iterating or the loop fails for good.
  public func updates() -> AsyncStream<SyncUpdate> {
    let (stream, sink) = AsyncStream<SyncUpdate>.makeStream()
    let run = SyncRun(
      service: service, appVersion: appVersion, clock: clock, timing: timing, jitter: jitter,
      wallClock: wallClock, sink: sink)
    let task = Task { await run.run() }
    sink.onTermination = { _ in task.cancel() }
    return stream
  }
}

private enum SyncSignal: Error {
  /// The stream cannot continue from the cursor, so fetch the snapshot again.
  case refetch
  /// The stream ended, or fell silent.
  case lost
}

private actor SyncRun {
  private static let log = Logger(subsystem: "ai.valliance.ian.desktop", category: "sync")

  private let service: any DesktopService
  private let appVersion: SemanticVersion
  private let clock: any SyncClock
  private let timing: SyncEngine.Timing
  private let jitter: @Sendable () -> Double
  private let wallClock: (@Sendable () -> Date)?
  private let sink: AsyncStream<SyncUpdate>.Continuation

  private var cursor: String?
  private var needsMe = true
  private var attempt = 0
  private var isDown = false
  private var poller: Task<Void, Never>?
  private var lastActivity: Duration = .zero
  private var resyncedLast = false
  /// True while a connection attempt is fetching its own snapshot.
  private var fetchingSnapshot = false

  init(
    service: any DesktopService, appVersion: SemanticVersion, clock: any SyncClock,
    timing: SyncEngine.Timing,
    jitter: @escaping @Sendable () -> Double, wallClock: (@Sendable () -> Date)?,
    sink: AsyncStream<SyncUpdate>.Continuation
  ) {
    self.service = service
    self.appVersion = appVersion
    self.clock = clock
    self.timing = timing
    self.jitter = jitter
    self.wallClock = wallClock
    self.sink = sink
  }

  func run() async {
    defer {
      poller?.cancel()
      sink.finish()
    }
    var connectedAt: Duration?
    while !Task.isCancelled {
      do {
        connectedAt = nil
        try await connect(connectedAt: &connectedAt)
      } catch is CancellationError {
        return
      } catch let error as DesktopError {
        switch error {
        case .unauthorised, .upgradeRequired, .failed:
          sink.yield(.failed(error))
          return
        case .gone:
          cursor = nil
          if retryAtOnce() { continue }
        default:
          break
        }
        Self.log.info("sync lost: \(error.kind, privacy: .public)")
      } catch SyncSignal.refetch {
        cursor = nil
        if retryAtOnce() { continue }
      } catch {
        Self.log.info("sync lost: \(error.localizedDescription, privacy: .private)")
      }
      if Task.isCancelled { return }
      if let connectedAt, await clock.now() - connectedAt >= timing.stableAfter { attempt = 0 }
      await waitBeforeRetry()
    }
  }

  /// A refetch is not an outage, so the first one retries at once. A second in a row, with no
  /// event between, backs off like any failure.
  private func retryAtOnce() -> Bool {
    defer { resyncedLast = true }
    return !resyncedLast
  }

  private func connect(connectedAt: inout Duration?) async throws {
    if needsMe {
      let sent = wallClock?()
      let me = try await service.me()
      sink.yield(.me(me))
      if let wallClock, let sent {
        // The server stamped `serverTime` somewhere inside the request, taken as its midpoint.
        let received = wallClock()
        let midpoint = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
        sink.yield(.clockOffset(me.serverTime.timeIntervalSince(midpoint)))
      }
      if let minimum = SemanticVersion(me.minClientVersion), minimum > appVersion {
        throw DesktopError.upgradeRequired(minClientVersion: minimum.description)
      }
      needsMe = false
    }
    if cursor == nil {
      fetchingSnapshot = true
      defer { fetchingSnapshot = false }
      let snapshot = try await service.snapshot()
      cursor = snapshot.cursor
      sink.yield(.snapshot(snapshot))
    }
    let messages = try await service.stream(lastEventID: cursor)
    connectedAt = await clock.now()
    lastActivity = connectedAt ?? .zero
    isDown = false
    poller?.cancel()
    poller = nil
    sink.yield(.connected)
    try await pump(messages)
  }

  private func pump(_ messages: AsyncThrowingStream<StreamMessage, any Error>) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for try await message in messages { try await self.handle(message) }
        throw SyncSignal.lost
      }
      group.addTask { try await self.watchForSilence() }
      defer { group.cancelAll() }
      try await group.next()
    }
  }

  private func handle(_ message: StreamMessage) async throws {
    lastActivity = await clock.now()
    switch message {
    case .event(let id, let event):
      resyncedLast = false
      if let id { cursor = id }
      sink.yield(.event(id: id, event))
    case .ignored:
      break
    case .undecodable:
      throw SyncSignal.refetch
    }
  }

  private func watchForSilence() async throws {
    while true {
      let silent = await clock.now() - lastActivity
      let remaining = timing.silenceLimit - silent
      if remaining <= .zero { throw SyncSignal.lost }
      try await clock.sleep(for: remaining)
    }
  }

  private func waitBeforeRetry() async {
    if !isDown {
      isDown = true
      sink.yield(.disconnected)
    }
    // Polling waits for `/me` to pass the version check, so a refused client never reads data.
    if poller == nil && !needsMe { startPolling() }
    let delay = timing.backoff.delay(attempt: attempt, jitter: jitter())
    attempt += 1
    try? await clock.sleep(for: delay)
  }

  /// While the stream is down, fetch the snapshot every interval after the first minute. The
  /// stream returning cancels this.
  private func startPolling() {
    poller = Task {
      do {
        try await clock.sleep(for: timing.pollAfter)
        while true {
          if let snapshot = try? await service.snapshot() {
            adopt(snapshot)
          }
          try await clock.sleep(for: timing.pollInterval)
        }
      } catch {}
    }
  }

  private func adopt(_ snapshot: Components.Schemas.Snapshot) {
    // A snapshot fetched before the stream returned, or while a connection attempt fetched its
    // own, is older than what the loop holds. So is one with a lower cursor.
    guard isDown, !fetchingSnapshot else { return }
    if let held = cursor.flatMap(UInt64.init), let polled = UInt64(snapshot.cursor), polled < held {
      return
    }
    cursor = snapshot.cursor
    sink.yield(.snapshot(snapshot))
  }
}
