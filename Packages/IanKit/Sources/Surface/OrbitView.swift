import SwiftUI

/// Draws an `OrbitDrawing` into its frame, scaled from the 100 unit box. Pure drawing: no clock,
/// no state. Snapshot tests render this view.
public struct OrbitDrawingView: View {
  private let drawing: OrbitDrawing
  private let layered: OrbitMotion

  public init(drawing: OrbitDrawing) {
    self.init(drawing: drawing, layered: .still)
  }

  /// `layered` names the parts that Core Animation layers draw over this view, which it leaves
  /// out so they are not drawn twice.
  init(drawing: OrbitDrawing, layered: OrbitMotion) {
    self.drawing = drawing
    self.layered = layered
  }

  public var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / OrbitRenderer.boxSize
      Self.draw(drawing, layered: layered, in: &context, scale: scale)
    }
  }

  private static func draw(
    _ drawing: OrbitDrawing, layered: OrbitMotion, in context: inout GraphicsContext,
    scale: Double
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

    if layered.core == nil {
      context.fill(
        circle(
          CGPoint(x: centre.x, y: centre.y), drawing.core.radius * scale),
        with: .color(drawing.core.colour.color))
    }

    for satellite in drawing.satellites {
      let shape = circle(
        CGPoint(x: satellite.centre.x * scale, y: satellite.centre.y * scale),
        satellite.radius * scale)
      context.fill(shape, with: .color(satellite.colour.color))
      if let rim = satellite.rim, !layered.rims.contains(where: { $0.slot == satellite.slot }) {
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

/// The Orbit at rest: the still pose, with the core's breath and each alert's pulse as Core
/// Animation layers over it (ADR 0017).
///
/// The still pose is drawn when the model, the size or the motion changes, and not on a clock.
/// The layers run, and the still pose leaves out the parts they draw, only while the Orbit is on
/// screen and unsuppressed, Reduce Motion is off and something in the model moves. Otherwise there
/// are no layers and the still pose shows the resting state.
public struct OrbitView: View {
  private let model: OrbitModel
  private let reducedMotion: Bool
  private let isAnimating: Bool

  public init(model: OrbitModel, reducedMotion: Bool, isAnimating: Bool) {
    self.model = model
    self.reducedMotion = reducedMotion
    self.isAnimating = isAnimating
  }

  /// The motion to show: the model's moving parts, or none unless the Orbit is on screen and
  /// unsuppressed (`isAnimating`), Reduce Motion is off and something in the model moves.
  static func motion(model: OrbitModel, reducedMotion: Bool, isAnimating: Bool) -> OrbitMotion {
    guard isAnimating, !reducedMotion, OrbitRenderer.hasMotion(model) else { return .still }
    return OrbitRenderer.motion(for: model)
  }

  public var body: some View {
    let motion = Self.motion(model: model, reducedMotion: reducedMotion, isAnimating: isAnimating)
    ZStack {
      OrbitDrawingView(
        drawing: OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true),
        layered: motion)
      OrbitMotionLayers(motion: motion)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
}
