import Client
import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

private let launchTime = Date(timeIntervalSince1970: 1_792_137_600)

private struct Harness {
  let store: IanStore
  let clock: ManualClock
  let feed: AsyncThrowingStream<StreamMessage, any Error>.Continuation
}

/// A started, live store holding `task_1` and `alrt_1`, with Today naming both.
@MainActor
private func liveHarness() async -> Harness {
  let today = Fixtures.todayJSON(load: 2, itemIDs: ["task_1", "alrt_1"])
  let items = [
    Fixtures.itemJSON(id: "task_1", version: 3),
    Fixtures.itemJSON(id: "alrt_1", alert: true, version: 2),
  ]
  let service = ScriptedService(snapshots: [
    .success(Fixtures.snapshot(cursor: "10", items: items, today: today))
  ])
  let feed = service.planStream()
  let clock = ManualClock()
  let store = IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: clock,
    jitter: { 1 }, now: { launchTime })
  store.start()
  _ = await eventually("live") { await MainActor.run { store.connection == .live } }
  return Harness(store: store, clock: clock, feed: feed)
}

@MainActor
private func apply(_ harness: Harness, _ json: String, id: String) async {
  harness.feed.yield(.event(id: id, Fixtures.event(json)))
  _ = await eventually("event \(id)") {
    await MainActor.run { harness.store.state.lastEventID == UInt64(id) }
  }
}

private func todayUpdated(naming ids: [String]) -> String {
  "{\"type\":\"today.updated\",\"today\":\(Fixtures.todayJSON(load: ids.count, itemIDs: ids))}"
}

@MainActor
@Suite("Removal record")
struct RemovalTests {
  @Test("keeps the removed item, its outcome and the time it left")
  func keepsRemovedItem() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }

    await apply(harness, Fixtures.removedJSON("task_1", outcome: "Settled."), id: "11")

    let removal = harness.store.removals["task_1"]
    #expect(removal?.item.id == "task_1")
    #expect(removal?.item.version == 3)
    #expect(removal?.outcome == "Settled.")
    #expect(removal?.removedAt == launchTime)
    #expect(harness.store.state.items["task_1"] == nil)
  }

  @Test("keeps a cleared alert, which carries no outcome")
  func keepsClearedAlert() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }

    await apply(harness, Fixtures.alertClearedJSON("alrt_1"), id: "11")

    #expect(harness.store.removals["alrt_1"]?.item.id == "alrt_1")
    #expect(harness.store.removals["alrt_1"]?.outcome == nil)
  }

  @Test("keeps no record for an item the store never held")
  func ignoresUnknownItem() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }

    await apply(harness, Fixtures.removedJSON("task_9"), id: "11")

    #expect(harness.store.removals.isEmpty)
  }

  @Test("keeps the record while Today still names the item")
  func keepsRecordWhileTodayNamesIt() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }
    await apply(harness, Fixtures.removedJSON("task_1"), id: "11")

    await apply(harness, todayUpdated(naming: ["task_1", "alrt_1"]), id: "12")

    #expect(harness.store.removals["task_1"] != nil)
  }

  @Test("clears the record when a later today update no longer names the item")
  func clearsWhenTodayDropsItem() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }
    await apply(harness, Fixtures.removedJSON("task_1"), id: "11")
    await apply(harness, Fixtures.alertClearedJSON("alrt_1"), id: "12")

    await apply(harness, todayUpdated(naming: ["alrt_1"]), id: "13")

    #expect(harness.store.removals["task_1"] == nil)
    #expect(harness.store.removals["alrt_1"] != nil)
  }

  @Test("clears the record when the item comes back")
  func clearsWhenItemReturns() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }
    await apply(harness, Fixtures.removedJSON("task_1"), id: "11")

    await apply(
      harness, Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_1", version: 4)), id: "12")

    #expect(harness.store.removals["task_1"] == nil)
  }

  @Test("clears the record after ten seconds and not before")
  func clearsAfterTenSeconds() async {
    let harness = await liveHarness()
    defer { harness.store.stop() }
    await apply(harness, Fixtures.removedJSON("task_1"), id: "11")
    #expect(
      await eventually("the expiry timer") {
        await harness.clock.requestedSleeps.contains(IanStore.removalLifetime)
      })

    await harness.clock.advance(by: .seconds(9))
    try? await Task.sleep(for: .milliseconds(20))
    #expect(harness.store.removals["task_1"] != nil)

    await harness.clock.advance(by: .seconds(1))
    #expect(await eventually("expiry") { await MainActor.run { harness.store.removals.isEmpty } })
  }

  @Test("names an item only while the snapshot's Today lists it")
  func todayNamesItemsItLists() async {
    var state = StoreState()
    state.apply(
      snapshot: Fixtures.snapshot(
        items: [Fixtures.itemJSON(id: "task_1")],
        today: Fixtures.todayJSON(load: 1, itemIDs: ["task_1"])))
    #expect(state.todayNames("task_1"))

    state.apply(snapshot: Fixtures.snapshot(items: [], today: Fixtures.todayJSON(load: 0)))

    #expect(!state.todayNames("task_1"))
  }
}
