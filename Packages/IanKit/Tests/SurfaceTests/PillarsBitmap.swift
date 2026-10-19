import AppKit

@testable import Surface

/// Paints a drawing with the live field's painter into a bitmap on the ground colour, so tests
/// compare what the screen shows.
@MainActor
enum PillarsBitmap {
  static func image(
    of drawing: PillarsDrawing, scale: CGFloat, size: CGSize = PillarsRenderer.boxSize
  ) -> NSImage {
    NSImage(cgImage: cgImage(of: drawing, scale: scale, size: size), size: size)
  }

  static func cgImage(
    of drawing: PillarsDrawing, scale: CGFloat, size: CGSize = PillarsRenderer.boxSize
  ) -> CGImage {
    let width = Int(size.width * scale)
    let height = Int(size.height * scale)
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { preconditionFailure("The bitmap context could not be made.") }
    // The painter expects the top left as the origin, as a flipped view's context has.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    context.setFillColor(OrbitPalette.ground.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    PillarsPainter.paint(drawing, in: context, fit: PillarsFit(size: size), labels: PillarsLabels())
    guard let image = context.makeImage() else {
      preconditionFailure("The Pillars field did not render to an image.")
    }
    return image
  }
}
