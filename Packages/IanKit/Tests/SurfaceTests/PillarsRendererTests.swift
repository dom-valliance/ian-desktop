import Foundation
import Testing

@testable import Surface

@Suite("Pillars renderer")
struct PillarsRendererTests {
  private let units = ["a", "b", "c", "d", "e"]
  private let half = 0.5.squareRoot()

  private func key(_ column: Int, _ horizon: PillarHorizon = .now) -> PillarCellKey {
    PillarCellKey(unitID: units[column], horizon: horizon)
  }

  private func scene(
    _ cells: [PillarCell] = [], selected: PillarCellKey? = nil, openedAt: Double? = nil,
    sinking: [PillarCellKey: Double] = [:]
  ) -> PillarsScene {
    PillarsScene(
      unitIDs: units, cells: cells, selected: selected, openedAt: openedAt, sinking: sinking)
  }

  private func cell(
    _ key: PillarCellKey, pressure: Double = 1, kind: PillarKind = .proposal,
    working: Bool = false
  ) -> PillarCell {
    PillarCell(key: key, pressure: pressure, kind: kind, working: working)
  }

  private func drawing(
    _ scene: PillarsScene, time: Double = 0, reduced: Bool = false
  ) -> PillarsDrawing {
    PillarsRenderer.drawing(for: scene, time: time, reducedMotion: reduced)
  }

  private func drawnCell(_ drawing: PillarsDrawing, _ key: PillarCellKey) throws
    -> PillarsDrawing.Cell
  {
    try #require(drawing.cells.first { $0.key == key })
  }

  /// How far the top face sits above the footprint, in box units.
  private func height(_ cell: PillarsDrawing.Cell) throws -> Double {
    let top = try #require(cell.faces.last)
    return cell.tile.points[0].y - top.points[0].y
  }

  // MARK: Projection

  @Test("projects the grid origin to the box origin at 45 degrees")
  func projectsOrigin() {
    let point = PillarsRenderer.project(0, 0, 0, yaw: .pi / 4)
    #expect(abs(point.x - 300) < 1e-9)
    #expect(abs(point.y - 250) < 1e-9)
  }

  @Test("projects a point along x, raised by its height, from the README formula")
  func projectsAlongX() {
    let point = PillarsRenderer.project(64, 0, 30, yaw: .pi / 4)
    #expect(abs(point.x - (300 + 64 * half)) < 1e-9)
    #expect(abs(point.y - (250 + 64 * half * 0.52 - 30)) < 1e-9)
  }

  @Test("projects a point along z from the README formula")
  func projectsAlongZ() {
    let point = PillarsRenderer.project(0, 64, 0, yaw: .pi / 4)
    #expect(abs(point.x - (300 - 64 * half)) < 1e-9)
    #expect(abs(point.y - (250 + 64 * half * 0.52)) < 1e-9)
  }

  @Test("turns the yaw by 10 degrees at most and holds 45 degrees under Reduce Motion")
  func yawRange() {
    let peak = (.pi / 2) / 0.22
    #expect(abs(PillarsRenderer.yaw(time: peak, reducedMotion: false) - 55 * .pi / 180) < 1e-9)
    #expect(abs(PillarsRenderer.yaw(time: 0, reducedMotion: false) - .pi / 4) < 1e-9)
    #expect(PillarsRenderer.yaw(time: peak, reducedMotion: true) == .pi / 4)
  }

  // MARK: Order, faces and shades

  @Test("draws all fifteen cells back to front at 45 degrees")
  func drawOrder() {
    let drawing = drawing(scene())
    #expect(drawing.cells.count == 15)
    let depths = drawing.cells.map { cell in
      let column = Double(units.firstIndex(of: cell.key.unitID)! - 2)
      return (column + Double(cell.key.horizon.rawValue - 1)) * 64 * half
    }
    #expect(depths == depths.sorted())
    #expect(drawing.cells.first?.key == key(0, .later))
    #expect(drawing.cells.last?.key == key(4, .now))
  }

  @Test("draws only the two faces that look towards the viewer, then the top")
  func visibleFaces() throws {
    let cell = try drawnCell(drawing(scene([cell(key(2))])), key(2))
    #expect(cell.faces.count == 3)
  }

  @Test("shades each face towards the ground from the README formula")
  func shades() throws {
    let cell = try drawnCell(drawing(scene([cell(key(2), kind: .proposal)])), key(2))
    func shade(_ m: Double) -> OrbitColour {
      func mix(_ k: Double) -> Double { (23 + (k - 23) * m).rounded() }
      return OrbitColour(mix(240), mix(185), mix(226))
    }
    #expect(cell.faces[0].fill == shade(0.6 + 0.2 * (half + 1) / 2))
    #expect(cell.faces[1].fill == shade(0.6 + 0.2 * (1 - half) / 2))
    #expect(cell.faces[2].fill == shade(0.96))
  }

  // MARK: Height

  @Test(
    "raises a pillar by 14 plus pressure times 120",
    arguments: [(0.0, 14.0), (0.5, 74.0), (1.0, 134.0)])
  func heights(pressure: Double, expected: Double) throws {
    let cell = try drawnCell(drawing(scene([cell(key(2), pressure: pressure)])), key(2))
    #expect(abs(try height(cell) - expected) < 1e-9)
  }

  @Test("ripples the selected pillar and its neighbours from the selected cell")
  func ripple() throws {
    let cells = [cell(key(2)), cell(key(3))]
    let drawing = drawing(scene(cells, selected: key(2)), time: 0.5)
    let selected = 134 + 4 * sin(-2.6 * 0.5)
    let neighbour = 134 + 4 * sin(0.8 - 2.6 * 0.5)
    #expect(abs(try height(drawnCell(drawing, key(2))) - selected) < 1e-9)
    #expect(abs(try height(drawnCell(drawing, key(3))) - neighbour) < 1e-9)
  }

  @Test("draws no ripple under Reduce Motion")
  func noRippleWhenReduced() throws {
    let drawing = drawing(scene([cell(key(2))], selected: key(2)), time: 0.5, reduced: true)
    #expect(abs(try height(drawnCell(drawing, key(2))) - 134) < 1e-9)
  }

  // MARK: Growth and sinking

  @Test("grows from nothing to full height over 0.6 seconds, easing out")
  func growCurve() throws {
    let scene = scene([cell(key(0))], openedAt: 0)
    #expect(abs(try height(drawnCell(drawing(scene, time: 0), key(0)))) < 1e-9)
    #expect(abs(try height(drawnCell(drawing(scene, time: 0.3), key(0))) - 134 * 0.875) < 1e-9)
    #expect(abs(try height(drawnCell(drawing(scene, time: 0.6), key(0))) - 134) < 1e-9)
  }

  @Test("starts growing the front row before the back row and the left column first")
  func growStagger() {
    #expect(PillarsRenderer.grow(time: 0.09, openedAt: 0, row: 2, column: 0) > 0)
    #expect(PillarsRenderer.grow(time: 0.09, openedAt: 0, row: 1, column: 0) == 0)
    #expect(PillarsRenderer.grow(time: 0.05, openedAt: 0, row: 2, column: 1) == 0)
  }

  @Test("sinks from full height to nothing over 0.7 seconds, easing out")
  func sinkCurve() throws {
    let scene = scene([cell(key(0))], sinking: [key(0): 0])
    #expect(abs(try height(drawnCell(drawing(scene, time: 0), key(0))) - 134) < 1e-9)
    #expect(abs(try height(drawnCell(drawing(scene, time: 0.35), key(0))) - 134 * 0.125) < 1e-9)
  }

  @Test("draws a sunk pillar as an empty tile once it falls below 0.02")
  func sinkCutOff() throws {
    let scene = scene([cell(key(0))], sinking: [key(0): 0])
    #expect(try !drawnCell(drawing(scene, time: 0.5), key(0)).faces.isEmpty)
    #expect(try drawnCell(drawing(scene, time: 0.69), key(0)).faces.isEmpty)
    #expect(try drawnCell(drawing(scene, time: 0.7), key(0)).faces.isEmpty)
  }

  @Test("fades in under Reduce Motion at full height")
  func fadeIn() throws {
    let scene = scene([cell(key(0))], openedAt: 0)
    let mid = try drawnCell(drawing(scene, time: 0.3, reduced: true), key(0))
    #expect(abs(mid.opacity - 0.875) < 1e-9)
    #expect(abs(try height(mid) - 134) < 1e-9)
    #expect(try drawnCell(drawing(scene, time: 0.6, reduced: true), key(0)).opacity == 1)
  }

  @Test("fades out under Reduce Motion at full height")
  func fadeOut() throws {
    let scene = scene([cell(key(0))], sinking: [key(0): 0])
    let mid = try drawnCell(drawing(scene, time: 0.35, reduced: true), key(0))
    #expect(abs(mid.opacity - 0.125) < 1e-9)
    #expect(abs(try height(mid) - 134) < 1e-9)
  }

  @Test("reports a transition while growth or a sink runs and not after")
  func transitions() {
    #expect(PillarsRenderer.hasTransition(scene(openedAt: 0), time: 0.5))
    #expect(!PillarsRenderer.hasTransition(scene(openedAt: 0), time: 2))
    #expect(PillarsRenderer.hasTransition(scene(sinking: [key(0): 0]), time: 0.5))
    #expect(!PillarsRenderer.hasTransition(scene(sinking: [key(0): 0]), time: 1))
    #expect(!PillarsRenderer.hasTransition(scene(), time: 0))
  }

  // MARK: Outlines

  @Test("outlines the selected pillar's top in white, width 3")
  func selectedOutline() throws {
    let cell = try drawnCell(drawing(scene([cell(key(2))], selected: key(2))), key(2))
    let top = try #require(cell.faces.last)
    #expect(top.stroke == OrbitColour(255, 255, 255))
    #expect(top.lineWidth == 3)
  }

  @Test("outlines an alert's top with a pulsing rim, width 2.5")
  func alertOutline() throws {
    let cells = [cell(key(2), kind: .alert)]
    let moving = try #require(
      drawnCell(drawing(scene(cells), time: 0.3), key(2)).faces.last)
    let pulse = 0.5 + 0.5 * sin(1.5)
    #expect(moving.lineWidth == 2.5)
    #expect(abs(moving.stroke.alpha - (0.45 + 0.5 * pulse)) < 1e-9)
    let still = try #require(
      drawnCell(drawing(scene(cells), time: 0.3, reduced: true), key(2)).faces.last)
    #expect(abs(still.stroke.alpha - 0.95) < 1e-9)
  }

  @Test("outlines any other top in its own fill, width 1")
  func plainOutline() throws {
    let top = try #require(drawnCell(drawing(scene([cell(key(2))])), key(2)).faces.last)
    #expect(top.stroke == top.fill)
    #expect(top.lineWidth == 1)
  }

  // MARK: Hit-testing

  private func centre(_ polygon: PillarsDrawing.Polygon) -> CGPoint {
    let count = Double(polygon.points.count)
    return CGPoint(
      x: polygon.points.map(\.x).reduce(0, +) / count,
      y: polygon.points.map(\.y).reduce(0, +) / count)
  }

  @Test("hits a pillar on its top face")
  func hitsPillar() throws {
    let drawing = drawing(scene([cell(key(1, .week))]))
    let top = try #require(try drawnCell(drawing, key(1, .week)).faces.last)
    #expect(PillarsRenderer.hit(centre(top), in: drawing) == key(1, .week))
  }

  @Test("hits an empty tile on its footprint")
  func hitsEmptyTile() throws {
    let drawing = drawing(scene([cell(key(1, .week))]))
    let tile = try drawnCell(drawing, key(3, .later)).tile
    #expect(PillarsRenderer.hit(centre(tile), in: drawing) == key(3, .later))
  }

  @Test("hits nothing outside the plate")
  func hitsNothing() {
    #expect(PillarsRenderer.hit(CGPoint(x: 2, y: 2), in: drawing(scene())) == nil)
  }

  @Test("answers with the front-most pillar where two overlap")
  func hitsFrontMost() throws {
    let cells = [cell(key(2, .later)), cell(key(2, .week))]
    let drawing = drawing(scene(cells))
    let back = try drawnCell(drawing, key(2, .later)).faces
    let front = try drawnCell(drawing, key(2, .week)).faces
    func inside(_ faces: [PillarsDrawing.Polygon], _ point: CGPoint) -> Bool {
      faces.contains { PillarsRenderer.contains($0.points, point) }
    }
    let overlaps = stride(from: 0.0, to: 540, by: 4).flatMap { x in
      stride(from: 0.0, to: 420, by: 4).map { CGPoint(x: x, y: $0) }
    }.filter { inside(back, $0) && inside(front, $0) }
    #expect(!overlaps.isEmpty)
    #expect(overlaps.allSatisfy { PillarsRenderer.hit($0, in: drawing) == key(2, .week) })
  }

  // MARK: Working particles

  @Test("rises five particles from a working cell and none from an idle one")
  func particles() {
    let idle = drawing(scene([cell(key(2))]), time: 1)
    let working = drawing(scene([cell(key(2), working: true)]), time: 1)
    #expect(idle.particles.isEmpty)
    #expect(working.particles.count == 5)
  }

  @Test("holds the particles at t of 0.4 under Reduce Motion")
  func particlesStill() {
    let scene = scene([cell(key(2), working: true)])
    #expect(
      drawing(scene, time: 1, reduced: true).particles
        == drawing(scene, time: 7, reduced: true).particles)
  }

  @Test("sizes and colours particles by index, fading with their phase")
  func particleStyle() {
    let particles = drawing(scene([cell(key(2), working: true)]), time: 0, reduced: true).particles
    #expect(particles.map(\.radius) == [3.2, 2.2, 3.2, 2.2, 3.2])
    #expect(particles[0].colour == OrbitPalette.workingCore.withAlpha(particles[0].colour.alpha))
    #expect(particles[1].colour == OrbitPalette.rim.withAlpha(particles[1].colour.alpha))
    let phase = (0.4 * 0.32).truncatingRemainder(dividingBy: 1)
    #expect(abs(particles[0].colour.alpha - 0.85 * sin(.pi * phase)) < 1e-9)
  }

  // MARK: Plate and labels

  @Test("labels the rows LATER, THIS WEEK and NOW, with NOW at the front")
  func rowLabels() {
    let labels = drawing(scene()).rowLabels
    #expect(labels.map(\.text) == ["LATER", "THIS WEEK", "NOW"])
    #expect(labels[0].anchor.y < labels[2].anchor.y)
  }

  @Test("draws no more than five columns")
  func columnLimit() {
    let wide = PillarsScene(
      unitIDs: units + ["f"], cells: [], selected: nil, openedAt: nil, sinking: [:])
    #expect(drawing(wide).cells.count == 15)
  }

  // MARK: Fit

  @Test("fits the box to a frame, keeping its aspect and centring it")
  func fit() {
    let fit = PillarsFit(size: CGSize(width: 1080, height: 600))
    #expect(abs(fit.scale - 600 / 420) < 1e-9)
    #expect(abs(fit.offset.x - (1080 - 540 * 600 / 420) / 2) < 1e-9)
    let point = CGPoint(x: 100, y: 100)
    #expect(abs(fit.toBox(fit.toView(point)).x - 100) < 1e-9)
  }
}
