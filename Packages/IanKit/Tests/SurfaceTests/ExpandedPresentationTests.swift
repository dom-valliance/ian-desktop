import AppKit
import Attention
import Client
import Store
import SwiftUI
import TestSupport
import Testing

@testable import Surface

@Suite("Expanded client presentation")
@MainActor
struct ExpandedPresentationTests {
  init() {
    _ = NSApplication.shared
  }

  private func withController(
    camera: FakeCamera = FakeCamera(),
    _ body: (SurfaceController, SuppressionSignals) throws -> Void
  ) rethrows {
    try withScratchDefaults { defaults in
      let store = IanStore(
        service: ScriptedService(), profile: .mock,
        appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
      let signals = SuppressionSignals(camera: camera)
      try body(
        SurfaceController(store: store, signals: signals, defaults: defaults, quit: {}), signals)
    }
  }

  @Test("does not animate before the expanded client has opened")
  func quietBeforeOpening() {
    withController { controller, _ in
      #expect(!controller.isExpandedAnimating)
      #expect(controller.expandedOpenedAt == nil)
    }
  }

  @Test("animates while the expanded client is shown and stops when it is hidden")
  func animatesOnlyWhileShown() {
    withController { controller, _ in
      controller.showExpanded()
      #expect(controller.isExpandedAnimating)
      #expect(controller.expandedOpenedAt != nil)
      controller.hideExpanded()
      #expect(!controller.isExpandedAnimating)
    }
  }

  @Test("stops animating while suppressed, though the panel stays open")
  func stopsWhenSuppressed() {
    withController { controller, signals in
      controller.showExpanded()
      signals.isPaused = true
      #expect(controller.isExpandedVisible)
      #expect(!controller.isExpandedAnimating)
      controller.hideExpanded()
    }
  }

  @Test("stamps a new opening time each time the panel opens, and not on a repeated open")
  func stampsEachOpening() async {
    await withScratchDefaultsAsync { defaults in
      let store = IanStore(
        service: ScriptedService(), profile: .mock,
        appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
      let controller = SurfaceController(
        store: store, signals: SuppressionSignals(camera: FakeCamera()), defaults: defaults,
        quit: {})
      controller.showExpanded()
      let first = controller.expandedOpenedAt
      controller.showExpanded()
      #expect(controller.expandedOpenedAt == first)
      controller.hideExpanded()
      try? await Task.sleep(for: .milliseconds(5))
      controller.showExpanded()
      #expect(controller.expandedOpenedAt != first)
      controller.hideExpanded()
    }
  }

  @Test("hosts the app's content in the expanded panel, still hidden from screen capture")
  func hostsContent() {
    withController { controller, _ in
      let before = controller.windows[2].contentView
      controller.setExpandedContent(Text("Content"))
      #expect(controller.windows[2].contentView !== before)
      #expect(controller.windows[2].sharingType == .none)
    }
  }
}
