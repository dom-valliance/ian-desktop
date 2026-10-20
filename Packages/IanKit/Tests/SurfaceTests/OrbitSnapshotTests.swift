import AppKit
import Attention
import SnapshotTesting
import Testing

@testable import Surface

/// The Orbit drawn from each scenario's fixture, through the same pure renderer the app uses.
/// Motion on is drawn at a fixed time, so the breath and the pulse are mid-cycle.
@Suite("Orbit snapshots")
@MainActor
struct OrbitSnapshotTests {
  private static let time = 0.6

  private func image(_ scenario: String, reducedMotion: Bool) -> NSImage {
    let model = OrbitModel(state: OrbitScenario.load(scenario).state, suppression: .none)
    return OrbitImage.of(model, time: Self.time, reducedMotion: reducedMotion)
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

extension OrbitSnapshotTests {
  /// The suppressed Orbit shows the same state with no item text, so it is drawn as the same
  /// pixels as the unsuppressed one and is held to the reference that one already has.
  @Test("draws a suppressed Orbit as the state alone, like its unsuppressed reference")
  func suppressed() {
    let scenario = OrbitScenario.load("normal")
    let model = OrbitModel(
      state: scenario.state,
      suppression: Suppression(
        cameraLive: true, externalMeeting: false, quietHours: false, userPaused: false))
    #expect(model.topTitle == nil)
    assertSnapshot(
      of: OrbitImage.of(model, time: Self.time, reducedMotion: true),
      as: .image(precision: 0.998, perceptualPrecision: 0.98), named: "normal-motion-off",
      testName: "orbit")
  }
}
