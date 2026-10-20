import Foundation
import Store

/// The plain-text report Settings copies. It holds ids, versions, states, counts and timings,
/// and never a title, a meta line, a quote or a name (AGENTS.md rule 5, spec 6.4).
enum DiagnosticsReport {
  /// The event lag in words, such as "0.4 seconds", or "no heartbeat yet".
  static func lagText(_ lag: TimeInterval?) -> String {
    lag.map { String(format: "%.1f seconds", $0) } ?? "no heartbeat yet"
  }

  /// A time as UTC with milliseconds, the form the contract uses.
  static func timeText(_ date: Date?) -> String {
    date?.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) ?? "none"
  }

  @MainActor
  static func lines(for store: IanStore) -> [(label: String, value: String)] {
    [
      ("App version", store.appVersion.description),
      ("Contract version", store.state.me?.contractVersion ?? "unknown"),
      ("Environment", store.profileID),
      ("Event lag", lagText(store.eventLag)),
      ("Last snapshot", timeText(store.lastSnapshotAt)),
    ]
  }

  @MainActor
  static func text(for store: IanStore, generatedAt: Date) -> String {
    let phase: String
    switch store.phase {
    case .stopped: phase = "stopped"
    case .running: phase = "running"
    case .signInRequired: phase = "sign-in required"
    case .upgradeRequired: phase = "upgrade required"
    }
    let connection: String
    switch store.connection {
    case .connecting: connection = "connecting"
    case .live: connection = "live"
    case .offline: connection = "offline"
    }
    let extra: [(label: String, value: String)] = [
      ("Principal id", store.state.me?.principalId ?? "unknown"),
      ("State", phase),
      ("Connection", connection),
      ("Last event id", store.state.lastEventID.map(String.init) ?? "none"),
      ("Open items", String(store.state.items.count)),
      ("Agents", String(store.state.agents.count)),
      ("Generated", timeText(generatedAt)),
    ]
    return (["Ian diagnostics"] + (lines(for: store) + extra).map { "\($0.label): \($0.value)" })
      .joined(separator: "\n")
  }
}
