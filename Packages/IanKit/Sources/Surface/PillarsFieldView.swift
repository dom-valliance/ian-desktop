import SwiftUI

/// Maps the 540 by 420 box into a frame, keeping its aspect and centring it.
struct PillarsFit: Equatable {
  let scale: Double
  let offset: CGPoint

  init(size: CGSize) {
    let box = PillarsRenderer.boxSize
    scale = max(0, min(size.width / box.width, size.height / box.height))
    offset = CGPoint(
      x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
  }

  func toView(_ point: CGPoint) -> CGPoint {
    CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
  }

  func toBox(_ point: CGPoint) -> CGPoint {
    guard scale > 0 else { return .zero }
    return CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
  }
}

/// Draws a `PillarsDrawing` scaled to its frame. Pure drawing: no clock, no state. Snapshot
/// tests render this view.
public struct PillarsDrawingView: View {
  private let drawing: PillarsDrawing

  public init(drawing: PillarsDrawing) {
    self.drawing = drawing
  }

  public var body: some View {
    Canvas { context, size in
      Self.draw(drawing, in: &context, fit: PillarsFit(size: size))
    }
  }

  private static func draw(
    _ drawing: PillarsDrawing, in context: inout GraphicsContext, fit: PillarsFit
  ) {
    fill(drawing.plate, in: &context, fit: fit)
    for cell in drawing.cells {
      if cell.faces.isEmpty || cell.opacity < 1 {
        fill(cell.tile, in: &context, fit: fit)
      }
      guard !cell.faces.isEmpty else { continue }
      if cell.opacity < 1 {
        context.drawLayer { layer in
          layer.opacity = cell.opacity
          for face in cell.faces { fill(face, in: &layer, fit: fit) }
        }
      } else {
        for face in cell.faces { fill(face, in: &context, fit: fit) }
      }
    }
    for particle in drawing.particles {
      let centre = fit.toView(particle.centre)
      let radius = particle.radius * fit.scale
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
        with: .color(particle.colour.color))
    }
    for label in drawing.rowLabels {
      context.draw(
        Text(label.text).font(.system(size: 11 * fit.scale, design: .monospaced))
          .tracking(1.6 * fit.scale).foregroundColor(PillarsRenderer.labelColour.color),
        at: fit.toView(label.anchor), anchor: .trailing)
    }
  }

  private static func fill(
    _ polygon: PillarsDrawing.Polygon, in context: inout GraphicsContext, fit: PillarsFit
  ) {
    var path = Path()
    path.addLines(polygon.points.map(fit.toView))
    path.closeSubpath()
    context.fill(path, with: .color(polygon.fill.color))
    context.stroke(
      path, with: .color(polygon.stroke.color),
      style: StrokeStyle(lineWidth: polygon.lineWidth * fit.scale, lineJoin: .round))
  }
}

/// The Pillars field: the drawing, driven by a clock that runs only while something moves.
///
/// The clock stops when the field is hidden, occluded or suppressed (`isAnimating` false). The
/// yaw turns for as long as the field is visible, so under motion the clock runs at the display's
/// rate (spec 6.9). Under Reduce Motion it runs only through a growth or a sink, which are then
/// fades. A stopped field is drawn in its still pose.
///
/// The field is not the accessible path (non-negotiable 8): every pillar is also a row in the
/// lists below it, so VoiceOver meets one label and none of the internals.
public struct PillarsFieldView: View {
  private let scene: PillarsScene
  private let isAnimating: Bool
  private let reducedMotion: Bool
  private let onSelect: (PillarCellKey) -> Void

  /// Whether a Reduce Motion fade has finished, so its clock can stop.
  @State private var fadeDone = false

  public init(
    scene: PillarsScene, isAnimating: Bool, reducedMotion: Bool,
    onSelect: @escaping (PillarCellKey) -> Void
  ) {
    self.scene = scene
    self.isAnimating = isAnimating
    self.reducedMotion = reducedMotion
    self.onSelect = onSelect
  }

  private var runsClock: Bool {
    isAnimating && (!reducedMotion || !fadeDone)
  }

  public var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation(paused: !runsClock)) { timeline in
        let time = timeline.date.timeIntervalSinceReferenceDate
        PillarsDrawingView(drawing: drawing(at: time))
      }
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture().onEnded { tap in
          let point = PillarsFit(size: geometry.size).toBox(tap.location)
          let now = Date.now.timeIntervalSinceReferenceDate
          if let key = PillarsRenderer.hit(
            point, in: PillarsRenderer.drawing(for: scene, time: now, reducedMotion: still))
          {
            onSelect(key)
          }
        })
    }
    .task(id: scene.transitionEnd) {
      fadeDone = false
      let remaining = scene.transitionEnd - Date.now.timeIntervalSinceReferenceDate
      if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
      fadeDone = true
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Pillars field. Each pillar is also a row in the lists below.")
  }

  /// A stopped field holds its pose, and Reduce Motion never turns.
  private var still: Bool { reducedMotion || !isAnimating }

  private func drawing(at time: Double) -> PillarsDrawing {
    PillarsRenderer.drawing(for: scene, time: time, reducedMotion: still)
  }
}

extension PillarsScene {
  /// When the last growth or sink finishes.
  var transitionEnd: TimeInterval {
    let grow = openedAt.map { $0 + PillarsRenderer.longestGrow } ?? 0
    let sink = (sinking.values.max() ?? 0) + PillarsRenderer.sinkDuration
    return max(grow, sink)
  }
}
