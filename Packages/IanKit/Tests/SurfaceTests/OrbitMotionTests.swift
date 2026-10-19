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

  @Test("leaves out of the still pose exactly the parts the layers draw")
  func stillPoseLeavesLayeredParts() {
    for scenario in OrbitScenario.names {
      let model = model(scenario)
      let layered = motion(model)
      let rimmed = layered.rims.map(\.slot)
      let full = OrbitRenderer.drawing(for: model, time: 0, reducedMotion: true)
      #expect(layered.core == (model.working ? full.core : nil))
      #expect(rimmed == full.satellites.filter { $0.rim != nil }.map(\.slot))
    }
  }

  @Test("shows the layers inside a hosted Orbit, over the still pose")
  func hosted() {
    let hosting = NSHostingView(
      rootView: OrbitView(model: model("incident"), reducedMotion: false, isAnimating: true)
        .frame(width: 96, height: 96))
    hosting.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
    hosting.layoutSubtreeIfNeeded()
    let found = Self.descendants(of: hosting).compactMap { $0 as? OrbitMotionView }
    #expect(found.count == 1)
    #expect(found.first?.rimLayers.isEmpty == false)
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
