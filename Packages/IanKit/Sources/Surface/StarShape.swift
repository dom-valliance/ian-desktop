import CoreGraphics

/// The Valliance star as a vector path, so it stays sharp at every scale and takes any fill.
///
/// The symbol is the union of four quarter rings, each centred on one corner of a square of side
/// `s`, with an inner radius of `innerRadiusFraction * s` and an outer radius of `s` less that.
/// The union is a four pointed star: each arm ends flat at the middle of a side, about 0.176 `s`
/// wide, and the points farther than the outer radius from every corner leave a concave diamond
/// hole at the centre.
///
/// The fraction was fitted to the brand source, `assets/Valliance_Symbol RGB Solid OffWhite.png`,
/// by maximising the intersection over union of the two shapes' coverage. The fit is 0.412, at an
/// intersection over union of 0.995.
///
/// The four rings wind the same way, so the default non-zero fill rule gives their union and keeps
/// the centre hole. Do not fill the path with the even-odd rule: it would punch out the overlaps.
enum StarShape {
  static let innerRadiusFraction = 0.412

  /// The star in the square `rect`, which is expected to be square.
  static func path(in rect: CGRect) -> CGPath {
    let side = min(rect.width, rect.height)
    let inner = innerRadiusFraction * side
    let outer = side - inner
    let corners: [(point: CGPoint, quadrant: Double)] = [
      (CGPoint(x: rect.minX, y: rect.minY), 0),
      (CGPoint(x: rect.minX + side, y: rect.minY), 1),
      (CGPoint(x: rect.minX + side, y: rect.minY + side), 2),
      (CGPoint(x: rect.minX, y: rect.minY + side), 3),
    ]
    let path = CGMutablePath()
    for (corner, quadrant) in corners {
      let start = quadrant * .pi / 2
      let end = start + .pi / 2
      path.move(
        to: CGPoint(x: corner.x + outer * cos(start), y: corner.y + outer * sin(start)))
      path.addArc(
        center: corner, radius: outer, startAngle: start, endAngle: end, clockwise: false)
      path.addArc(
        center: corner, radius: inner, startAngle: end, endAngle: start, clockwise: true)
      path.closeSubpath()
    }
    return path
  }

  /// The star centred on `centre`, `halfSide` from the centre to the end of each arm.
  static func path(centre: CGPoint, halfSide: Double) -> CGPath {
    path(
      in: CGRect(
        x: centre.x - halfSide, y: centre.y - halfSide, width: halfSide * 2, height: halfSide * 2))
  }
}
