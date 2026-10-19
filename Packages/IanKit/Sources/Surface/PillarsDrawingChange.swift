import CoreGraphics

extension PillarsDrawing {
  /// Whether `self` would look different from `other` once drawn. A point that has moved less
  /// than `pointTolerance` box units and a colour channel that has moved less than
  /// `colourTolerance` (on the 0 to 255 scale, alpha scaled to match) are the same picture.
  ///
  /// The sway moves the nearest corner under a device pixel for most frames, so redrawing every
  /// frame repaints the same pixels. The field repaints only when this says something shows
  /// (ADR 0018).
  func isVisiblyDifferent(
    from other: PillarsDrawing, pointTolerance: Double, colourTolerance: Double
  ) -> Bool {
    guard cells.count == other.cells.count, particles.count == other.particles.count,
      rowLabels.count == other.rowLabels.count
    else { return true }

    func differs(_ a: Polygon, _ b: Polygon) -> Bool {
      guard a.points.count == b.points.count, abs(a.lineWidth - b.lineWidth) < 0.05 else {
        return true
      }
      return a.fill.differs(from: b.fill, by: colourTolerance)
        || a.stroke.differs(from: b.stroke, by: colourTolerance)
        || zip(a.points, b.points).contains { $0.moved(from: $1, by: pointTolerance) }
    }

    if differs(plate, other.plate) { return true }
    for (a, b) in zip(rowLabels, other.rowLabels)
    where a.text != b.text || a.anchor.moved(from: b.anchor, by: pointTolerance) {
      return true
    }
    for (a, b) in zip(cells, other.cells) {
      if a.key != b.key || a.faces.count != b.faces.count
        || abs(a.opacity - b.opacity) * 255 >= colourTolerance || differs(a.tile, b.tile)
        || zip(a.faces, b.faces).contains(where: differs)
      {
        return true
      }
    }
    for (a, b) in zip(particles, other.particles)
    where a.centre.moved(from: b.centre, by: pointTolerance)
      || abs(a.radius - b.radius) >= pointTolerance
      || a.colour.differs(from: b.colour, by: colourTolerance)
    {
      return true
    }
    return false
  }
}

extension CGPoint {
  fileprivate func moved(from other: CGPoint, by tolerance: Double) -> Bool {
    abs(x - other.x) >= tolerance || abs(y - other.y) >= tolerance
  }
}

extension OrbitColour {
  fileprivate func differs(from other: OrbitColour, by tolerance: Double) -> Bool {
    abs(red - other.red) >= tolerance || abs(green - other.green) >= tolerance
      || abs(blue - other.blue) >= tolerance || abs(alpha - other.alpha) * 255 >= tolerance
  }
}
