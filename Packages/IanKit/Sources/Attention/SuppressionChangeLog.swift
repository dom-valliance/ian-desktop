import os

/// Leaves one line in the unified log each time suppression changes, and none while it stays the
/// same, so a stall in motion has evidence. The line names the triggers by their raw values and
/// carries no item content.
@MainActor
public final class SuppressionChangeLog {
  private static let motionLog = Logger(
    subsystem: "ai.valliance.ian.desktop", category: "motion")

  private let emit: (@MainActor (String) -> Void)?
  private var last: [Suppression.Trigger] = []

  /// - Parameter emit: Receives each line. Without one, the line goes to the `motion` category
  ///   at `.notice`, public because it holds trigger names only.
  public init(emit: (@MainActor (String) -> Void)? = nil) {
    self.emit = emit
  }

  /// Logs `suppression` when its triggers differ from the last one recorded. The first call
  /// compares against "nothing suppresses", so a quiet start logs nothing.
  public func record(_ suppression: Suppression) {
    guard suppression.triggers != last else { return }
    last = suppression.triggers
    let names = suppression.triggers.map(\.rawValue).joined(separator: ", ")
    let line = "suppression \(suppression.isActive ? "on: \(names)" : "off")"
    if let emit {
      emit(line)
    } else {
      Self.motionLog.notice("\(line, privacy: .public)")
    }
  }
}
