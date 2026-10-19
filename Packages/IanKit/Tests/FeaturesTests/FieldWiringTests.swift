import AppKit
import Attention
import Contract
import Store
import Surface
import TestSupport
import Testing

@testable import Features

@Suite("Field wiring")
@MainActor
struct FieldWiringTests {
  private func sceneAfterRefresh() async -> (PillarsScene, IanStore) {
    let (store, _, _) = await TodayScenario.liveStore()
    let model = TodayModel()
    model.select(.item("cmt_a2"))
    model.refresh(store: store, openedAt: 7, now: 100)
    return (model.scene!.pillarsScene, store)
  }

  @Test("maps the scene's columns, cells and kinds in the order sent")
  func mapsUnitsAndKinds() async {
    let (scene, store) = await sceneAfterRefresh()
    defer { store.stop() }

    #expect(scene.unitIDs == ["unit_a", "unit_b"])
    #expect(
      scene.cells.map(\.key) == [
        PillarCellKey(unitID: "unit_a", horizon: .now),
        PillarCellKey(unitID: "unit_a", horizon: .week),
        PillarCellKey(unitID: "unit_a", horizon: .later),
        PillarCellKey(unitID: "unit_b", horizon: .now),
        PillarCellKey(unitID: "unit_b", horizon: .later),
      ])
    #expect(scene.cells.map(\.kind) == [.proposal, .task, .task, .alert, .task])
    #expect(scene.cells.map(\.pressure) == [0.8, 0.4, 0.2, 0.9, 0.1])
    #expect(scene.openedAt == 7)
  }

  @Test("maps the selected pillar from the selected row")
  func mapsSelection() async {
    let (scene, store) = await sceneAfterRefresh()
    defer { store.stop() }
    #expect(scene.selected == PillarCellKey(unitID: "unit_a", horizon: .now))
  }

  @Test("maps every kind to the field's kind and every horizon to its row")
  func mapsKindsAndHorizons() {
    for kind in Components.Schemas.ItemKind.allCases {
      #expect(
        ItemKindStyle.colour(kind) == KindPalette.colour(for: ItemKindStyle.pillarKind(kind)).color)
    }
    #expect(FieldCellRef(unitID: "u", horizon: .later).pillarKey.horizon == .later)
    #expect(FieldCellRef(unitID: "u", horizon: .week).pillarKey.horizon == .week)
    #expect(FieldCellRef(PillarCellKey(unitID: "u", horizon: .now)).horizon == .now)
  }

  @Test("maps sinking cells to the field's keys with their start times")
  func mapsSinking() async {
    let (store, _, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    let model = TodayModel()
    await TodayScenario.send(Fixtures.removedJSON("alrt_b1"), id: 11, to: feed, on: store)

    model.refresh(store: store, openedAt: nil, now: 50)

    #expect(
      model.scene?.pillarsScene.sinking.keys.contains(
        PillarCellKey(unitID: "unit_b", horizon: .now)) == true)
  }

  @Test("selects the row when the field reports a tap on a pillar")
  func fieldTapSelectsRow() {
    let model = TodayModel()
    let today = TodayScenario.today

    model.selectPillar(PillarCellKey(unitID: "unit_a", horizon: .now), in: today)
    #expect(model.selection == .item("prop_a1"))
    model.selectPillar(PillarCellKey(unitID: "unit_a", horizon: .week), in: today)
    #expect(model.selection == .week(unitID: "unit_a"))
    model.selectPillar(PillarCellKey(unitID: "unit_b", horizon: .later), in: today)
    #expect(model.selection == .later(unitID: "unit_b"))
  }

  @Test("opens the Settings view when the Settings command runs")
  func settingsCommandShowsSettings() async {
    _ = NSApplication.shared
    let (store, _, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let defaults = UserDefaults(suiteName: "ian.tests.\(UUID().uuidString)")!
    let controller = SurfaceController(
      store: store, signals: SuppressionSignals(camera: IdleCamera()), defaults: defaults,
      quit: {})
    let model = ClientModel()
    _ = ExpandedClientView(store: store, controller: controller, model: model)
    #expect(model.section == .today)

    controller.perform(.openSettings)

    #expect(model.section == .settings)
    controller.hideExpanded()
  }
}

@MainActor
private final class IdleCamera: CameraMonitoring {
  var isLive = false
  func start(onChange: @escaping @MainActor () -> Void) {}
  func stop() {}
}
