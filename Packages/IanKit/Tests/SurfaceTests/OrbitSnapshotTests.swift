import AppKit
import Attention
import SnapshotTesting
import SwiftUI
import Testing

@testable import Surface

/// The Orbit drawn from each scenario's fixture, through the same pure renderer the app uses.
/// Motion on is drawn at a fixed time, so the breath and the pulse are mid-cycle.
@Suite("Orbit snapshots")
@MainActor
struct OrbitSnapshotTests {
  private static let time = 0.6
  private static let scale: CGFloat = 2

  private func image(_ scenario: String, reducedMotion: Bool) -> NSImage {
    let model = OrbitModel(state: OrbitScenario.load(scenario).state, suppression: .none)
    let drawing = OrbitRenderer.drawing(
      for: model, time: Self.time, reducedMotion: reducedMotion)
    let view = OrbitDrawingView(drawing: drawing)
      .frame(width: OrbitPlacement.avatarSize, height: OrbitPlacement.avatarSize)
      .background(OrbitPalette.ground.color)
    let renderer = ImageRenderer(content: view)
    renderer.scale = Self.scale
    guard let image = renderer.nsImage else {
      preconditionFailure("The Orbit did not render to an image.")
    }
    return image
  }

  @Test("matches the reference with motion on", arguments: OrbitScenario.names)
  func motionOn(scenario: String) {
    assertSnapshot(
      of: image(scenario, reducedMotion: false),
      as: .image(precision: 0.998, perceptualPrecision: 0.98), named: "\(scenario)-motion-on",
      testName: "orbit")
  }

  @Test("matches the reference with motion off", arguments: OrbitScenario.names)
  func motionOff(scenario: String) {
    assertSnapshot(
      of: image(scenario, reducedMotion: true),
      as: .image(precision: 0.998, perceptualPrecision: 0.98), named: "\(scenario)-motion-off",
      testName: "orbit")
  }
}
