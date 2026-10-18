import Client
import Foundation

/// A clock that moves only when a test says so, so sync tests never wait for real.
public actor ManualClock: SyncClock {
  private struct Sleeper {
    let id: UUID
    let deadline: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var current: Duration = .zero
  private var sleepers: [Sleeper] = []
  private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  /// Every duration passed to `sleep`, in order.
  public private(set) var requestedSleeps: [Duration] = []

  public init() {}

  public func now() -> Duration { current }

  public func sleep(for duration: Duration) async throws {
    requestedSleeps.append(duration)
    let id = UUID()
    let deadline = current + duration
    try await withTaskCancellationHandler(
      operation: { () async throws -> Void in
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
          }
          sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
          wakeWatchers()
        }
      },
      onCancel: { Task { await self.cancel(id) } })
  }

  /// Moves time forward and wakes every sleeper whose deadline has passed, earliest first.
  public func advance(by duration: Duration) {
    current += duration
    let due = sleepers.filter { $0.deadline <= current }.sorted { $0.deadline < $1.deadline }
    sleepers.removeAll { $0.deadline <= current }
    for sleeper in due { sleeper.continuation.resume() }
  }

  /// Suspends until at least `count` tasks are asleep on this clock.
  public func waitForSleepers(_ count: Int = 1) async {
    if sleepers.count >= count { return }
    await withCheckedContinuation { watchers.append((count, $0)) }
  }

  private func wakeWatchers() {
    let ready = watchers.filter { sleepers.count >= $0.count }
    watchers.removeAll { sleepers.count >= $0.count }
    for watcher in ready { watcher.continuation.resume() }
  }

  private func cancel(_ id: UUID) {
    guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
    sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}

/// Polls `condition` until it holds, yielding between checks, and fails after a generous limit
/// so a broken test ends instead of hanging.
public func eventually(
  _ description: String = "the condition", timeout: Duration = .seconds(10),
  _ condition: @Sendable () async -> Bool
) async -> Bool {
  let limit = ContinuousClock.now.advanced(by: timeout)
  while ContinuousClock.now < limit {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(2))
  }
  return false
}
