import Foundation

/// The Orbit as shapes in a 100 by 100 box, ready to draw.
public struct OrbitDrawing: Equatable, Sendable {
  public struct Arc: Equatable, Sendable {
    public let radius: Double
    /// The share of the circumference, clockwise from 12 o'clock, above 0 and at most 1.
    public let fraction: Double
    public let colour: OrbitColour
  }

  public struct Core: Equatable, Sendable {
    public let radius: Double
    public let colour: OrbitColour
  }

  public struct Rim: Equatable, Sendable {
    public let width: Double
    public let colour: OrbitColour
  }

  public struct Satellite: Equatable, Sendable {
    public let slot: Int
    public let centre: CGPoint
    public let radius: Double
    public let colour: OrbitColour
    public let rim: Rim?
  }

  public struct Chip: Equatable, Sendable {
    public let rect: CGRect
    public let text: String
  }

  public let loadArc: Arc?
  public let overMedianArc: Arc?
  public let core: Core
  public let satellites: [Satellite]
  public let chip: Chip?
}

/// A pure function from the Orbit model, the time and the motion setting to a drawing
/// (ADR 0004). Reduce Motion is a parameter, not another code path: it fixes the breath at its
/// midpoint and the pulse at full.
public enum OrbitRenderer {
  public static let boxSize = 100.0
  public static let centre = CGPoint(x: 50, y: 50)
  public static let trackRadius = 34.0
  public static let overMedianRadius = 42.0
  public static let trackWidth = 2.5
  /// Degrees from 3 o'clock, clockwise on screen. The first satellite is at 12 o'clock.
  public static let satelliteAngles: [Double] = [-90, -18, 54, 126, 198]

  static let restingCoreRadius = 6.0
  static let satelliteRadius = 4.5
  static let alertRadius = 6.5
  static let rimWidth = 1.5
  /// The Scale artboard draws the chip in a 160 unit box; this maps it to the 100 unit box.
  static let chipScale = 100.0 / 160.0
  static let chipStroke = 1.0 * chipScale

  /// Whether anything in the drawing changes with time, so the caller can stop its clock.
  public static func hasMotion(_ model: OrbitModel) -> Bool {
    model.working || model.satellites.contains { $0.kind == .alert }
  }

  /// The inner ring's share of the circumference: `min(1, load / median)`.
  public static func loadFraction(load: Int, median: Double) -> Double {
    min(1, Double(load) / median)
  }

  /// The outer arc's share: `clamp(load / median - 1, 0, 1)`.
  public static func overMedianFraction(load: Int, median: Double) -> Double {
    max(0, min(1, Double(load) / median - 1))
  }

  public static func drawing(
    for model: OrbitModel, time: Double, reducedMotion: Bool
  ) -> OrbitDrawing {
    let breath = reducedMotion ? 0.5 : 0.5 + 0.5 * sin(1.5 * time)
    let pulse = reducedMotion ? 1.0 : 0.5 + 0.5 * sin(5 * time)

    let inner = loadFraction(load: model.load, median: model.median)
    let outer = overMedianFraction(load: model.load, median: model.median)

    let core =
      model.working
      ? OrbitDrawing.Core(
        radius: restingCoreRadius + breath, colour: OrbitPalette.workingCore)
      : OrbitDrawing.Core(radius: restingCoreRadius, colour: OrbitPalette.restingCore)

    let satellites = model.satellites.compactMap { satellite -> OrbitDrawing.Satellite? in
      guard satellite.slot < satelliteAngles.count else { return nil }
      let angle = satelliteAngles[satellite.slot] * .pi / 180
      let isAlert = satellite.kind == .alert
      return OrbitDrawing.Satellite(
        slot: satellite.slot,
        centre: CGPoint(
          x: centre.x + trackRadius * cos(angle), y: centre.y + trackRadius * sin(angle)),
        radius: isAlert ? alertRadius : satelliteRadius,
        colour: OrbitPalette.colour(for: satellite.kind),
        rim: isAlert
          ? OrbitDrawing.Rim(
            width: rimWidth, colour: OrbitPalette.rim.withAlpha(0.5 + 0.5 * pulse)) : nil)
    }

    return OrbitDrawing(
      loadArc: inner > 0
        ? OrbitDrawing.Arc(radius: trackRadius, fraction: inner, colour: OrbitPalette.loadArc)
        : nil,
      overMedianArc: outer > 0
        ? OrbitDrawing.Arc(
          radius: overMedianRadius, fraction: outer, colour: OrbitPalette.overMedianArc) : nil,
      core: core,
      satellites: satellites,
      chip: model.overflow > 0 ? chip(overflow: model.overflow) : nil)
  }

  /// The "+n" pill at the upper left of the ring, between the first and last satellites.
  private static func chip(overflow: Int) -> OrbitDrawing.Chip {
    let size = CGSize(width: 32 * chipScale, height: 24 * chipScale)
    let angle = -126.0 * .pi / 180
    let middle = CGPoint(
      x: centre.x + 40 * cos(angle), y: centre.y + 40 * sin(angle))
    return OrbitDrawing.Chip(
      rect: CGRect(
        x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width,
        height: size.height),
      text: "+\(overflow)")
  }
}
