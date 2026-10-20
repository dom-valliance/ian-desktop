import AppKit
import Attention
import Client
import Store
import TestSupport
import Testing

@testable import Surface

@Suite("Showing an item")
@MainActor
struct ShowItemTests {
  init() {
    _ = NSApplication.shared
  }

  @Test("opens the panel and tells the client which view holds the item")
  func showsItem() {
    withScratchDefaults { defaults in
      let store = IanStore(
        service: ScriptedService(), profile: .mock,
        appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
      let controller = SurfaceController(
        store: store, signals: SuppressionSignals(camera: FakeCamera()), defaults: defaults,
        quit: {})
      var shown: [ItemDestination] = []
      controller.onShowItem = { shown.append($0) }

      controller.showItem(.alerts)
      defer { controller.hideExpanded() }

      #expect(controller.isExpandedVisible)
      #expect(shown == [.alerts])
    }
  }
}
