import Contract
import Foundation

/// One agent as the table shows it, in words. Every value is the server's: the state, the cost and
/// the share of the ceiling are formatted, not computed (ADR 0001).
struct AgentRow: Identifiable, Equatable {
  enum Command: Equatable {
    case pause, resume
  }

  let id: String
  let name: String
  let kind: String
  let state: String
  /// The breaker's state when the agent has one and the state does not already say it.
  let breaker: String?
  let lastRun: String
  let nextRun: String
  let cost: String
  let share: String
  /// Both as the server sent them, such as "£0.42, 2.8%".
  var costAndShare: String { "\(cost), \(share)" }
  /// The one command the row offers, nil when the agent is not pausable.
  let command: Command?

  init(agent: Components.Schemas.Agent, timeZone: TimeZone = .current) {
    id = agent.id
    name = agent.name
    kind = Self.kindName(agent.kind)
    state = Self.stateName(agent.state)
    breaker = agent.state == .breakerOpen ? nil : agent.breaker.flatMap(Self.breakerName)
    let format = CardDate(timeZone: timeZone)
    lastRun = agent.lastRunAt.map(format.string) ?? "Not yet"
    nextRun = agent.nextRunAt.map(format.string) ?? "None planned"
    cost = Self.money(agent.costTodayGbp)
    share = Self.percent(agent.ceilingFraction)
    command = agent.pausable ? (agent.state == .paused ? .resume : .pause) : nil
  }

  static func kindName(_ kind: Components.Schemas.AgentKind) -> String {
    switch kind {
    case .watcher: "Watcher"
    case .agent: "Agent"
    case .job: "Job"
    }
  }

  static func stateName(_ state: Components.Schemas.AgentState) -> String {
    switch state {
    case .running: "Running"
    case .idle: "Idle"
    case .paused: "Paused"
    case .breakerOpen: "Breaker open"
    case .failed: "Failed"
    }
  }

  /// A closed breaker is the normal case and says nothing.
  private static func breakerName(_ breaker: Components.Schemas.BreakerState) -> String? {
    switch breaker {
    case .closed: nil
    case .open: "Breaker open"
    case .halfOpen: "Breaker half open"
    }
  }

  static func money(_ pounds: Double) -> String {
    pounds.formatted(.currency(code: "GBP").locale(Locale(identifier: "en_GB")))
  }

  /// A fraction as a percentage, such as 0.03 as "3%".
  static func percent(_ fraction: Double) -> String {
    fraction.formatted(
      .percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_GB")))
  }
}

/// What the Agents view says while the organisation's kill switch is on. Read-only: nothing
/// here can release it (spec 6.3).
struct KillSwitchNotice: Equatable {
  let title = "Paused for everyone"
  let message: String

  /// Nil when the kill switch is off.
  init?(global: Components.Schemas.GlobalState) {
    guard global.paused else { return nil }
    message =
      "Ian's kill switch is on, so no agent acts until it is released. "
      + "You cannot change this here."
      + (global.pausedReason.map { " Reason: \($0)" } ?? "")
  }
}
