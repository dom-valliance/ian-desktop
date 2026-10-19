import AppKit
import SnapshotTesting
import SwiftUI
import Testing

@testable import Surface

/// The field drawn from each scenario's fixture, fully grown and nothing selected, through the
/// same pure renderer the app uses. Motion on is drawn at a fixed time, so the yaw is off its
/// resting angle.
@Suite("Pillars snapshots")
@MainActor
struct PillarsSnapshotTests {
  private static let time = 3.0
  private static let scale: CGFloat = 2

  private func image(_ scenario: String, reducedMotion: Bool) -> NSImage {
    let drawing = PillarsRenderer.drawing(
      for: OrbitScenario.load(scenario).pillarsScene, time: Self.time,
      reducedMotion: reducedMotion)
    let view = PillarsDrawingView(drawing: drawing)
      .frame(width: PillarsRenderer.boxSize.width, height: PillarsRenderer.boxSize.height)
      .background(OrbitPalette.ground.color)
    let renderer = ImageRenderer(content: view)
    renderer.scale = Self.scale
    guard let image = renderer.nsImage else {
      preconditionFailure("The Pillars field did not render to an image.")
    }
    return image
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
}
