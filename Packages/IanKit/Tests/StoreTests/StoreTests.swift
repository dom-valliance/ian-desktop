import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

private typealias Schemas = Components.Schemas

private func event(_ json: String) -> Schemas.StreamEvent { Fixtures.event(json) }

private func snapshotState(
  cursor: String = "10", items: [String] = [Fixtures.itemJSON(id: "task_1")]
) -> StoreState {
  var state = StoreState()
  state.apply(snapshot: Fixtures.snapshot(cursor: cursor, items: items))
  return state
}

@Test("fills every part of the state from a snapshot and takes its cursor")
private func appliesSnapshot() {
  let state = snapshotState(
    cursor: "10", items: [Fixtures.itemJSON(id: "task_1"), Fixtures.itemJSON(id: "task_2")])

  #expect(state.items.keys.sorted() == ["task_1", "task_2"])
  #expect(state.today?.orbit.load == 2)
  #expect(state.views?.counts.agents == 1)
  #expect(state.agents.map(\.id) == ["agent_1"])
  #expect(state.costToday?.ceilingGbp == 15)
  #expect(state.settings?.pushBudgetPerHour == 3)
  #expect(state.lastEventID == 10)
}

@Test("replaces the whole state when a later snapshot arrives")
private func laterSnapshotReplacesState() {
  var state = snapshotState(items: [Fixtures.itemJSON(id: "task_1")])

  state.apply(snapshot: Fixtures.snapshot(cursor: "40", items: [Fixtures.itemJSON(id: "task_2")]))

  #expect(state.items.keys.sorted() == ["task_2"])
  #expect(state.lastEventID == 40)
}

@Test("applies events in id order and ignores an id at or below the last applied one")
private func ignoresRepeatedAndOlderIDs() {
  var state = snapshotState(cursor: "10")
  let first = state.apply(
    event: event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_1", title: "First"))), id: "11")

  let repeated = state.apply(
    event: event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_1", title: "Repeat"))), id: "11")
  let older = state.apply(
    event: event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_1", title: "Older"))), id: "9")
  let atSnapshot = state.apply(
    event: event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_1", title: "Old"))), id: "10")

  #expect(first.applied)
  #expect(!repeated.applied)
  #expect(!older.applied)
  #expect(!atSnapshot.applied)
  #expect(state.items["task_1"]?.title == "First")
  #expect(state.lastEventID == 11)
}

@Test("accepts a gap in event ids, since ids rise but are not consecutive")
private func acceptsGaps() {
  var state = snapshotState(cursor: "10")

  let effects = state.apply(
    event: event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_2"))), id: "25")

  #expect(effects.applied)
  #expect(state.lastEventID == 25)
}

@Test("ignores an event whose id is not a number")
private func ignoresUnparsableID() {
  var state = snapshotState(cursor: "10")

  let effects = state.apply(
    event: event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_2"))), id: "abc")

  #expect(!effects.applied)
  #expect(state.items["task_2"] == nil)
}

@Test("applies a heartbeat without moving the cursor")
private func heartbeatLeavesCursor() {
  var state = snapshotState(cursor: "10")

  let effects = state.apply(event: event(Fixtures.heartbeatJSON), id: nil)

  #expect(effects.applied)
  #expect(state.lastEventID == 10)
}

@Test("replaces the whole item on upsert, with its new version and actions")
private func upsertReplacesWholeItem() {
  var state = snapshotState(items: [Fixtures.itemJSON(id: "task_1", version: 1)])

  state.apply(
    event: event(
      Fixtures.upsertedJSON(
        Fixtures.itemJSON(
          id: "task_1", version: 2, title: "Renamed",
          actions: [.init("done"), .init("snooze", input: "until")]))), id: "11")

  let item = state.items["task_1"]
  #expect(item?.version == 2)
  #expect(item?.title == "Renamed")
  #expect(item?.actions.map(\.id) == ["done", "snooze"])
}

@Test("adds an item on alert.raised and removes it on alert.cleared")
private func alertsComeAndGo() {
  var state = snapshotState()

  state.apply(
    event: event(Fixtures.alertRaisedJSON(Fixtures.itemJSON(id: "alrt_1", alert: true))), id: "11")
  #expect(state.items["alrt_1"]?.kind == .alert)

  let effects = state.apply(event: event(Fixtures.alertClearedJSON("alrt_1")), id: "12")
  #expect(state.items["alrt_1"] == nil)
  #expect(effects.removedItemID == "alrt_1")
}

@Test("removes an item on item.removed")
private func removesItem() {
  var state = snapshotState()

  let effects = state.apply(event: event(Fixtures.removedJSON("task_1")), id: "11")

  #expect(state.items["task_1"] == nil)
  #expect(effects.removedItemID == "task_1")
}

@Test("replaces today, views and settings whole")
private func replacesBlocks() {
  var state = snapshotState()

  state.apply(event: event(Fixtures.todayUpdatedJSON(load: 42)), id: "11")
  state.apply(event: event(Fixtures.viewsUpdatedJSON(tasks: 7)), id: "12")
  state.apply(event: event(Fixtures.settingsUpdatedJSON(pushBudget: 9)), id: "13")

  #expect(state.today?.orbit.load == 42)
  #expect(state.views?.counts.tasks == 7)
  #expect(state.settings?.pushBudgetPerHour == 9)
}

@Test("replaces the agent and today's cost together, and adds an agent it has not seen")
private func replacesAgentAndCost() {
  var state = snapshotState()

  state.apply(event: event(Fixtures.agentUpdatedJSON(state: "paused", cost: 1.5)), id: "11")
  state.apply(event: event(Fixtures.agentUpdatedJSON(id: "agent_2", state: "running")), id: "12")

  #expect(state.agents.map(\.id) == ["agent_1", "agent_2"])
  #expect(state.agents.first?.state == .paused)
  #expect(state.costToday?.costGbp == 0.9)
}

@Test("reports the correlation id an event carries")
private func reportsCorrelationID() {
  var state = snapshotState()

  let effects = state.apply(
    event: event(Fixtures.removedJSON("task_1", correlationId: "corr_1")), id: "11")

  #expect(effects.correlationID == "corr_1")
}

@Test("reports the minimum version from client.deprecated")
private func reportsDeprecation() {
  var state = snapshotState()

  let effects = state.apply(
    event: event(Fixtures.clientDeprecatedJSON(minClientVersion: "0.3.0")), id: "11")

  #expect(effects.deprecatedBelow == "0.3.0")
}
