import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Surface

@Suite("Valliance star shape")
struct StarShapeTests {
  private static let side = 100.0
  private let path = StarShape.path(in: CGRect(x: 0, y: 0, width: side, height: side))

  private func contains(_ x: Double, _ y: Double) -> Bool {
    path.contains(CGPoint(x: x, y: y), using: .winding)
  }

  @Test("is symmetric about both axes and both diagonals")
  func symmetric() {
    let side = Self.side
    for step in 1..<40 {
      for other in 1..<40 {
        let x = Double(step) * 2.5 + 0.3
        let y = Double(other) * 2.5 + 0.7
        let here = contains(x, y)
        #expect(contains(side - x, y) == here, "left to right at \(x), \(y)")
        #expect(contains(x, side - y) == here, "top to bottom at \(x), \(y)")
        #expect(contains(y, x) == here, "across the diagonal at \(x), \(y)")
        #expect(contains(side - y, side - x) == here, "across the other diagonal at \(x), \(y)")
      }
    }
  }

  @Test("reaches the middle of each side with a flat arm end")
  func armsReachTheSides() {
    let middle = Self.side / 2
    #expect(contains(middle, 0.5))
    #expect(contains(middle, Self.side - 0.5))
    #expect(contains(0.5, middle))
    #expect(contains(Self.side - 0.5, middle))
    // The arm is about 17.6 wide at its end: in at 8 either side of the middle, out at 10.
    #expect(contains(middle + 8, 0.5))
    #expect(!contains(middle + 10, 0.5))
    #expect(!contains(middle - 10, 0.5))
  }

  @Test("leaves a hole at the centre")
  func centreIsAHole() {
    #expect(!contains(50, 50))
    #expect(!contains(52, 50))
    #expect(!contains(50, 47))
    // The arms are solid between the hole and the sides.
    #expect(contains(50, 30))
    #expect(contains(30, 50))
  }

  @Test("leaves the four corners of the square empty")
  func cornersAreEmpty() {
    for (x, y) in [(1.0, 1.0), (99.0, 1.0), (1.0, 99.0), (99.0, 99.0), (10.0, 10.0)] {
      #expect(!contains(x, y), "corner at \(x), \(y)")
    }
  }

  @Test("fits inside its square")
  func staysInsideItsSquare() {
    let box = path.boundingBoxOfPath
    #expect(abs(box.minX) < 1e-9 && abs(box.minY) < 1e-9)
    #expect(abs(box.width - Self.side) < 1e-9 && abs(box.height - Self.side) < 1e-9)
  }

  @Test("centres on a point at the half side asked for")
  func centred() {
    let box = StarShape.path(centre: CGPoint(x: 50, y: 40), halfSide: 9).boundingBoxOfPath
    #expect(abs(box.midX - 50) < 1e-9 && abs(box.midY - 40) < 1e-9)
    #expect(abs(box.width - 18) < 1e-9)
  }

  // MARK: Fidelity

  /// The measured intersection over union of the path, rasterised at 516 points square, with the
  /// off-white brand PNG's alpha is 0.995 at an inner radius fraction of 0.412.
  @Test("matches the brand symbol with an intersection over union of at least 0.97")
  func matchesBrandSymbol() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("assets/Valliance_Symbol RGB Solid OffWhite.png")
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let symbol = try Self.alpha(of: image)
    let box = try #require(symbol.opaqueBounds)
    #expect(box.width == box.height)

    let side = box.width
    let mine = try Self.alpha(
      drawing: StarShape.path(in: CGRect(x: 0, y: 0, width: side, height: side)),
      width: side, height: side)

    var intersection = 0
    var union = 0
    for row in 0..<side {
      for column in 0..<side {
        let theirs = symbol.isOpaque(column: box.minX + column, row: box.minY + row)
        let ours = mine.isOpaque(column: column, row: row)
        if theirs && ours { intersection += 1 }
        if theirs || ours { union += 1 }
      }
    }
    let ratio = Double(intersection) / Double(union)
    #expect(ratio >= 0.97, "intersection over union was \(ratio)")
  }

  private struct Alpha {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func isOpaque(column: Int, row: Int) -> Bool { bytes[row * width + column] > 127 }

    var opaqueBounds: (minX: Int, minY: Int, width: Int, height: Int)? {
      var minX = width
      var maxX = -1
      var minY = height
      var maxY = -1
      for row in 0..<height {
        for column in 0..<width where isOpaque(column: column, row: row) {
          minX = min(minX, column)
          maxX = max(maxX, column)
          minY = min(minY, row)
          maxY = max(maxY, row)
        }
      }
      guard maxX >= 0 else { return nil }
      return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
  }

  private static func alpha(of image: CGImage) throws -> Alpha {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Alpha(
      width: width, height: height, bytes: (0..<width * height).map { pixels[$0 * 4 + 3] })
  }

  private static func alpha(drawing path: CGPath, width: Int, height: Int) throws -> Alpha {
    var pixels = [UInt8](repeating: 0, count: width * height)
    let context = try #require(
      CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(path)
    context.fillPath()
    return Alpha(width: width, height: height, bytes: pixels)
  }
}
