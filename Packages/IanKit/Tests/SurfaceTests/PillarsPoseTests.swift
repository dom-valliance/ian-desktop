import Testing

@testable import Surface

@Suite("Pillars pose while stopped")
struct PillarsPoseTests {
  private let key = PillarCellKey(unitID: "u", horizon: .now)

  private func scene(openedAt: Double?) -> PillarsScene {
    PillarsScene(
      unitIDs: ["u"],
      cells: [PillarCell(key: key, pressure: 0.8, kind: .proposal, working: false)],
      selected: nil, openedAt: openedAt, sinking: [:])
  }

  @Test("draws every pillar at full opacity when the clock is stopped just after it opened")
  func stoppedFieldIsNotBlank() {
    let opened = 1_000.0
    let scene = scene(openedAt: opened)
    // A clock frozen at the moment of opening, as a suppressed field's would be.
    let frozen = opened - 0.01

    let blank = PillarsRenderer.drawing(for: scene, time: frozen, reducedMotion: true)
    #expect(blank.cells.contains { $0.opacity < 1 })

    for reduced in [true, false] {
      let time = PillarsFieldView.drawTime(scene: scene, isAnimating: false, clock: frozen)
      let drawing = PillarsRenderer.drawing(for: scene, time: time, reducedMotion: reduced)
      #expect(drawing.cells.allSatisfy { $0.opacity == 1 })
      #expect(
        drawing.cells
          == PillarsRenderer.drawing(
            for: self.scene(openedAt: nil), time: time, reducedMotion: reduced
          ).cells)
    }
  }

  @Test("follows the clock while the field animates")
  func animatingFieldFollowsClock() {
    let scene = scene(openedAt: 1_000)
    #expect(PillarsFieldView.drawTime(scene: scene, isAnimating: true, clock: 1_000.1) == 1_000.1)
  }
}
