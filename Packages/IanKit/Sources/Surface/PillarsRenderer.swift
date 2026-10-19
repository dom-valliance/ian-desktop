import Foundation

/// The field as polygons in a 540 by 420 box, in draw order.
public struct PillarsDrawing: Equatable, Sendable {
  public struct Polygon: Equatable, Sendable {
    public let points: [CGPoint]
    public let fill: OrbitColour
    public let stroke: OrbitColour
    public let lineWidth: Double
  }

  public struct Cell: Equatable, Sendable {
    public let key: PillarCellKey
    /// The cell's flat footprint, drawn alone for an empty tile and under a fading pillar.
    public let tile: Polygon
    /// The visible side faces then the top face; empty for an empty tile.
    public let faces: [Polygon]
    /// The pillar's opacity. Below 1 only under Reduce Motion, which fades instead of moving.
    public let opacity: Double
  }

  public struct Particle: Equatable, Sendable {
    public let centre: CGPoint
    public let radius: Double
    public let colour: OrbitColour
  }

  public struct RowLabel: Equatable, Sendable {
    public let text: String
    /// The right edge of the text, already moved 4 units down.
    public let anchor: CGPoint
  }

  public let plate: Polygon
  public let rowLabels: [RowLabel]
  /// Back to front.
  public let cells: [Cell]
  public let particles: [Particle]
}

/// A pure function from the scene, the time and the motion setting to a drawing, following the
/// design README's Pillars section (ADR 0004). Reduce Motion is a parameter: it drops the sway,
/// stops the ripple, the pulse and the particles, and turns growth and sinking into a fade.
public enum PillarsRenderer {
  public static let boxSize = CGSize(width: 540, height: 420)
  static let pitch = 64.0
  static let halfWidth = 25.0
  static let tilt = 0.52
  static let origin = CGPoint(x: 300, y: 250)
  static let maxHeight = 120.0
  static let baseHeight = 14.0
  static let platePad = pitch * 0.62
  static let turn = 10.0
  static let growDuration = 0.6
  static let sinkDuration = 0.7
  static let goneBelow = 0.02
  static let stillParticleTime = 0.4
  /// The last cell to start growing (back row, fifth column) plus its own duration.
  static let longestGrow = growDuration + 2 * 0.09 + Double(columns - 1) * 0.05
  static let columns = 5

  static let corners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
  static let normals: [(Double, Double)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]

  static let tileFill = OrbitColour(255, 255, 255, alpha: 0.05)
  static let tileStroke = OrbitColour(255, 255, 255, alpha: 0.14)
  static let plateFill = OrbitColour(255, 255, 255, alpha: 0.025)
  static let plateStroke = OrbitColour(255, 255, 255, alpha: 0.08)
  static let selectedOutline = OrbitColour(255, 255, 255)
  static let labelColour = OrbitColour(0xF2, 0xEE, 0xEE, alpha: 0.6)
  static let rowTitles = ["LATER", "THIS WEEK", "NOW"]

  static func easeOutCubic(_ x: Double) -> Double {
    1 - pow(1 - x, 3)
  }

  static func clamp(_ x: Double) -> Double {
    max(0, min(1, x))
  }

  /// The sway carries on around `angle`, the degrees the principal has turned the field to.
  /// Reduce Motion drops the sway and keeps the angle.
  public static func yaw(
    time: Double, reducedMotion: Bool, angle: Double = FieldTurn.defaultAngle
  ) -> Double {
    let degrees = angle + (reducedMotion ? 0 : turn * sin(0.22 * time))
    return degrees * .pi / 180
  }

  static func project(_ x: Double, _ z: Double, _ height: Double, yaw: Double) -> CGPoint {
    CGPoint(
      x: origin.x + x * cos(yaw) - z * sin(yaw),
      y: origin.y + (x * sin(yaw) + z * cos(yaw)) * tilt - height)
  }

  /// `max(0, 14 + pressure * 120 + ripple)`, before growth and sinking.
  static func baseHeight(pressure: Double, ripple: Double) -> Double {
    max(0, baseHeight + pressure * maxHeight + ripple)
  }

  static func ripple(distance: Double, time: Double) -> Double {
    4 * sin(0.8 * distance - 2.6 * time)
  }

  static func grow(time: Double, openedAt: Double, row: Int, column: Int) -> Double {
    let delay = Double(2 - row) * 0.09 + Double(column) * 0.05
    return easeOutCubic(clamp((time - openedAt - delay) / growDuration))
  }

  static func sink(time: Double, startedAt: Double) -> Double {
    1 - easeOutCubic(clamp((time - startedAt) / sinkDuration))
  }

  /// The mix of a kind colour towards the ground: each channel is `23 + (k - 23) m`, rounded.
  static func shaded(_ colour: OrbitColour, _ m: Double) -> OrbitColour {
    let ground = OrbitPalette.ground.red
    func mix(_ k: Double) -> Double { (ground + (k - ground) * m).rounded() }
    return OrbitColour(mix(colour.red), mix(colour.green), mix(colour.blue))
  }

  static func colour(for kind: PillarKind) -> OrbitColour { KindPalette.colour(for: kind) }

  /// Whether growth or a sink is still running at `time`, so a still field can keep its clock.
  public static func hasTransition(_ scene: PillarsScene, time: Double) -> Bool {
    if let openedAt = scene.openedAt, time < openedAt + longestGrow { return true }
    return scene.sinking.values.contains { time < $0 + sinkDuration }
  }

  public static func drawing(
    for scene: PillarsScene, time: Double, reducedMotion: Bool,
    angle: Double = FieldTurn.defaultAngle
  ) -> PillarsDrawing {
    let yaw = yaw(time: time, reducedMotion: reducedMotion, angle: angle)
    let sinYaw = sin(yaw)
    let cosYaw = cos(yaw)
    let pulse = reducedMotion ? 1 : 0.5 + 0.5 * sin(5 * time)
    let particleTime = reducedMotion ? stillParticleTime : time
    let cellsByKey = Dictionary(scene.cells.map { ($0.key, $0) }) { first, _ in first }
    let selectedColumn = scene.selected.flatMap { scene.unitIDs.firstIndex(of: $0.unitID) }

    struct Slot {
      let key: PillarCellKey
      let column: Int
      let x: Double
      let z: Double
    }
    var slots: [Slot] = []
    for (column, unitID) in scene.unitIDs.prefix(columns).enumerated() {
      for horizon in PillarHorizon.allCases {
        slots.append(
          Slot(
            key: PillarCellKey(unitID: unitID, horizon: horizon), column: column,
            x: Double(column - 2) * pitch, z: Double(horizon.rawValue - 1) * pitch))
      }
    }
    slots.sort { $0.x * sinYaw + $0.z * cosYaw < $1.x * sinYaw + $1.z * cosYaw }

    var cells: [PillarsDrawing.Cell] = []
    var particles: [PillarsDrawing.Particle] = []
    for slot in slots {
      let base = corners.map { (slot.x + $0.0 * halfWidth, slot.z + $0.1 * halfWidth) }
      let footprint = base.map { project($0.0, $0.1, 0, yaw: yaw) }
      let tile = PillarsDrawing.Polygon(
        points: footprint, fill: tileFill, stroke: tileStroke, lineWidth: 1)

      var grow = 1.0
      if let openedAt = scene.openedAt {
        grow = Self.grow(
          time: time, openedAt: openedAt, row: slot.key.horizon.rawValue, column: slot.column)
      }
      var sink = 1.0
      if let startedAt = scene.sinking[slot.key] {
        sink = Self.sink(time: time, startedAt: startedAt)
      }
      guard let cell = cellsByKey[slot.key], sink >= goneBelow else {
        cells.append(.init(key: slot.key, tile: tile, faces: [], opacity: 1))
        continue
      }

      var ripple = 0.0
      if !reducedMotion, let selected = scene.selected, let selectedColumn {
        let distance = hypot(
          Double(slot.column - selectedColumn),
          Double(slot.key.horizon.rawValue - selected.horizon.rawValue))
        ripple = Self.ripple(distance: distance, time: time)
      }
      let scale = reducedMotion ? 1 : grow * sink
      let opacity = reducedMotion ? grow * sink : 1
      let height = baseHeight(pressure: cell.pressure, ripple: ripple) * scale

      let kindColour = colour(for: cell.kind)
      let top = base.map { project($0.0, $0.1, height, yaw: yaw) }
      var faces: [PillarsDrawing.Polygon] = []
      for edge in 0..<4 {
        let normal = normals[edge]
        guard normal.0 * sinYaw + normal.1 * cosYaw > 0 else { continue }
        let nx = normal.0 * cosYaw - normal.1 * sinYaw
        let next = (edge + 1) % 4
        let fill = shaded(kindColour, 0.6 + 0.2 * (nx + 1) / 2)
        faces.append(
          .init(
            points: [top[edge], top[next], footprint[next], footprint[edge]], fill: fill,
            stroke: fill, lineWidth: 1))
      }
      let topFill = shaded(kindColour, 0.96)
      let outline: (OrbitColour, Double) =
        if scene.selected == slot.key {
          (selectedOutline, 3)
        } else if cell.kind == .alert {
          (OrbitPalette.rim.withAlpha(0.45 + 0.5 * pulse), 2.5)
        } else {
          (topFill, 1)
        }
      faces.append(.init(points: top, fill: topFill, stroke: outline.0, lineWidth: outline.1))
      cells.append(.init(key: slot.key, tile: tile, faces: faces, opacity: opacity))

      if cell.working {
        let centre = CGPoint(x: (top[0].x + top[2].x) / 2, y: (top[0].y + top[2].y) / 2)
        for k in 0..<5 {
          let phase = (particleTime * 0.32 + Double(k) * 0.2).truncatingRemainder(dividingBy: 1)
          let odd = k % 2 == 1
          particles.append(
            .init(
              centre: CGPoint(
                x: centre.x + 6 * sin(6 * phase + 1.7 * Double(k)), y: centre.y - 8 - 80 * phase),
              radius: odd ? 2.2 : 3.2,
              colour: (odd ? OrbitPalette.rim : OrbitPalette.workingCore)
                .withAlpha(0.85 * sin(.pi * phase) * opacity)))
        }
      }
    }

    let reach = 2 * pitch + platePad
    let depth = pitch + platePad
    let plate = PillarsDrawing.Polygon(
      points: [(-reach, -depth), (reach, -depth), (reach, depth), (-reach, depth)].map {
        project($0.0, $0.1, 0, yaw: yaw)
      },
      fill: plateFill, stroke: plateStroke, lineWidth: 1)
    let labels = rowTitles.enumerated().map { row, title in
      let point = project(-reach - 6, Double(row - 1) * pitch, 0, yaw: yaw)
      return PillarsDrawing.RowLabel(text: title, anchor: CGPoint(x: point.x, y: point.y + 4))
    }
    return PillarsDrawing(plate: plate, rowLabels: labels, cells: cells, particles: particles)
  }

  /// The cell under `point`, in box units, front-most first. A pillar answers for its faces and
  /// an empty tile for its footprint; a point outside every cell answers nil.
  public static func hit(
    _ point: CGPoint, in drawing: PillarsDrawing
  ) -> PillarCellKey? {
    for cell in drawing.cells.reversed() {
      let polygons = cell.faces.isEmpty ? [cell.tile] : cell.faces
      if polygons.contains(where: { contains($0.points, point) }) { return cell.key }
    }
    return nil
  }

  static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
    var inside = false
    var previous = polygon[polygon.count - 1]
    for current in polygon {
      if (current.y > point.y) != (previous.y > point.y),
        point.x
          < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
      {
        inside.toggle()
      }
      previous = current
    }
    return inside
  }
}
