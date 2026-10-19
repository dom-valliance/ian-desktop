import Foundation
import Testing

@testable import Surface

@Suite("Field turn")
struct FieldTurnTests {
  private func moved(_ pointer: inout FieldPointer, by dx: Double, _ dy: Double = 0) {
    pointer.changed(translation: CGSize(width: dx, height: dy))
  }

  // MARK: Drag mapping

  @Test("turns half a degree for each point dragged")
  func degreesPerPoint() {
    #expect(abs(FieldTurn.angle(from: 45, translation: -100) - 95) < 1e-9)
    #expect(abs(FieldTurn.angle(from: 45, translation: 20) - 35) < 1e-9)
  }

  @Test("turns the front edge to the right when dragged right")
  func directionFollowsThePointer() {
    let pose = PillarsRenderer.project(0, 64, 0, yaw: 45 * .pi / 180)
    let dragged = FieldTurn.angle(from: 45, translation: 40) * .pi / 180
    let after = PillarsRenderer.project(0, 64, 0, yaw: dragged)
    #expect(after.x > pose.x)
  }

  @Test("turns all the way round, staying within 0 to 360 degrees")
  func wraps() {
    #expect(abs(FieldTurn.angle(from: 45, translation: 720) - 45) < 1e-9)
    #expect(abs(FieldTurn.angle(from: 45, translation: 200) - 305) < 1e-9)
    #expect(abs(FieldTurn.angle(from: 350, translation: -40) - 10) < 1e-9)
    #expect(FieldTurn.normalised(-90) == 270)
  }

  @Test("follows the pointer from the angle it started at")
  func followsFromStart() {
    var pointer = FieldPointer(angle: 100)
    moved(&pointer, by: -20)
    #expect(abs(pointer.angle - 110) < 1e-9)
    moved(&pointer, by: -60)
    #expect(abs(pointer.angle - 130) < 1e-9)
    _ = pointer.ended(location: .zero, time: 1)
    moved(&pointer, by: 20)
    #expect(abs(pointer.angle - 120) < 1e-9)
  }

  @Test("holds the angle while the pointer is inside the click threshold")
  func holdsInsideThreshold() {
    var pointer = FieldPointer(angle: 45)
    moved(&pointer, by: 2, 2)
    #expect(pointer.angle == 45)
  }

  @Test("keeps turning once past the threshold, even if the pointer comes back")
  func staysADrag() {
    var pointer = FieldPointer(angle: 45)
    moved(&pointer, by: 30)
    moved(&pointer, by: 1)
    #expect(abs(pointer.angle - 44.5) < 1e-9)
    #expect(pointer.ended(location: .zero, time: 1) == .turned)
  }

  // MARK: Click, drag and double-click

  @Test("selects on a click below the drag threshold")
  func clickSelects() {
    var pointer = FieldPointer()
    moved(&pointer, by: 1, 1)
    #expect(
      pointer.ended(location: CGPoint(x: 10, y: 20), time: 1) == .select(CGPoint(x: 10, y: 20)))
    #expect(pointer.angle == 45)
  }

  @Test("does not select after a drag above the threshold")
  func dragDoesNotSelect() {
    var pointer = FieldPointer()
    moved(&pointer, by: 50)
    #expect(pointer.ended(location: CGPoint(x: 10, y: 20), time: 1) == .turned)
  }

  @Test("returns to 45 degrees on a double-click and selects nothing the second time")
  func doubleClickResets() {
    var pointer = FieldPointer(angle: 200)
    let spot = CGPoint(x: 50, y: 50)
    #expect(pointer.ended(location: spot, time: 1) == .select(spot))
    #expect(pointer.ended(location: spot, time: 1.2) == .reset)
    #expect(pointer.angle == 45)
  }

  @Test("treats two clicks far apart in time or place as two selections")
  func slowOrDistantClicksAreNotADoubleClick() {
    var pointer = FieldPointer(angle: 200)
    _ = pointer.ended(location: .zero, time: 1)
    #expect(pointer.ended(location: .zero, time: 1.9) == .select(.zero))
    #expect(
      pointer.ended(location: CGPoint(x: 60, y: 0), time: 2) == .select(CGPoint(x: 60, y: 0)))
    #expect(pointer.angle == 200)
  }

  @Test("selects on a click after a drag was abandoned, without snapping the angle")
  func clickAfterAbandonedDrag() {
    var pointer = FieldPointer(angle: 45)
    moved(&pointer, by: -100)
    let turned = pointer.angle
    // The drag is cancelled: no `ended` call. The next gesture starts with no translation.
    moved(&pointer, by: 0)
    #expect(pointer.angle == turned)
    #expect(pointer.ended(location: CGPoint(x: 5, y: 5), time: 1) == .select(CGPoint(x: 5, y: 5)))
    #expect(pointer.angle == turned)
  }

  @Test("turns from where the last gesture left the field after an abandoned drag")
  func dragAfterAbandonedDragStartsFromTheCurrentAngle() {
    var pointer = FieldPointer(angle: 45)
    moved(&pointer, by: -100)
    let turned = pointer.angle
    moved(&pointer, by: 0)
    moved(&pointer, by: -20)
    #expect(abs(pointer.angle - (turned + 10)) < 1e-9)
  }

  @Test("pairs two clicks within the interval the system gives")
  func usesTheGivenDoubleClickInterval() {
    var pointer = FieldPointer(angle: 200)
    _ = pointer.ended(location: .zero, time: 1, doubleClickInterval: 1.5)
    #expect(pointer.ended(location: .zero, time: 2.2, doubleClickInterval: 1.5) == .reset)
  }

  @Test("keeps the angle in 0 up to 360 and answers 45 for a value that is not a number")
  func normalisedRange() {
    #expect(FieldTurn.normalised(360) == 0)
    #expect(FieldTurn.normalised(720) == 0)
    #expect(FieldTurn.normalised(-1e-20) == 0)
    #expect(FieldTurn.normalised(.nan) == 45)
    #expect(FieldTurn.normalised(.infinity) == 45)
  }

  @Test("does not pair a click with the end of a drag")
  func dragBreaksADoubleClick() {
    var pointer = FieldPointer(angle: 200)
    _ = pointer.ended(location: .zero, time: 1)
    moved(&pointer, by: 40)
    _ = pointer.ended(location: .zero, time: 1.1)
    #expect(pointer.ended(location: .zero, time: 1.2) == .select(.zero))
  }
}

@Suite("Field angle in the renderer")
struct FieldAngleRendererTests {
  private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
  private let peak = (.pi / 2) / 0.22

  @Test("sways 10 degrees around the angle the principal chose")
  func swaysAroundTheAngle() {
    #expect(
      abs(PillarsRenderer.yaw(time: peak, reducedMotion: false, angle: 135) - radians(145)) < 1e-9)
    #expect(
      abs(PillarsRenderer.yaw(time: 0, reducedMotion: false, angle: 135) - radians(135)) < 1e-9)
    #expect(
      abs(PillarsRenderer.yaw(time: 3 * peak, reducedMotion: false, angle: 225) - radians(215))
        < 1e-9)
  }

  @Test("holds the chosen angle with no sway under Reduce Motion")
  func reduceMotionHoldsTheAngle() {
    for time in [0.0, 1, peak, 7.3] {
      #expect(PillarsRenderer.yaw(time: time, reducedMotion: true, angle: 225) == radians(225))
    }
  }

  @Test("still rests at 45 degrees when no angle is given")
  func defaultsTo45() {
    #expect(PillarsRenderer.yaw(time: 0, reducedMotion: true) == .pi / 4)
  }

  private let cells = [
    PillarCell(
      key: PillarCellKey(unitID: "a", horizon: .later), pressure: 0.7, kind: .proposal,
      working: false),
    PillarCell(
      key: PillarCellKey(unitID: "c", horizon: .week), pressure: 0.5, kind: .task, working: false),
    PillarCell(
      key: PillarCellKey(unitID: "e", horizon: .now), pressure: 0.9, kind: .alert, working: false),
  ]

  private var scene: PillarsScene {
    PillarsScene(
      unitIDs: ["a", "b", "c", "d", "e"], cells: cells, selected: nil, openedAt: nil, sinking: [:])
  }

  private func topCentre(
    _ key: PillarCellKey, in drawing: PillarsDrawing
  ) throws -> CGPoint {
    let top = try #require(drawing.cells.first { $0.key == key }?.faces.last)
    return CGPoint(
      x: top.points.map(\.x).reduce(0, +) / 4, y: top.points.map(\.y).reduce(0, +) / 4)
  }

  @Test("hits the pillar drawn under the point at 135 and 225 degrees", arguments: [135.0, 225.0])
  func hitTestFollowsTheAngle(angle: Double) throws {
    let turned = PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true, angle: angle)
    let resting = PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true, angle: 45)
    var movedCells = 0
    for cell in cells {
      let point = try topCentre(cell.key, in: turned)
      #expect(PillarsRenderer.hit(point, in: turned) == cell.key)
      if PillarsRenderer.hit(point, in: resting) != cell.key { movedCells += 1 }
    }
    // A hit test that ignored the angle would answer from the 45 degree pose, and fail here.
    #expect(movedCells > 0)
  }

  @Test("answers a point differently once the field has turned")
  func pointFollowsTheTurn() throws {
    let before = PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true, angle: 45)
    let after = PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true, angle: 135)
    let key = cells[0].key
    let spot = try topCentre(key, in: before)
    #expect(PillarsRenderer.hit(spot, in: before) == key)
    #expect(PillarsRenderer.hit(spot, in: after) != key)
  }

  private let labelReach = 2 * PillarsRenderer.pitch + PillarsRenderer.platePad + 6

  /// The label's x on screen for the plate's left (`-1`) or right (`1`) end.
  private func labelX(end: Double, row: Int, angle: Double) -> Double {
    PillarsRenderer.project(
      end * labelReach, Double(row - 1) * PillarsRenderer.pitch, 0, yaw: angle * .pi / 180
    ).x
  }

  @Test("puts each row label at the plate end that projects leftmost at every angle")
  func labelsSitAtTheLeftmostEnd() {
    for angle in stride(from: 0.0, to: 360, by: 15) where abs(cos(angle * .pi / 180)) > 0.05 {
      let drawing = PillarsRenderer.drawing(
        for: scene, time: 0, reducedMotion: true, angle: angle)
      for (row, label) in drawing.rowLabels.enumerated() {
        let left = min(
          labelX(end: -1, row: row, angle: angle), labelX(end: 1, row: row, angle: angle))
        #expect(abs(label.anchor.x - left) < 1e-9, "row \(row) at \(angle) degrees")
      }
    }
  }

  @Test("keeps the row labels at one end while the sway crosses 90 degrees")
  func swayDoesNotFlipLabels() {
    // Chosen angle 85 degrees: the sway takes the yaw from 75 to 95, across 90.
    for time in [0.0, (.pi / 2) / 0.22, 3 * (.pi / 2) / 0.22] {
      let drawing = PillarsRenderer.drawing(
        for: scene, time: time, reducedMotion: false, angle: 85)
      let yaw = PillarsRenderer.yaw(time: time, reducedMotion: false, angle: 85)
      for (row, label) in drawing.rowLabels.enumerated() {
        let point = PillarsRenderer.project(
          -labelReach, Double(row - 1) * PillarsRenderer.pitch, 0, yaw: yaw)
        #expect(abs(label.anchor.x - point.x) < 1e-9)
      }
    }
  }

  @Test("draws the plate and cells at the turned angle")
  func drawsAtTheAngle() {
    let at45 = PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true, angle: 45)
    let at135 = PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true, angle: 135)
    #expect(at45.plate != at135.plate)
    #expect(at45 == PillarsRenderer.drawing(for: scene, time: 0, reducedMotion: true))
  }
}
