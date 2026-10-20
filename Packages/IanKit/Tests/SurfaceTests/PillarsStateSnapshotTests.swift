import AppKit
import SnapshotTesting
import Testing

@testable import Surface

/// The field states the four scenarios never reach: a selected pillar, a pillar mid-sink, the
/// field mid-growth, no units, fewer than five, and every kind at the pressure limits. Each is
/// drawn with motion on and off at a fixed time, through the renderer and painter the app uses.
@Suite("Pillars state snapshots")
@MainActor
struct PillarsStateSnapshotTests {
  fileprivate nonisolated static let time = 3.0

  enum State: String, CaseIterable {
    case selected
    case selectedAlert = "selected-alert"
    case sinking
    case growing
    case empty
    case twoUnits = "two-units"
    case everyKind = "every-kind"

    var scene: PillarsScene {
      switch self {
      case .selected:
        var scene = OrbitScenario.load("normal").pillarsScene
        scene.selected = PillarCellKey(unitID: "unit_internal", horizon: .week)
        return scene
      case .selectedAlert:
        var scene = OrbitScenario.load("incident").pillarsScene
        scene.selected = PillarCellKey(unitID: "other", horizon: .now)
        return scene
      case .sinking:
        var scene = OrbitScenario.load("normal").pillarsScene
        scene.sinking[PillarCellKey(unitID: "unit_client_b", horizon: .now)] =
          PillarsStateSnapshotTests.time - 0.25
        return scene
      case .growing:
        var scene = OrbitScenario.load("normal").pillarsScene
        scene.openedAt = PillarsStateSnapshotTests.time - 0.35
        return scene
      case .empty:
        return PillarsScene(unitIDs: [], cells: [], selected: nil, openedAt: nil, sinking: [:])
      case .twoUnits:
        return PillarsScene(
          unitIDs: ["unit_a", "unit_b"],
          cells: [
            PillarCell(
              key: .init(unitID: "unit_a", horizon: .now), pressure: 0.9, kind: .alert,
              working: false),
            PillarCell(
              key: .init(unitID: "unit_a", horizon: .later), pressure: 0.3, kind: .task,
              working: false),
          ], selected: nil, openedAt: nil, sinking: [:])
      case .everyKind:
        let kinds: [PillarKind] = [.proposal, .commitmentBy, .commitmentTo, .task, .alert]
        let pressures = [0.0, 0.25, 0.5, 0.75, 1.0]
        var cells: [PillarCell] = []
        for (column, kind) in kinds.enumerated() {
          for horizon in PillarHorizon.allCases {
            let pressure = horizon == .now ? pressures[column] : pressures[4 - column]
            cells.append(
              PillarCell(
                key: .init(unitID: "unit_\(column)", horizon: horizon), pressure: pressure,
                kind: kind, working: horizon == .now && (column == 0 || column == 4)))
          }
        }
        return PillarsScene(
          unitIDs: (0..<5).map { "unit_\($0)" }, cells: cells, selected: nil, openedAt: nil,
          sinking: [:])
      }
    }
  }

  private func image(_ state: State, reducedMotion: Bool) -> NSImage {
    let drawing = PillarsRenderer.drawing(
      for: state.scene, time: Self.time, reducedMotion: reducedMotion)
    return PillarsBitmap.image(of: drawing, scale: 2)
  }

  @Test("matches the reference with motion on", arguments: State.allCases)
  func motionOn(state: State) {
    assertSnapshot(
      of: image(state, reducedMotion: false),
      as: .image(precision: 0.998, perceptualPrecision: 0.98),
      named: "\(state.rawValue)-motion-on", testName: "pillars")
  }

  @Test("matches the reference with motion off", arguments: State.allCases)
  func motionOff(state: State) {
    assertSnapshot(
      of: image(state, reducedMotion: true),
      as: .image(precision: 0.998, perceptualPrecision: 0.98),
      named: "\(state.rawValue)-motion-off", testName: "pillars")
  }

  @Test("draws at most five columns, however many units the scene names")
  func capsColumns() {
    var scene = State.everyKind.scene
    scene.unitIDs += ["unit_5", "unit_6"]
    let drawing = PillarsRenderer.drawing(for: scene, time: Self.time, reducedMotion: true)
    #expect(drawing.cells.count == 15)
  }
}
