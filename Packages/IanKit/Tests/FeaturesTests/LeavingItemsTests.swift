import Client
import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

private func viewsJSON(proposals: [(id: String, ids: [String])], alerts: String = "[]") -> String {
  let groups = proposals.map { group in
    let ids = group.ids.map { "\"\($0)\"" }.joined(separator: ",")
    return "{\"id\":\"\(group.id)\",\"label\":\"Group \(group.id)\",\"itemIds\":[\(ids)]}"
  }.joined(separator: ",")
  return """
    {"counts":{"today":0,"proposals":0,"commitments":0,"tasks":0,"alerts":0,"agents":1},\
    "proposals":[\(groups)],"commitments":{"owedByMe":[],"owedToMe":[],"toConfirm":[]},\
    "tasks":[],"alerts":\(alerts)}
    """
}

private struct Harness {
  let store: IanStore
  let clock: ManualClock
  let feed: AsyncThrowingStream<StreamMessage, any Error>.Continuation
}

@MainActor
private func liveHarness(_ views: String) async -> Harness {
  let items = ["prop_1", "prop_2", "prop_3"].map { Fixtures.itemJSON(id: $0) }
  let service = ScriptedService(
    snapshots: [.success(Fixtures.snapshot(cursor: "10", items: items, views: views))])
  let feed = service.planStream()
  let clock = ManualClock()
  let store = IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: clock,
    jitter: { 1 })
  store.start()
  _ = await eventually("live") { await MainActor.run { store.connection == .live } }
  return Harness(store: store, clock: clock, feed: feed)
}

@MainActor
private func send(_ harness: Harness, _ json: String, id: String) async {
  harness.feed.yield(.event(id: id, Fixtures.event(json)))
  _ = await eventually("event \(id)") {
    await MainActor.run { harness.store.state.lastEventID == UInt64(id) }
  }
}

@MainActor
private func removeThenUpdateViews(_ harness: Harness, remaining: [(id: String, ids: [String])])
  async
{
  await send(harness, Fixtures.removedJSON("prop_2", outcome: "Approved."), id: "11")
  await send(
    harness, "{\"type\":\"views.updated\",\"views\":\(viewsJSON(proposals: remaining))}", id: "12")
}

@MainActor
@Suite("Leaving items stay in their view")
struct LeavingItemsTests {
  private let before = [(id: "g", ids: ["prop_1", "prop_2", "prop_3"])]

  @Test("keeps a removed item's card in place with its outcome until its record expires")
  func staysInPlaceUntilExpiry() async {
    let harness = await liveHarness(viewsJSON(proposals: before))
    defer { harness.store.stop() }

    await removeThenUpdateViews(harness, remaining: [(id: "g", ids: ["prop_1", "prop_3"])])

    let kept = ProposalsListModel(state: harness.store.state, removals: harness.store.removals)
    #expect(kept.groups.map { $0.entries.map(\.id) } == [["prop_1", "prop_2", "prop_3"]])
    #expect(kept.groups.first?.entries[1].removal?.outcome == "Approved.")

    await harness.clock.waitForSleepers()
    await harness.clock.advance(by: IanStore.removalLifetime + .seconds(1))
    _ = await eventually("expiry") { await MainActor.run { harness.store.removals.isEmpty } }

    let gone = ProposalsListModel(state: harness.store.state, removals: harness.store.removals)
    #expect(gone.groups.map { $0.entries.map(\.id) } == [["prop_1", "prop_3"]])
  }

  @Test("keeps the card in its group when the server drops the whole group")
  func groupDroppedToo() async {
    let harness = await liveHarness(
      viewsJSON(proposals: [(id: "a", ids: ["prop_1"]), (id: "b", ids: ["prop_2"])]))
    defer { harness.store.stop() }

    await removeThenUpdateViews(harness, remaining: [(id: "a", ids: ["prop_1"])])

    let kept = ProposalsListModel(state: harness.store.state, removals: harness.store.removals)
    #expect(kept.groups.map(\.id) == ["a", "b"])
    #expect(kept.groups.last?.entries.map(\.id) == ["prop_2"])
  }

  @Test("lets the server's own position win when its views still name the item")
  func serverPositionWins() async {
    let harness = await liveHarness(viewsJSON(proposals: before))
    defer { harness.store.stop() }

    await removeThenUpdateViews(
      harness, remaining: [(id: "g", ids: ["prop_2", "prop_1", "prop_3"])])

    let model = ProposalsListModel(state: harness.store.state, removals: harness.store.removals)
    #expect(model.groups.map { $0.entries.map(\.id) } == [["prop_2", "prop_1", "prop_3"]])
  }
}
