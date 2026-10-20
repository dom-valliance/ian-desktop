import Store

/// What the store holds of one item that the planner needs.
public struct ObservedItem: Equatable, Sendable {
  public let id: String
  public let rung: NotificationRung

  public init(id: String, rung: NotificationRung) {
    self.id = id
    self.rung = rung
  }

  public init(_ item: StoreState.Item) {
    self.init(id: item.id, rung: NotificationRung(item: item))
  }
}

/// What changed since the planner last looked.
public struct EscalationPlan: Equatable, Sendable {
  /// Items that appeared, or whose rung rose, most urgent first and then by id. The ladder
  /// decides which of them notify, whisper or arm Stop.
  public var escalations: [ObservedItem] = []
  /// Items that have left the store, whose delivered notification is to be withdrawn.
  public var removed: [String] = []

  public init(escalations: [ObservedItem] = [], removed: [String] = []) {
    self.escalations = escalations
    self.removed = removed
  }
}

/// Decides which items escalate (ADR 0020). It remembers the rung it last saw for each item, so
/// a repeat of the same state is silent, a fall is recorded without a sound and a later rise is
/// an escalation again.
///
/// The first state after a launch or a reset is a baseline: only Stop items escalate in it, so a
/// relaunch or a profile switch never floods the principal with what was already there.
public struct EscalationPlanner: Sendable {
  private var seen: [String: NotificationRung] = [:]
  private var awaitingBaseline = true

  public init() {}

  /// - Parameters:
  ///   - items: Every open item in the store.
  ///   - hasSnapshot: False while the store holds no data, which is before the first snapshot and
  ///     after a reset. The planner then forgets everything and waits for a new baseline.
  public mutating func observe(_ items: [ObservedItem], hasSnapshot: Bool) -> EscalationPlan {
    guard hasSnapshot else {
      let forgotten = seen.keys.sorted()
      seen = [:]
      awaitingBaseline = true
      return EscalationPlan(removed: forgotten)
    }

    var plan = EscalationPlan()
    let isBaseline = awaitingBaseline
    awaitingBaseline = false
    var next: [String: NotificationRung] = [:]
    for item in items {
      next[item.id] = item.rung
      let before = seen[item.id]
      let escalated = before.map { item.rung > $0 } ?? true
      guard escalated else { continue }
      if isBaseline && item.rung != .stop { continue }
      plan.escalations.append(item)
    }
    plan.removed = seen.keys.filter { next[$0] == nil }.sorted()
    seen = next
    plan.escalations.sort { $0.rung != $1.rung ? $0.rung > $1.rung : $0.id < $1.id }
    return plan
  }
}
