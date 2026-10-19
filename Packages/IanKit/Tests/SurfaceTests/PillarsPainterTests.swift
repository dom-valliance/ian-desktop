import AppKit
import Testing

@testable import Surface

@Suite("Pillars painter")
@MainActor
struct PillarsPainterTests {
  private let key = PillarCellKey(unitID: "u", horizon: .now)

  private func scene(selected: Bool = false, working: Bool = true) -> PillarsScene {
    PillarsScene(
      unitIDs: ["u"],
      cells: [PillarCell(key: key, pressure: 0.8, kind: .proposal, working: working)],
      selected: selected ? key : nil, openedAt: nil, sinking: [:])
  }

  private func drawing(_ scene: PillarsScene) -> PillarsDrawing {
    PillarsRenderer.drawing(for: scene, time: 3, reducedMotion: true)
  }

  private func pixels(_ drawing: PillarsDrawing) -> NSBitmapImageRep {
    NSBitmapImageRep(cgImage: PillarsBitmap.cgImage(of: drawing, scale: 1))
  }

  private func centre(of polygon: PillarsDrawing.Polygon) -> CGPoint {
    let count = Double(polygon.points.count)
    return CGPoint(
      x: polygon.points.map(\.x).reduce(0, +) / count,
      y: polygon.points.map(\.y).reduce(0, +) / count)
  }

  /// The stored channel values, which are sRGB and opaque here, so no colour conversion enters.
  private func colour(at point: CGPoint, in image: NSBitmapImageRep) -> [Double] {
    let data = image.bitmapData!
    let offset = Int(point.y) * image.bytesPerRow + Int(point.x) * image.samplesPerPixel
    return (0..<3).map { Double(data[offset + $0]) }
  }

  private func expect(_ actual: [Double], matches expected: OrbitColour) {
    for (a, e) in zip(actual, [expected.red, expected.green, expected.blue]) {
      #expect(abs(a - e) <= 2)
    }
  }

  @Test("paints each face of a pillar in the colour the renderer gives it")
  func facesKeepTheirColours() throws {
    let drawing = drawing(scene(working: false))
    let image = pixels(drawing)
    let faces = try #require(drawing.cells.first { $0.key == key }?.faces)
    #expect(faces.count == 3)
    for face in faces { expect(colour(at: centre(of: face), in: image), matches: face.fill) }
  }

  @Test("paints an empty cell as the tile over the plate over the ground")
  func emptyTileIsPainted() throws {
    let bare = PillarsScene(
      unitIDs: ["u"], cells: [], selected: nil, openedAt: nil, sinking: [:])
    let drawing = drawing(bare)
    let tile = try #require(drawing.cells.first { $0.key == key }?.tile)
    func over(_ base: Double, _ ink: OrbitColour) -> Double {
      base + (255 - base) * ink.alpha
    }
    let expected = over(
      over(OrbitPalette.ground.red, PillarsRenderer.plateFill), PillarsRenderer.tileFill)
    for channel in colour(at: centre(of: tile), in: pixels(drawing)) {
      #expect(abs(channel - expected) <= 2)
    }
  }

  @Test("outlines the selected pillar's top face in white")
  func selectionOutline() throws {
    let drawing = drawing(scene(selected: true, working: false))
    let top = try #require(drawing.cells.first { $0.key == key }?.faces.last)
    let edge = CGPoint(
      x: (top.points[0].x + top.points[1].x) / 2, y: (top.points[0].y + top.points[1].y) / 2)
    expect(colour(at: edge, in: pixels(drawing)), matches: PillarsRenderer.selectedOutline)
  }

  @Test("paints the working particles above the pillar")
  func particlesArePainted() throws {
    let drawing = drawing(scene())
    let image = pixels(drawing)
    #expect(drawing.particles.count == 5)
    let ground = OrbitPalette.ground
    let lit = drawing.particles.filter { $0.colour.alpha > 0.5 }
    #expect(!lit.isEmpty)
    for particle in lit {
      let painted = colour(at: particle.centre, in: image)
      #expect(painted[0] > ground.red + 20 || painted[2] > ground.blue + 20)
    }
  }

  @Test("draws the row titles ending at their anchors")
  func labelsEndAtTheirAnchors() throws {
    let drawing = drawing(
      PillarsScene(unitIDs: [], cells: [], selected: nil, openedAt: nil, sinking: [:]))
    let image = pixels(drawing)
    let ground = OrbitPalette.ground
    func isInk(_ point: CGPoint) -> Bool {
      colour(at: point, in: image)[0] > ground.red + 40
    }
    for label in drawing.rowLabels {
      let band = (Int(label.anchor.y) - 9)...Int(label.anchor.y)
      let left = Int(label.anchor.x) - 60...Int(label.anchor.x)
      let right = (Int(label.anchor.x) + 4)...(Int(label.anchor.x) + 40)
      let inked = left.contains { x in band.contains { isInk(CGPoint(x: x, y: $0)) } }
      let beyond = right.contains { x in band.contains { isInk(CGPoint(x: x, y: $0)) } }
      #expect(inked)
      #expect(!beyond)
    }
  }

  @Test("paints a fading pillar translucently over its tile")
  func fadingPillarIsTranslucent() throws {
    let fading = PillarsScene(
      unitIDs: ["u"],
      cells: [PillarCell(key: key, pressure: 0.8, kind: .proposal, working: false)],
      selected: nil, openedAt: 100, sinking: [:])
    let drawing = PillarsRenderer.drawing(for: fading, time: 100.3, reducedMotion: true)
    let cell = try #require(drawing.cells.first { $0.key == key })
    #expect(cell.opacity < 1 && cell.opacity > 0)
    let top = try #require(cell.faces.last)
    let painted = colour(at: centre(of: top), in: pixels(drawing))
    let ground = OrbitPalette.ground.red
    #expect(painted[0] > ground)
    #expect(painted[0] < top.fill.red - 5)
  }
}

@Suite("Pillars frame change")
struct PillarsFrameChangeTests {
  private let key = PillarCellKey(unitID: "u", horizon: .now)
  private var scene: PillarsScene {
    PillarsScene(
      unitIDs: ["u"],
      cells: [PillarCell(key: key, pressure: 0.8, kind: .alert, working: true)],
      selected: key, openedAt: nil, sinking: [:])
  }

  private func drawing(at time: Double) -> PillarsDrawing {
    PillarsRenderer.drawing(for: scene, time: time, reducedMotion: false)
  }

  @Test("treats the same time as the same picture")
  func sameTime() {
    #expect(
      !drawing(at: 3).isVisiblyDifferent(
        from: drawing(at: 3), pointTolerance: 0.1, colourTolerance: 2))
  }

  @Test("treats a frame of sway alone as unchanged under a sixth of a point")
  func swayFrame() {
    let sway = PillarsRenderer.drawing(
      for: PillarsScene(
        unitIDs: ["u"],
        cells: [PillarCell(key: key, pressure: 0.8, kind: .proposal, working: false)],
        selected: nil, openedAt: nil, sinking: [:]),
      time: 3, reducedMotion: false)
    let next = PillarsRenderer.drawing(
      for: PillarsScene(
        unitIDs: ["u"],
        cells: [PillarCell(key: key, pressure: 0.8, kind: .proposal, working: false)],
        selected: nil, openedAt: nil, sinking: [:]),
      time: 3 + 1.0 / 60, reducedMotion: false)
    #expect(!next.isVisiblyDifferent(from: sway, pointTolerance: 0.35, colourTolerance: 2))
  }

  @Test("sees a pulse, a particle or a long gap as a change")
  func visibleChanges() {
    #expect(
      drawing(at: 3.5).isVisiblyDifferent(
        from: drawing(at: 3), pointTolerance: 0.35, colourTolerance: 2))
    #expect(
      drawing(at: 30).isVisiblyDifferent(
        from: drawing(at: 3), pointTolerance: 0.35, colourTolerance: 2))
  }

  @Test("sees a different number of cells as a change")
  func structureChange() {
    let empty = PillarsScene(
      unitIDs: [], cells: [], selected: nil, openedAt: nil, sinking: [:])
    #expect(
      PillarsRenderer.drawing(for: empty, time: 3, reducedMotion: true).isVisiblyDifferent(
        from: drawing(at: 3), pointTolerance: 0.35, colourTolerance: 2))
  }
}
