import AppKit
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
    } symbols: {
      ForEach(Array(PillarsRenderer.rowTitles.enumerated()), id: \.offset) { row, title in
        Text(title).font(.system(size: 11, design: .monospaced)).tracking(1.6)
          .foregroundColor(PillarsRenderer.labelColour.color).tag(row)
      }
    }
  }

  private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

  private static func draw(
    _ drawing: PillarsDrawing, in context: inout GraphicsContext, fit: PillarsFit
  ) {
    fill(drawing.plate, in: &context, fit: fit)
    for (row, label) in drawing.rowLabels.enumerated() {
      guard let symbol = context.resolveSymbol(id: row) else { continue }
      var layer = context
      let anchor = fit.toView(label.anchor)
      layer.translateBy(x: anchor.x, y: anchor.y)
      layer.scaleBy(x: fit.scale, y: fit.scale)
      // The canvas sets each label's baseline at the anchor; `bottomTrailing` puts the text's
      // bottom there, so the descent is added to bring the baseline back.
      layer.draw(
        symbol, at: CGPoint(x: 0, y: -Self.labelFont.descender), anchor: .bottomTrailing)
    }
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
/// yaw turns for as long as the field is visible, so under motion the clock runs at 60 frames a
/// second (spec 6.9). Under Reduce Motion it runs only through a growth or a sink, which are then
/// fades. A stopped field is drawn in its still pose.
///
/// Dragging sideways turns the field about its vertical axis, a click selects a pillar and a
/// double-click returns the field to 45 degrees (`FieldPointer`). The turn is this view's own
/// state, so a drag redraws the field alone.
///
/// The field is not the accessible path (non-negotiable 8): every pillar is also a row in the
/// lists below it, so VoiceOver meets one label and none of the internals.
public struct PillarsFieldView: View {
  /// Spec 6.9 asks for 60 frames a second. A ProMotion display would otherwise draw at 120.
  private static let frameInterval = 1.0 / 60

  private let scene: PillarsScene
  private let isAnimating: Bool
  private let reducedMotion: Bool
  private let onSelect: (PillarCellKey) -> Void
  private let onTurn: (Double) -> Void

  /// The angle and the click state, which a drag changes many times a second.
  @State private var pointer: FieldPointer

  /// Whether a Reduce Motion fade has finished, so its clock can stop.
  @State private var fadeDone = false

  public init(
    scene: PillarsScene, isAnimating: Bool, reducedMotion: Bool,
    angle: Double = FieldTurn.defaultAngle, onTurn: @escaping (Double) -> Void = { _ in },
    onSelect: @escaping (PillarCellKey) -> Void
  ) {
    self.scene = scene
    self.isAnimating = isAnimating
    self.reducedMotion = reducedMotion
    self.onSelect = onSelect
    self.onTurn = onTurn
    _pointer = State(initialValue: FieldPointer(angle: angle))
  }

  private var runsClock: Bool {
    isAnimating && (!reducedMotion || !fadeDone)
  }

  public var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !runsClock)) {
        timeline in
        let clock = timeline.date.timeIntervalSinceReferenceDate
        PillarsDrawingView(
          drawing: drawing(at: Self.drawTime(scene: scene, isAnimating: isAnimating, clock: clock)))
      }
      .contentShape(Rectangle())
      .accessibilityHidden(true)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in pointer.changed(translation: drag.translation) }
          .onEnded { drag in
            let fit = PillarsFit(size: geometry.size)
            switch pointer.ended(
              location: drag.location, time: Date.now.timeIntervalSinceReferenceDate)
            {
            case .turned, .reset:
              onTurn(pointer.angle)
            case .select(let location):
              let time = Self.drawTime(
                scene: scene, isAnimating: isAnimating,
                clock: Date.now.timeIntervalSinceReferenceDate)
              if let key = PillarsRenderer.hit(fit.toBox(location), in: drawing(at: time)) {
                onSelect(key)
              }
            }
          })
    }
    .task(id: scene.transitionEnd) {
      fadeDone = false
      let remaining = scene.transitionEnd - Date.now.timeIntervalSinceReferenceDate
      if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
      fadeDone = true
    }
    // The field only describes itself. A tap gesture on it would make VoiceOver's activation
    // select or clear a pillar, so the labelled element is a separate one with no action.
    .overlay {
      Color.clear
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pillars field. Each pillar is also a row in the lists below.")
    }
  }

  /// The time to draw at. A field whose clock is stopped, hidden or suppressed, draws its
  /// finished pose: a clock frozen before `openedAt` would otherwise draw every pillar unrisen.
  static func drawTime(scene: PillarsScene, isAnimating: Bool, clock: Double) -> Double {
    isAnimating ? clock : max(clock, scene.transitionEnd)
  }

  /// A stopped field holds its pose, and Reduce Motion never turns.
  private var still: Bool { reducedMotion || !isAnimating }

  private func drawing(at time: Double) -> PillarsDrawing {
    PillarsRenderer.drawing(
      for: scene, time: time, reducedMotion: still, angle: pointer.angle)
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
