import AppKit
import QuartzCore
import SwiftUI

/// The parts of the Orbit that move: the working core, which breathes, and the rim of each
/// alert, which pulses. They are drawn by Core Animation layers while the Orbit animates, and by
/// the still pose otherwise (ADR 0017).
struct OrbitMotion: Equatable {
  var core: OrbitDrawing.Core?
  var rims: [OrbitDrawing.Satellite]

  static let still = OrbitMotion(core: nil, rims: [])

  var isStill: Bool { core == nil && rims.isEmpty }
}

/// The Orbit's breath and pulse as `CABasicAnimation`s on shape layers. The render server runs
/// them, so Ian's process does no work per frame (ADR 0017).
///
/// The layers live in the renderer's 100 by 100 box, scaled to the view, so every position is
/// the renderer's own. With no motion there are no layers and no animations.
@MainActor
final class OrbitMotionView: NSView {
  static let breathKey = "breath"
  static let pulseKey = "pulse"

  private let box = CALayer()
  private var applied = OrbitMotion.still

  private(set) var coreLayer: CAShapeLayer?
  private(set) var rimLayers: [CAShapeLayer] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    box.bounds = CGRect(x: 0, y: 0, width: OrbitRenderer.boxSize, height: OrbitRenderer.boxSize)
    box.anchorPoint = .zero
    box.position = .zero
    // The renderer's y axis points down.
    box.isGeometryFlipped = true
    layer?.addSublayer(box)
  }

  required init?(coder: NSCoder) {
    fatalError("OrbitMotionView is built in code.")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func isAccessibilityElement() -> Bool { false }

  override func layout() {
    super.layout()
    let scale = min(bounds.width, bounds.height) / OrbitRenderer.boxSize
    withoutImplicitAnimation { box.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale)) }
  }

  /// Shows `motion`: the layers and their animations, or nothing for `.still`. Applying the same
  /// motion twice leaves the running animations alone, so a redraw does not restart the breath.
  func apply(_ motion: OrbitMotion) {
    guard motion != applied else { return }
    applied = motion
    withoutImplicitAnimation {
      for layer in box.sublayers ?? [] { layer.removeFromSuperlayer() }
      coreLayer = motion.core.map(makeCoreLayer)
      rimLayers = motion.rims.compactMap(makeRimLayer)
      for layer in [coreLayer].compactMap({ $0 }) + rimLayers { box.addSublayer(layer) }
    }
  }

  private func makeCoreLayer(_ core: OrbitDrawing.Core) -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.frame = box.bounds
    layer.path = Self.circle(at: OrbitRenderer.centre, radius: core.radius)
    layer.fillColor = core.colour.cgColor
    let breath = CABasicAnimation(keyPath: "path")
    breath.fromValue = Self.circle(
      at: OrbitRenderer.centre, radius: OrbitRenderer.restingCoreRadius)
    breath.toValue = Self.circle(
      at: OrbitRenderer.centre,
      radius: OrbitRenderer.restingCoreRadius + OrbitRenderer.breathRange)
    layer.add(Self.loop(breath, rate: OrbitRenderer.breathRate), forKey: Self.breathKey)
    return layer
  }

  private func makeRimLayer(_ satellite: OrbitDrawing.Satellite) -> CAShapeLayer? {
    guard let rim = satellite.rim else { return nil }
    let layer = CAShapeLayer()
    layer.frame = box.bounds
    layer.path = Self.circle(at: satellite.centre, radius: satellite.radius)
    layer.fillColor = nil
    layer.strokeColor = rim.colour.withAlpha(1).cgColor
    layer.lineWidth = rim.width
    let pulse = CABasicAnimation(keyPath: "opacity")
    pulse.fromValue = OrbitRenderer.rimMinimumAlpha
    pulse.toValue = 1.0
    layer.add(Self.loop(pulse, rate: OrbitRenderer.pulseRate), forKey: Self.pulseKey)
    return layer
  }

  /// A sine of `rate` radians a second runs from low to high in half its period, and back in the
  /// other half. Ease in and out follows a sine closely enough to match its range and timing.
  private static func loop(_ animation: CABasicAnimation, rate: Double) -> CABasicAnimation {
    animation.duration = Double.pi / rate
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    return animation
  }

  private static func circle(at centre: CGPoint, radius: Double) -> CGPath {
    CGPath(
      ellipseIn: CGRect(
        x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2),
      transform: nil)
  }

  private func withoutImplicitAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
  }
}

extension OrbitColour {
  var cgColor: CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
  }
}

/// Puts `OrbitMotionView` over the still pose.
struct OrbitMotionLayers: NSViewRepresentable {
  let motion: OrbitMotion

  func makeNSView(context: Context) -> OrbitMotionView {
    OrbitMotionView(frame: .zero)
  }

  func updateNSView(_ view: OrbitMotionView, context: Context) {
    view.apply(motion)
  }
}
