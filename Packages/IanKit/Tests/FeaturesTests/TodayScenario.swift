import Client
import Contract
import Foundation
import Store
import TestSupport

@testable import Features

/// Invented Today data covering every kind and horizon, in an order a client would get wrong if
/// it sorted. Titles and units are placeholders (AGENTS.md, Data).
///
/// - Units: `unit_a` "[CLIENT A]", `unit_b` "[CLIENT B]".
/// - Now: the alert first, then two items of `unit_a`.
/// - Week: two items of `unit_a`. Later: `unit_a` holds a task and a proposal, `unit_b` a task.
enum TodayScenario {
  typealias Schemas = Components.Schemas

  static let approve = Schemas.ItemAction(
    id: "act_yes", label: "Go ahead", style: .primary, confirm: nil, input: .none)
  static let decline = Schemas.ItemAction(
    id: "act_no", label: "Not this one", style: .secondary, confirm: "Decline this?", input: .none)
  static let snooze = Schemas.ItemAction(
    id: "act_later", label: "Come back to it", style: .quiet, confirm: nil, input: .until)
  static let chase = Schemas.ItemAction(
    id: "act_nudge", label: "Nudge", style: .secondary, confirm: nil, input: .note)

  static func item(
    _ id: String, kind: Schemas.ItemKind, unit: String, horizon: Schemas.Horizon,
    title: String? = nil, actions: [Schemas.ItemAction] = [approve, decline]
  ) -> Schemas.Item {
    var item = Fixtures.item(id: id, title: title ?? "Title of \(id)")
    item.kind = kind
    item.unit = Schemas.Unit(id: unit, name: unit == "unit_a" ? "[CLIENT A]" : "[CLIENT B]")
    item.horizon = horizon
    item.actions = actions
    item.meta = "Meta of \(id)"
    return item
  }

  static let items: [Schemas.Item] = [
    item("alrt_b1", kind: .alert, unit: "unit_b", horizon: .now, actions: [snooze]),
    item("prop_a1", kind: .proposal, unit: "unit_a", horizon: .now),
    item("cmt_a2", kind: .commitmentBy, unit: "unit_a", horizon: .now, actions: [chase]),
    item("task_a3", kind: .task, unit: "unit_a", horizon: .week),
    item("cmt_a4", kind: .commitmentTo, unit: "unit_a", horizon: .week),
    item("task_a5", kind: .task, unit: "unit_a", horizon: .later),
    item("prop_a6", kind: .proposal, unit: "unit_a", horizon: .later),
    item("task_b2", kind: .task, unit: "unit_b", horizon: .later),
  ]

  static let todayJSON = """
    {"orbit":{"itemIds":["alrt_b1","prop_a1","cmt_a2"],"overflow":0,"nowCount":3,\
    "urgentCount":1,"load":8,"median":12,"working":false},
    "field":{"units":[{"id":"unit_a","name":"[CLIENT A]"},{"id":"unit_b","name":"[CLIENT B]"}],\
    "cells":[
    {"unitId":"unit_a","horizon":"now","itemIds":["prop_a1","cmt_a2"],"pressure":0.8,\
    "kind":"proposal","working":false},
    {"unitId":"unit_a","horizon":"week","itemIds":["task_a3","cmt_a4"],"pressure":0.4,\
    "kind":"task","working":false},
    {"unitId":"unit_a","horizon":"later","itemIds":["task_a5","prop_a6"],"pressure":0.2,\
    "kind":"task","working":false},
    {"unitId":"unit_b","horizon":"now","itemIds":["alrt_b1"],"pressure":0.9,\
    "kind":"alert","working":false},
    {"unitId":"unit_b","horizon":"later","itemIds":["task_b2"],"pressure":0.1,\
    "kind":"task","working":false}]},
    "lists":{"now":["alrt_b1","prop_a1","cmt_a2"],\
    "week":[{"unitId":"unit_a","itemIds":["task_a3","cmt_a4"]}],\
    "later":[{"unitId":"unit_a","counts":[{"kind":"task","count":1},{"kind":"proposal","count":1}]},\
    {"unitId":"unit_b","counts":[{"kind":"task","count":1}]}]},
    "context":{"inExternalMeeting":false,"quietHoursActive":false}}
    """

  static let viewsJSON = """
    {"counts":{"today":8,"proposals":2,"commitments":2,"tasks":3,"alerts":1,"agents":4},\
    "proposals":[],"commitments":{"owedByMe":[],"owedToMe":[],"toConfirm":[]},\
    "tasks":[],"alerts":[]}
    """

  static var today: Schemas.Today { Fixtures.decode(todayJSON) }

  static var snapshot: Schemas.Snapshot {
    var snapshot = Fixtures.snapshot(today: todayJSON, views: viewsJSON)
    snapshot.items = items
    return snapshot
  }

  static var state: StoreState {
    var state = StoreState()
    state.apply(snapshot: snapshot)
    return state
  }

  /// `today.updated` for the scenario without the items named.
  static func todayUpdatedJSON(dropping ids: Set<String>) -> String {
    var today = today
    today.orbit.itemIds.removeAll { ids.contains($0) }
    today.lists.now.removeAll { ids.contains($0) }
    for index in today.field.cells.indices {
      today.field.cells[index].itemIds.removeAll { ids.contains($0) }
    }
    today.field.cells.removeAll { $0.itemIds.isEmpty }
    for index in today.lists.week.indices {
      today.lists.week[index].itemIds.removeAll { ids.contains($0) }
    }
    today.lists.week.removeAll { $0.itemIds.isEmpty }
    return todayEventJSON(today)
  }

  private static func todayEventJSON(_ today: Schemas.Today) -> String {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(today),
      let json = String(data: data, encoding: .utf8)
    else { preconditionFailure("The scenario's Today does not encode.") }
    return "{\"type\":\"today.updated\",\"today\":\(json)}"
  }

  /// A started, live store holding the scenario.
  @MainActor
  static func liveStore(
    service: ScriptedService = ScriptedService(snapshots: [.success(snapshot)])
  ) async -> (store: IanStore, service: ScriptedService, feed: Feed) {
    let feed = service.planStream()
    let store = IanStore(
      service: service, profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0),
      clock: ManualClock(), jitter: { 1 })
    store.start()
    _ = await eventually("live") { await MainActor.run { store.connection == .live } }
    return (store, service, feed)
  }

  typealias Feed = AsyncThrowingStream<StreamMessage, any Error>.Continuation

  @MainActor
  static func send(_ json: String, id: Int, to feed: Feed, on store: IanStore) async {
    feed.yield(.event(id: String(id), Fixtures.event(json)))
    _ = await eventually("event \(id)") {
      await MainActor.run { store.state.lastEventID == UInt64(id) }
    }
  }
}
