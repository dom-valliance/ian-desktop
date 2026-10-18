import Foundation

/// Time for the sync loop, injected so tests never wait for real.
public protocol SyncClock: Sendable {
  /// A monotonic reading. Only differences between readings mean anything.
  func now() async -> Duration
  func sleep(for duration: Duration) async throws
}

public struct SystemSyncClock: SyncClock {
  private let clock = ContinuousClock()
  private let origin: ContinuousClock.Instant

  public init() {
    origin = clock.now
  }

  public func now() async -> Duration { origin.duration(to: clock.now) }

  public func sleep(for duration: Duration) async throws {
    try await clock.sleep(for: duration)
  }
}
