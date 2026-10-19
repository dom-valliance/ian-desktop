import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

private let nowPillar = FieldCellRef(unitID: "unit_b", horizon: .now)
private let t0: TimeInterval = 1_000

@Suite("Field scene")
struct FieldSceneBuilderTests {
  private func build(
    hasItem: @escaping (String) -> Bool = { _ in true }, removedAt: [String: TimeInterval] = [:],
    selected: FieldCellRef? = nil, openedAt: TimeInterval? = nil, memory: FieldMemory = .init(),
    today: Components.Schemas.Today = TodayScenario.today, now: TimeInterval = t0
  ) -> (scene: FieldSceneModel, memory: FieldMemory) {
    FieldSceneBuilder.build(
      today: today, hasItem: hasItem, removedAt: removedAt, selected: selected,
      openedAt: openedAt, memory: memory, now: now)
  }

  @Test("draws the field's columns in the order sent and a cell for each of its cells")
  func columnsAndCells() {
    let scene = build().scene
    #expect(scene.unitIDs == ["unit_a", "unit_b"])
    #expect(scene.cells == TodayScenario.today.field.cells)
    #expect(scene.sinking.isEmpty)
  }

  @Test("carries the selection and the opening time")
  func selectionAndOpening() {
    let scene = build(selected: nowPillar, openedAt: 42).scene
    #expect(scene.selected == nowPillar)
    #expect(scene.openedAt == 42)
  }

  @Test("sinks a cell whose every item the server has removed, from the time it left")
  func sinksWhenEveryItemRemoved() {
    let scene = build(
      hasItem: { $0 != "alrt_b1" }, removedAt: ["alrt_b1": t0 - 0.3]
    ).scene
    #expect(scene.sinking == [nowPillar: t0 - 0.3])
  }

  @Test("does not sink a cell while one of its items remains")
  func staysWhileAnItemRemains() {
    let scene = build(hasItem: { $0 != "prop_a1" }, removedAt: ["prop_a1": t0]).scene
    #expect(scene.sinking.isEmpty)
  }

  @Test("does not sink a cell for an item that is pending, since the store still holds it")
  func pendingDoesNotSink() {
    #expect(build(hasItem: { _ in true }).scene.sinking.isEmpty)
  }

  @Test("keeps a cell that left Today for 0.7 seconds with its last pressure, then lets it go")
  func ghostKeptForSinkDuration() {
    let first = build(
      hasItem: { $0 != "alrt_b1" }, removedAt: ["alrt_b1": t0])
    let dropped = TodayScenario.today.withoutCell(nowPillar)

    let during = build(
      hasItem: { $0 != "alrt_b1" }, removedAt: [:], memory: first.memory, today: dropped,
      now: t0 + 0.5)
    let ghost = during.scene.cells.first { TodaySelectionModel.ref($0) == nowPillar }
    #expect(ghost?.pressure == 0.9)
    #expect(during.scene.sinking[nowPillar] == t0)
    #expect(during.memory.hasUnfinishedSinking(at: t0 + 0.5))

    let after = build(
      hasItem: { $0 != "alrt_b1" }, removedAt: [:], memory: during.memory, today: dropped,
      now: t0 + 0.75)
    #expect(!after.scene.cells.contains { TodaySelectionModel.ref($0) == nowPillar })
    #expect(after.scene.sinking.isEmpty)
    #expect(!after.memory.hasUnfinishedSinking(at: t0 + 0.75))
  }

  @Test("keeps the sink going when Today and the removal both arrive before the next build")
  func ghostWhenBothUpdatesCoalesce() {
    let before = build()
    let dropped = TodayScenario.today.withoutCell(nowPillar)

    let after = build(
      hasItem: { $0 != "alrt_b1" }, removedAt: [:], memory: before.memory, today: dropped,
      now: t0 + 0.1)

    #expect(after.scene.sinking[nowPillar] == t0 + 0.1)
    #expect(after.scene.cells.contains { TodaySelectionModel.ref($0) == nowPillar })
  }

  @Test("keeps a column while a cell of the unit that left is still sinking, then drops it")
  func columnStaysWhileDepartingCellSinks() {
    let before = build()
    var withoutUnitB = TodayScenario.today
    withoutUnitB.field.units.removeAll { $0.id == "unit_b" }
    withoutUnitB.field.cells.removeAll { $0.unitId == "unit_b" }
    let gone: (String) -> Bool = { !["alrt_b1", "task_b2"].contains($0) }

    let during = build(
      hasItem: gone, memory: before.memory, today: withoutUnitB, now: t0 + 0.2)
    #expect(during.scene.unitIDs == ["unit_a", "unit_b"])
    #expect(during.scene.sinking[nowPillar] == t0 + 0.2)

    let after = build(
      hasItem: gone, memory: during.memory, today: withoutUnitB, now: t0 + 0.2 + 0.75)
    #expect(after.scene.unitIDs == ["unit_a"])
    #expect(after.scene.cells.allSatisfy { $0.unitId == "unit_a" })
  }

  @Test("lets a cell that moved away go at once, since its items still exist")
  func movedCellDoesNotSink() {
    let before = build()
    let dropped = TodayScenario.today.withoutCell(nowPillar)

    let after = build(memory: before.memory, today: dropped, now: t0 + 0.1)

    #expect(!after.scene.cells.contains { TodaySelectionModel.ref($0) == nowPillar })
    #expect(after.scene.sinking.isEmpty)
  }
}

extension Components.Schemas.Today {
  fileprivate func withoutCell(_ pillar: FieldCellRef) -> Self {
    var today = self
    today.field.cells.removeAll { TodaySelectionModel.ref($0) == pillar }
    return today
  }
}

/// The store feeding the builder through the model, as the Today view does.
@Suite("Field scene from the store")
@MainActor
struct FieldSceneStoreTests {
  @Test("sinks a pillar after item.removed, and not after the action's click")
  func sinksOnTheEventNotTheClick() async {
    let (store, service, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    let model = TodayModel()
    let now = Date().timeIntervalSinceReferenceDate

    await store.run(actionID: "act_later", on: "alrt_b1", until: Date().addingTimeInterval(60))
    #expect(service.actionCalls.count == 1)
    #expect(store.pending["alrt_b1"] != nil)
    model.refresh(store: store, openedAt: nil, now: now)
    #expect(model.scene?.sinking.isEmpty == true)

    await TodayScenario.send(Fixtures.removedJSON("alrt_b1"), id: 11, to: feed, on: store)
    model.refresh(store: store, openedAt: nil, now: now)
    #expect(model.scene?.sinking.keys.contains(nowPillar) == true)
  }

  @Test("keeps the sinking cell for 0.7 seconds after today.updated drops it")
  func keepsCellAfterTodayUpdate() async {
    let (store, _, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    let model = TodayModel()
    let start = Date().timeIntervalSinceReferenceDate

    await TodayScenario.send(Fixtures.removedJSON("alrt_b1"), id: 11, to: feed, on: store)
    model.refresh(store: store, openedAt: nil, now: start)
    await TodayScenario.send(
      TodayScenario.todayUpdatedJSON(dropping: ["alrt_b1"]), id: 12, to: feed, on: store)
    #expect(store.removals["alrt_b1"] != nil)

    let stillSinking = model.refresh(store: store, openedAt: nil, now: start + 0.3)
    #expect(stillSinking)
    #expect(
      model.scene?.cells.contains { TodaySelectionModel.ref($0) == nowPillar } == true)

    let finished = model.refresh(store: store, openedAt: nil, now: start + 0.8)
    #expect(!finished)
    #expect(
      model.scene?.cells.contains { TodaySelectionModel.ref($0) == nowPillar } == false)
  }

  @Test("selects the pillar holding the selected row in the scene")
  func sceneSelectsPillarOfRow() async {
    let (store, _, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let model = TodayModel()

    model.select(.item("cmt_a2"))
    model.refresh(store: store, openedAt: 7, now: 0)

    #expect(model.scene?.selected == FieldCellRef(unitID: "unit_a", horizon: .now))
    #expect(model.scene?.openedAt == 7)
  }

  @Test("selects the first item's row from a pillar and keeps it while the removal record lives")
  func pillarSelectsRowAndRemovedSelectionStays() async {
    let (store, _, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    let model = TodayModel()
    let today = TodayScenario.today

    model.selectPillar(FieldCellRef(unitID: "unit_a", horizon: .now), in: today)
    #expect(model.resolvedSelection(in: store) == .item("prop_a1"))

    await TodayScenario.send(Fixtures.removedJSON("prop_a1"), id: 11, to: feed, on: store)
    await TodayScenario.send(
      TodayScenario.todayUpdatedJSON(dropping: ["prop_a1"]), id: 12, to: feed, on: store)

    #expect(model.resolvedSelection(in: store) == .item("prop_a1"))
  }

  @Test("drops a selection once the item's removal record has expired")
  func expiredRemovalDropsSelection() async {
    let clock = ManualClock()
    let (store, _, feed) = await TodayScenario.liveStore(clock: clock)
    defer { store.stop() }
    let model = TodayModel()
    model.select(.item("prop_a1"))

    await TodayScenario.send(Fixtures.removedJSON("prop_a1"), id: 11, to: feed, on: store)
    #expect(model.resolvedSelection(in: store) == .item("prop_a1"))
    _ = await eventually("the expiry timer") {
      await clock.requestedSleeps.contains(IanStore.removalLifetime)
    }
    await clock.advance(by: .seconds(10))
    _ = await eventually("expiry") { await MainActor.run { store.removals.isEmpty } }

    #expect(model.resolvedSelection(in: store) == nil)
  }
}
