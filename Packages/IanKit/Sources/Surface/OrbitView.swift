import SwiftUI

/// Draws an `OrbitDrawing` into its frame, scaled from the 100 unit box. Pure drawing: no clock,
/// no state. Snapshot tests render this view.
public struct OrbitDrawingView: View {
  private let drawing: OrbitDrawing

  public init(drawing: OrbitDrawing) {
    self.drawing = drawing
  }

  public var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / OrbitRenderer.boxSize
      Self.draw(drawing, in: &context, scale: scale)
    }
  }

  private static func draw(
    _ drawing: OrbitDrawing, in context: inout GraphicsContext, scale: Double
  ) {
    let centre = CGPoint(
      x: OrbitRenderer.centre.x * scale, y: OrbitRenderer.centre.y * scale)

    let trackRadius = OrbitRenderer.trackRadius * scale
    context.stroke(
      circle(centre, trackRadius), with: .color(OrbitPalette.track.color),
      lineWidth: OrbitRenderer.trackWidth * scale)

    for arc in [drawing.loadArc, drawing.overMedianArc].compactMap({ $0 }) {
      context.stroke(
        path(of: arc, centre: centre, scale: scale), with: .color(arc.colour.color),
        style: StrokeStyle(lineWidth: OrbitRenderer.trackWidth * scale, lineCap: .round))
    }

    context.fill(
      circle(
        CGPoint(x: centre.x, y: centre.y), drawing.core.radius * scale),
      with: .color(drawing.core.colour.color))

    for satellite in drawing.satellites {
      let shape = circle(
        CGPoint(x: satellite.centre.x * scale, y: satellite.centre.y * scale),
        satellite.radius * scale)
      context.fill(shape, with: .color(satellite.colour.color))
      if let rim = satellite.rim {
        context.stroke(shape, with: .color(rim.colour.color), lineWidth: rim.width * scale)
      }
    }

    if let chip = drawing.chip {
      let rect = CGRect(
        x: chip.rect.minX * scale, y: chip.rect.minY * scale, width: chip.rect.width * scale,
        height: chip.rect.height * scale)
      let pill = Path(roundedRect: rect, cornerRadius: rect.height / 2)
      context.fill(pill, with: .color(OrbitPalette.chipFill.color))
      context.stroke(
        pill, with: .color(OrbitPalette.chipStroke.color),
        lineWidth: OrbitRenderer.chipStroke * scale)
      context.draw(
        Text(chip.text).font(.system(size: 12 * OrbitRenderer.chipScale * scale))
          .foregroundColor(OrbitPalette.chipText.color),
        at: CGPoint(x: rect.midX, y: rect.midY))
    }
  }

  private static func circle(_ centre: CGPoint, _ radius: Double) -> Path {
    Path(
      ellipseIn: CGRect(
        x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
  }

  /// An arc from 12 o'clock, clockwise on screen. SwiftUI's `clockwise` flag is inverted by its
  /// flipped y axis, so `false` here turns clockwise.
  private static func path(of arc: OrbitDrawing.Arc, centre: CGPoint, scale: Double) -> Path {
    let radius = arc.radius * scale
    guard arc.fraction < 1 else { return circle(centre, radius) }
    var path = Path()
    path.addArc(
      center: centre, radius: radius, startAngle: .degrees(-90),
      endAngle: .degrees(-90 + 360 * arc.fraction), clockwise: false)
    return path
  }
}

extension OrbitColour {
  public var color: Color {
    Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
  }
}

/// The Orbit at rest: the drawing, driven by a clock that runs only while something moves.
///
/// The clock stops when the Orbit is off screen or suppressed (`isAnimating` false), when
/// Reduce Motion is on, and whenever nothing in the model moves. A stopped Orbit is drawn in its
/// still pose.
public struct OrbitView: View {
  /// The breath takes 4.2 seconds and the pulse about 1.3, so 20 frames a second looks smooth
  /// and keeps the idle Orbit inside the spec 6.9 budget.
  private static let frameInterval = 1.0 / 20

  private let model: OrbitModel
  private let reducedMotion: Bool
  private let isAnimating: Bool

  public init(model: OrbitModel, reducedMotion: Bool, isAnimating: Bool) {
    self.model = model
    self.reducedMotion = reducedMotion
    self.isAnimating = isAnimating
  }

  public var body: some View {
    let moves = isAnimating && !reducedMotion && OrbitRenderer.hasMotion(model)
    TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !moves)) { timeline in
      OrbitDrawingView(
        drawing: OrbitRenderer.drawing(
          for: model, time: timeline.date.timeIntervalSinceReferenceDate,
          reducedMotion: !moves))
    }
  }
}
