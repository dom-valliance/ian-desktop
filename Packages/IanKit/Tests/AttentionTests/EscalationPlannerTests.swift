import Testing

@testable import Attention

private func observed(_ id: String, _ rung: NotificationRung) -> ObservedItem {
  ObservedItem(id: id, rung: rung)
}

@Suite("The escalation planner")
struct EscalationPlannerTests {
  @Test("the first snapshot is a baseline where only stop items escalate")
  func baseline() {
    var planner = EscalationPlanner()
    let plan = planner.observe(
      [observed("a", .urgent), observed("b", .stop), observed("c", .needsYou)], hasSnapshot: true)
    #expect(plan.escalations == [observed("b", .stop)])
  }

  @Test("a new urgent item escalates after the baseline")
  func newItem() {
    var planner = EscalationPlanner()
    _ = planner.observe([observed("a", .ambient)], hasSnapshot: true)
    let plan = planner.observe(
      [observed("a", .ambient), observed("b", .urgent)], hasSnapshot: true)
    #expect(plan.escalations == [observed("b", .urgent)])
  }

  @Test("a rise escalates and a repeat with no change does not")
  func riseAndRepeat() {
    var planner = EscalationPlanner()
    _ = planner.observe([observed("a", .needsYou)], hasSnapshot: true)
    #expect(planner.observe([observed("a", .urgent)], hasSnapshot: true).escalations.count == 1)
    #expect(planner.observe([observed("a", .urgent)], hasSnapshot: true).escalations.isEmpty)
  }

  @Test("a fall is silent and a later rise escalates again")
  func fallThenRise() {
    var planner = EscalationPlanner()
    _ = planner.observe([observed("a", .urgent)], hasSnapshot: true)
    #expect(planner.observe([observed("a", .needsYou)], hasSnapshot: true).escalations.isEmpty)
    let plan = planner.observe([observed("a", .urgent)], hasSnapshot: true)
    #expect(plan.escalations == [observed("a", .urgent)])
  }

  @Test("a reset forgets everything and the next snapshot is a new baseline")
  func reset() {
    var planner = EscalationPlanner()
    _ = planner.observe([observed("a", .urgent)], hasSnapshot: true)
    let cleared = planner.observe([], hasSnapshot: false)
    #expect(cleared.removed == ["a"])
    let plan = planner.observe(
      [observed("a", .urgent), observed("b", .stop)], hasSnapshot: true)
    #expect(plan.escalations == [observed("b", .stop)])
  }

  @Test("an item that leaves the store is reported as removed")
  func removal() {
    var planner = EscalationPlanner()
    _ = planner.observe([observed("a", .urgent), observed("b", .stop)], hasSnapshot: true)
    let plan = planner.observe([observed("b", .stop)], hasSnapshot: true)
    #expect(plan.removed == ["a"])
    #expect(plan.escalations.isEmpty)
  }

  @Test("escalations come most urgent first, then by id")
  func order() {
    var planner = EscalationPlanner()
    _ = planner.observe([], hasSnapshot: true)
    let plan = planner.observe(
      [observed("b", .urgent), observed("a", .urgent), observed("c", .stop)], hasSnapshot: true)
    #expect(plan.escalations.map(\.id) == ["c", "a", "b"])
  }

  @Test("no snapshot yet escalates nothing")
  func beforeSnapshot() {
    var planner = EscalationPlanner()
    let plan = planner.observe([], hasSnapshot: false)
    #expect(plan == EscalationPlan())
  }
}
