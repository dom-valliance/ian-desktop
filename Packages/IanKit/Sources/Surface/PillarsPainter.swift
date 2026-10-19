import AppKit

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

  /// The box as it lies in the frame.
  var rect: CGRect {
    CGRect(
      x: offset.x, y: offset.y, width: PillarsRenderer.boxSize.width * scale,
      height: PillarsRenderer.boxSize.height * scale)
  }

  func toView(_ point: CGPoint) -> CGPoint {
    CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
  }

  func toBox(_ point: CGPoint) -> CGPoint {
    guard scale > 0 else { return .zero }
    return CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
  }
}

/// The three row titles, laid out once. Drawing a frame only positions and draws these lines;
/// no text is shaped per frame.
struct PillarsLabels {
  struct Line {
    let line: CTLine
    /// The advance of the line, including the tracking after its last letter.
    let width: Double
  }

  static let fontSize = 11.0
  static let tracking = 1.6

  let lines: [Line]

  init() {
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): NSFont.monospacedSystemFont(
        ofSize: Self.fontSize, weight: .regular),
      NSAttributedString.Key(kCTKernAttributeName as String): Self.tracking,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String):
        PillarsRenderer.labelColour.cgColor,
    ]
    lines = PillarsRenderer.rowTitles.map { title in
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: title, attributes: attributes))
      return Line(line: line, width: CTLineGetTypographicBounds(line, nil, nil, nil))
    }
  }
}

/// Paints a `PillarsDrawing` with Core Graphics. The live field and the snapshot tests both call
/// this, so what the tests compare is what is on screen (ADR 0018).
///
/// The context must have its origin at the top left with y growing downwards, as a flipped
/// view's context does, because the drawing's coordinates run that way.
enum PillarsPainter {
  static func paint(
    _ drawing: PillarsDrawing, in context: CGContext, fit: PillarsFit, labels: PillarsLabels
  ) {
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: fit.rect)
    context.setLineJoin(.round)
    context.setShouldSmoothFonts(false)

    fill(drawing.plate, in: context, fit: fit)
    for (row, label) in drawing.rowLabels.enumerated() where row < labels.lines.count {
      draw(labels.lines[row], at: fit.toView(label.anchor), scale: fit.scale, in: context)
    }
    for cell in drawing.cells {
      if cell.faces.isEmpty || cell.opacity < 1 {
        fill(cell.tile, in: context, fit: fit)
      }
      guard !cell.faces.isEmpty else { continue }
      if cell.opacity < 1 {
        context.saveGState()
        context.setAlpha(cell.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for face in cell.faces { fill(face, in: context, fit: fit) }
        context.endTransparencyLayer()
        context.restoreGState()
      } else {
        for face in cell.faces { fill(face, in: context, fit: fit) }
      }
    }
    for particle in drawing.particles {
      let centre = fit.toView(particle.centre)
      let radius = particle.radius * fit.scale
      context.setFillColor(particle.colour.cgColor)
      context.fillEllipse(
        in: CGRect(
          x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
  }

  /// The line's baseline sits at `anchor` and its right edge ends there.
  private static func draw(
    _ label: PillarsLabels.Line, at anchor: CGPoint, scale: Double, in context: CGContext
  ) {
    context.saveGState()
    context.translateBy(x: anchor.x, y: anchor.y)
    context.scaleBy(x: scale, y: scale)
    // Glyphs are upright in a y-up space, so the flipped context needs the text matrix flipped.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: -label.width, y: 0)
    CTLineDraw(label.line, context)
    context.restoreGState()
  }

  private static func fill(
    _ polygon: PillarsDrawing.Polygon, in context: CGContext, fit: PillarsFit
  ) {
    guard let first = polygon.points.first else { return }
    context.beginPath()
    context.move(to: fit.toView(first))
    for point in polygon.points.dropFirst() { context.addLine(to: fit.toView(point)) }
    context.closePath()
    context.setFillColor(polygon.fill.cgColor)
    context.setStrokeColor(polygon.stroke.cgColor)
    context.setLineWidth(polygon.lineWidth * fit.scale)
    context.drawPath(using: .fillStroke)
  }
}
