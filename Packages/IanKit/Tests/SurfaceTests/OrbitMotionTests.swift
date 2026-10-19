import AppKit
import Attention
import QuartzCore
import SwiftUI
import TestSupport
import Testing

@testable import Surface

/// The Orbit's breath and pulse as Core Animation layers (ADR 0017): when they run, what they
/// animate, and that their geometry is the renderer's.
@Suite("Orbit motion")
@MainActor
struct OrbitMotionTests {
  private func model(_ scenario: String) -> OrbitModel {
    OrbitModel(state: OrbitScenario.load(scenario).state, suppression: .none)
  }

  private func motion(
    _ model: OrbitModel, reducedMotion: Bool = false, isAnimating: Bool = true
  ) -> OrbitMotion {
    OrbitView.motion(model: model, reducedMotion: reducedMotion, isAnimating: isAnimating)
  }

  private func motionView(showing motion: OrbitMotion, side: CGFloat = 96) -> OrbitMotionView {
    let view = OrbitMotionView(frame: CGRect(x: 0, y: 0, width: side, height: side))
    view.apply(motion)
    view.layoutSubtreeIfNeeded()
    return view
  }

  private func animation(of layer: CAShapeLayer?, key: String) throws -> CABasicAnimation {
    try #require(layer?.animation(forKey: key) as? CABasicAnimation)
  }

  private func bounds(of value: Any?) throws -> CGRect {
    // The animation's values are the CGPaths this view set.
    try #require((value as! CGPath?)?.boundingBoxOfPath)
  }

  // MARK: Breath

  @Test("breathes the core between radius 6 and 7 over half the sine's period while working")
  func breath() throws {
    let view = motionView(showing: motion(model("normal")))
    let breath = try animation(of: view.coreLayer, key: OrbitMotionView.breathKey)
    #expect(breath.keyPath == "path")
    #expect(abs(breath.duration - Double.pi / 1.5) < 1e-9)
    #expect(breath.autoreverses)
    #expect(breath.repeatCount == .infinity)
    #expect(breath.timingFunction == CAMediaTimingFunction(name: .easeInEaseOut))
    #expect(abs(try bounds(of: breath.fromValue).width - 12) < 1e-6)
    #expect(abs(try bounds(of: breath.toValue).width - 14) < 1e-6)
  }

  @Test("draws the core's layer at the renderer's centre and radius")
  func coreGeometry() throws {
    let model = model("normal")
    let core = OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true).core
    let view = motionView(showing: motion(model))
    let box = try bounds(of: try #require(view.coreLayer).path)
    #expect(box.midX == OrbitRenderer.centre.x)
    #expect(box.midY == OrbitRenderer.centre.y)
    #expect(abs(box.width - core.radius * 2) < 1e-6)
    #expect(view.coreLayer?.fillColor == core.colour.cgColor)
  }

  @Test("breathes nothing when the core is not working")
  func noBreathWhenIdle() {
    let view = motionView(showing: motion(model("incident")))
    #expect(view.coreLayer == nil)
  }

  // MARK: Pulse

  @Test("pulses each alert's rim between half and full opacity over half the sine's period")
  func pulse() throws {
    let model = model("incident")
    let view = motionView(showing: motion(model))
    let alerts = model.satellites.filter { $0.kind == .alert }.count
    #expect(alerts > 0)
    #expect(view.rimLayers.count == alerts)
    for layer in view.rimLayers {
      let pulse = try animation(of: layer, key: OrbitMotionView.pulseKey)
      #expect(pulse.keyPath == "opacity")
      #expect(abs(pulse.duration - Double.pi / 5) < 1e-9)
      #expect(pulse.fromValue as? Double == 0.5)
      #expect(pulse.toValue as? Double == 1.0)
      #expect(pulse.autoreverses)
      #expect(pulse.repeatCount == .infinity)
      #expect(pulse.timingFunction == CAMediaTimingFunction(name: .easeInEaseOut))
    }
  }

  @Test("draws each rim's layer on the renderer's satellite, with its width")
  func rimGeometry() throws {
    let model = model("incident")
    let satellites = OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true).satellites
      .filter { $0.rim != nil }
    let view = motionView(showing: motion(model))
    #expect(view.rimLayers.count == satellites.count)
    for (layer, satellite) in zip(view.rimLayers, satellites) {
      let box = try bounds(of: layer.path)
      #expect(abs(box.midX - satellite.centre.x) < 1e-9)
      #expect(abs(box.midY - satellite.centre.y) < 1e-9)
      #expect(abs(box.width - satellite.radius * 2) < 1e-6)
      #expect(Double(layer.lineWidth) == satellite.rim?.width)
      #expect(layer.fillColor == nil)
    }
  }

  @Test("scales the renderer's box to the view without moving any layer")
  func scalesToTheView() throws {
    let view = motionView(showing: motion(model("incident")), side: 96)
    let box = try #require(view.layer?.sublayers?.first)
    #expect(box.affineTransform().a == 0.96)
    #expect(box.affineTransform().d == 0.96)
    #expect(box.bounds.size == CGSize(width: 100, height: 100))
    #expect(box.position == .zero)
  }

  @Test("puts the renderer's y axis, which points down, at the top of the view")
  func yAxisPointsDown() throws {
    let model = model("incident")
    let satellites = OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true).satellites
      .filter { $0.rim != nil }
    let view = motionView(showing: motion(model), side: 96)
    let root = try #require(view.layer)
    for (layer, satellite) in zip(view.rimLayers, satellites) {
      let point = root.convert(satellite.centre, from: layer)
      #expect(abs(point.x - satellite.centre.x * 0.96) < 1e-6)
      #expect(abs(point.y - (100 - satellite.centre.y) * 0.96) < 1e-6)
    }
  }

  // MARK: When motion runs

  @Test("runs while visible, unsuppressed and with motion on, for a working core and an alert")
  func runsWhenAllowed() {
    #expect(motion(model("normal")).core != nil)
    #expect(!motion(model("incident")).rims.isEmpty)
  }

  @Test("runs nothing when nothing in the model moves")
  func nothingToMove() {
    #expect(motion(model("quiet")).isStill)
  }

  @Test(
    "leaves no layer and no animation when hidden, suppressed or reduced",
    arguments: ["normal", "incident"],
    [
      (isAnimating: false, reducedMotion: false),
      (isAnimating: true, reducedMotion: true),
      (isAnimating: false, reducedMotion: true),
    ])
  func removedWhenNotAllowed(
    scenario: String, state: (isAnimating: Bool, reducedMotion: Bool)
  ) {
    let model = model(scenario)
    let running = motionView(showing: motion(model))
    #expect(running.coreLayer != nil || !running.rimLayers.isEmpty)
    running.apply(
      motion(model, reducedMotion: state.reducedMotion, isAnimating: state.isAnimating))
    #expect(running.coreLayer == nil)
    #expect(running.rimLayers.isEmpty)
    #expect(running.layer?.sublayers?.first?.sublayers?.isEmpty ?? true)
  }

  @Test("adds the animations again when motion is allowed again")
  func addedAgain() throws {
    let model = model("normal")
    let view = motionView(showing: motion(model, isAnimating: false))
    #expect(view.coreLayer == nil)
    view.apply(motion(model))
    _ = try animation(of: view.coreLayer, key: OrbitMotionView.breathKey)
  }

  @Test("keeps a running animation when the same motion is applied again")
  func notRestarted() throws {
    let model = model("normal")
    let view = motionView(showing: motion(model))
    let layer = try #require(view.coreLayer)
    view.apply(motion(model))
    #expect(view.coreLayer === layer)
  }

  @Test("stops the Orbit's motion for each suppression trigger")
  func suppressedControllerDoesNotAnimate() async {
    let triggers: [(camera: Bool, meeting: Bool, quiet: Bool, paused: Bool)] = [
      (true, false, false, false), (false, true, false, false), (false, false, true, false),
      (false, false, false, true),
    ]
    for trigger in triggers {
      await withScratchDefaultsAsync { defaults in
        let camera = FakeCamera()
        camera.isLive = trigger.camera
        let signals = SuppressionSignals(camera: camera)
        signals.start()
        signals.isPaused = trigger.paused
        let store = await loadedStore(
          OrbitScenario.load("incident"), externalMeeting: trigger.meeting,
          quietHours: trigger.quiet)
        defer { store.stop() }
        let controller = SurfaceController(
          store: store, signals: signals, defaults: defaults, quit: {})
        #expect(!controller.isOrbitAnimating, "\(trigger)")
        #expect(
          OrbitView.motion(
            model: controller.presentation.model, reducedMotion: false,
            isAnimating: controller.isOrbitAnimating
          ).isStill)
      }
    }
  }

  // MARK: The still pose

  /// The Orbit's still pose in a bitmap, with the layered parts left out as `layered` says.
  private func pixels(of model: OrbitModel, layered: OrbitMotion) throws -> NSBitmapImageRep {
    let side: CGFloat = 400
    let view = OrbitDrawingView(
      drawing: OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true), layered: layered
    )
    .frame(width: side, height: side)
    .background(OrbitPalette.ground.color)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    return NSBitmapImageRep(cgImage: image)
  }

  /// Whether the pixel at a point in the renderer's 100 unit box is the bitmap's background,
  /// which the corner shows (colour management shifts the ground's own value).
  private func isGround(_ bitmap: NSBitmapImageRep, at point: CGPoint) throws -> Bool {
    let scale = Double(bitmap.pixelsWide) / OrbitRenderer.boxSize
    let pixel = try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
    let ground = try #require(bitmap.colorAt(x: 0, y: 0))
    return abs(pixel.redComponent - ground.redComponent) < 0.01
      && abs(pixel.greenComponent - ground.greenComponent) < 0.01
      && abs(pixel.blueComponent - ground.blueComponent) < 0.01
  }

  @Test("leaves the working core out of the still pose only when a layer draws it")
  func stillPoseLeavesLayeredCore() throws {
    let model = model("normal")
    let core = OrbitRenderer.centre
    #expect(try !isGround(pixels(of: model, layered: .still), at: core))
    #expect(try isGround(pixels(of: model, layered: motion(model)), at: core))
  }

  @Test("leaves each alert's rim out of the still pose only when a layer draws it")
  func stillPoseLeavesLayeredRims() throws {
    let model = model("incident")
    let rimmed = motion(model).rims
    #expect(!rimmed.isEmpty)
    let still = try pixels(of: model, layered: .still)
    let layered = try pixels(of: model, layered: motion(model))
    for satellite in rimmed {
      // Half a unit outside the satellite's fill is on the rim's stroke, and towards the centre
      // it is clear of the track, the arcs and the core.
      let inwards = CGVector(
        dx: OrbitRenderer.centre.x - satellite.centre.x,
        dy: OrbitRenderer.centre.y - satellite.centre.y)
      let length = hypot(inwards.dx, inwards.dy)
      let distance = satellite.radius + 0.5
      let edge = CGPoint(
        x: satellite.centre.x + inwards.dx / length * distance,
        y: satellite.centre.y + inwards.dy / length * distance)
      #expect(try !isGround(still, at: edge), "still pose, slot \(satellite.slot)")
      #expect(try isGround(layered, at: edge), "layered, slot \(satellite.slot)")
    }
  }

  @Test("keeps the core's layer running when only the rims change")
  func coreKeptWhenRimsChange() throws {
    let working = model("normal")
    let first = motion(working)
    let view = motionView(showing: first)
    let layer = try #require(view.coreLayer)
    var changed = first
    changed.rims = motion(model("incident")).rims
    view.apply(changed)
    #expect(view.coreLayer === layer)
    #expect(view.rimLayers.count == changed.rims.count)
  }

  @Test("keeps a rim's layer running when another rim goes")
  func rimKeptWhenAnotherGoes() throws {
    let rims = motion(model("incident")).rims
    try #require(rims.count >= 1)
    var two = OrbitMotion.still
    two.rims = rims + [rims[0].moved(toSlot: 4)]
    let view = motionView(showing: two)
    let layer = try #require(view.rimLayers.first)
    var one = two
    one.rims = rims
    view.apply(one)
    #expect(view.rimLayers.count == rims.count)
    #expect(view.rimLayers.first === layer)
  }

  @Test("runs the breath and the pulse at a capped frame rate")
  func cappedFrameRate() throws {
    let working = motionView(showing: motion(model("normal")))
    let breath = try animation(of: working.coreLayer, key: OrbitMotionView.breathKey)
    #expect(breath.preferredFrameRateRange.maximum <= 30)
    let alert = motionView(showing: motion(model("incident")))
    let pulse = try animation(of: alert.rimLayers.first, key: OrbitMotionView.pulseKey)
    #expect(pulse.preferredFrameRateRange.maximum <= 30)
  }

  @Test("shows the layers inside a hosted Orbit at the still pose's scale and positions")
  func hosted() throws {
    let model = model("incident")
    let hosting = NSHostingView(
      rootView: OrbitView(model: model, reducedMotion: false, isAnimating: true)
        .frame(width: 96, height: 96))
    hosting.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
    let panel = WindowFactory.makeOrbitPanel(content: hosting)
    hosting.layoutSubtreeIfNeeded()
    defer { panel.orderOut(nil) }

    let found = Self.descendants(of: hosting).compactMap { $0 as? OrbitMotionView }
    #expect(found.count == 1)
    let view = try #require(found.first)
    let box = try #require(view.layer?.sublayers?.first)
    #expect(abs(box.affineTransform().a - 0.96) < 1e-9)

    let satellites = OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true).satellites
      .filter { $0.rim != nil }
    #expect(view.rimLayers.count == satellites.count)
    for (layer, satellite) in zip(view.rimLayers, satellites) {
      let inView = try #require(view.layer).convert(satellite.centre, from: layer)
      let inHosting = hosting.convert(inView, from: view)
      // The still pose draws with y down, so compare in top-down coordinates.
      let top = hosting.isFlipped ? inHosting.y : hosting.bounds.height - inHosting.y
      #expect(abs(inHosting.x - satellite.centre.x * 0.96) < 1e-6)
      #expect(abs(top - satellite.centre.y * 0.96) < 1e-6)
    }
  }

  private static func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
  }

  // MARK: No clock

  @Test("has no timeline or display link driving the Orbit")
  func noClock() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/Surface")
    for name in ["OrbitView", "OrbitMotion", "OrbitHostView", "OrbitRenderer", "SurfaceViews"] {
      let text = try String(
        contentsOf: sources.appendingPathComponent("\(name).swift"), encoding: .utf8)
      for banned in ["TimelineView", "CADisplayLink", "CVDisplayLink", "Timer.scheduled"] {
        #expect(!text.contains(banned), "\(name).swift uses \(banned)")
      }
    }
  }
}

extension OrbitDrawing.Satellite {
  /// The same satellite in another slot, for a test that needs a second rim.
  fileprivate func moved(toSlot slot: Int) -> OrbitDrawing.Satellite {
    OrbitDrawing.Satellite(
      slot: slot, centre: centre, radius: radius, colour: colour, rim: rim)
  }
}
