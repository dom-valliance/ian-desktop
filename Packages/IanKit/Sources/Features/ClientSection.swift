import Contract

/// The seven views in the sidebar, in the order spec 6.2 lists them.
enum ClientSection: String, CaseIterable, Identifiable, Sendable {
  case today, proposals, commitments, tasks, alerts, agents, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today: "Today"
    case .proposals: "Proposals"
    case .commitments: "Commitments"
    case .tasks: "Tasks"
    case .alerts: "Alerts"
    case .agents: "Agents"
    case .settings: "Settings"
    }
  }

  /// The number the server sent for this view in `views.counts`. Settings has none, and no
  /// count is shown before the first snapshot.
  func count(in counts: Components.Schemas.ViewCounts?) -> Int? {
    guard let counts else { return nil }
    switch self {
    case .today: return counts.today
    case .proposals: return counts.proposals
    case .commitments: return counts.commitments
    case .tasks: return counts.tasks
    case .alerts: return counts.alerts
    case .agents: return counts.agents
    case .settings: return nil
    }
  }
}
