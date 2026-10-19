import AppKit
import SnapshotTesting
import Testing

@testable import Surface

/// The field drawn from each scenario's fixture, fully grown and nothing selected, through the
/// same renderer and Core Graphics painter the app uses. Motion on is drawn at a fixed time, so the yaw is off its
/// resting angle.
@Suite("Pillars snapshots")
@MainActor
struct PillarsSnapshotTests {
  private static let time = 3.0
  private static let scale: CGFloat = 2

  private func image(
    _ scenario: String, reducedMotion: Bool, angle: Double = FieldTurn.defaultAngle
  ) -> NSImage {
    let drawing = PillarsRenderer.drawing(
      for: OrbitScenario.load(scenario).pillarsScene, time: Self.time,
      reducedMotion: reducedMotion, angle: angle)
    return PillarsBitmap.image(of: drawing, scale: Self.scale)
  }

  @Test("matches the reference with motion on", arguments: OrbitScenario.names)
  func motionOn(scenario: String) {
    assertSnapshot(
      of: image(scenario, reducedMotion: false),
      as: .image(precision: 0.998, perceptualPrecision: 0.98), named: "\(scenario)-motion-on",
      testName: "pillars")
  }

  @Test("matches the reference with motion off", arguments: OrbitScenario.names)
  func motionOff(scenario: String) {
    assertSnapshot(
      of: image(scenario, reducedMotion: true),
      as: .image(precision: 0.998, perceptualPrecision: 0.98), named: "\(scenario)-motion-off",
      testName: "pillars")
  }

  @Test("matches the reference turned to the angle, with motion off", arguments: [135.0, 225.0])
  func turned(angle: Double) {
    assertSnapshot(
      of: image("normal", reducedMotion: true, angle: angle),
      as: .image(precision: 0.998, perceptualPrecision: 0.98),
      named: "normal-motion-off-\(Int(angle))", testName: "pillars")
  }
}
