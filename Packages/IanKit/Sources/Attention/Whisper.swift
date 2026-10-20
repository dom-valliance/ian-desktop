import Observation

/// The one-line whisper an urgent item gets beside the Orbit (spec 6.6). It shows the item's
/// title for eight seconds. A newer whisper replaces it and restarts the eight seconds.
///
/// It has no motion, so Reduce Motion needs nothing from it.
@MainActor
@Observable
public final class Whisper {
  public static let lifetime: Duration = .seconds(8)

  /// The title being whispered, or nil when nothing is.
  public private(set) var title: String?

  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored private var expiry: Task<Void, Never>?

  /// - Parameter sleep: Waits for a duration. The app passes `Task.sleep`; tests pass a manual
  ///   clock's.
  public init(
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.sleep = sleep
  }

  public func show(_ title: String) {
    expiry?.cancel()
    self.title = title
    let sleep = sleep
    expiry = Task { [weak self] in
      guard (try? await sleep(Self.lifetime)) != nil, !Task.isCancelled else { return }
      self?.title = nil
    }
  }

  public func hide() {
    expiry?.cancel()
    expiry = nil
    title = nil
  }
}
