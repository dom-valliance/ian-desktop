import AppKit
import Attention
import Client
import Store
import TestSupport
import Testing

@testable import Surface

/// The launch argument's route to the open panel (`scripts/measure-cpu.sh`).
@Suite("Opening the panel after the first snapshot")
@MainActor
struct OpenOnFirstSnapshotTests {
  init() {
    _ = NSApplication.shared
  }

  private func controller(
    service: ScriptedService, defaults: UserDefaults
  ) -> (SurfaceController, IanStore) {
    let store = IanStore(
      service: service, profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    let controller = SurfaceController(
      store: store, signals: SuppressionSignals(camera: FakeCamera()), defaults: defaults,
      quit: {})
    return (controller, store)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<300 where !condition() {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test("opens the panel at once when the first snapshot is already in")
  func opensAtOnceWhenLoaded() async {
    await withScratchDefaultsAsync { defaults in
      let store = await loadedStore(OrbitScenario.load("normal"))
      defer { store.stop() }
      let controller = SurfaceController(
        store: store, signals: SuppressionSignals(camera: FakeCamera()), defaults: defaults,
        quit: {})
      controller.showExpandedAfterFirstSnapshot()
      #expect(controller.isExpandedVisible)
      controller.hideExpanded()
    }
  }

  @Test("opens the panel once after the first snapshot and not on earlier state changes")
  func opensOnceAfterFirstSnapshot() async {
    await withScratchDefaultsAsync { defaults in
      let service = ScriptedService()
      let (gate, release) = AsyncStream<Void>.makeStream()
      service.planSnapshotHook { _ in for await _ in gate { break } }
      let (controller, store) = controller(service: service, defaults: defaults)
      defer { store.stop() }

      controller.showExpandedAfterFirstSnapshot()
      store.start()
      // `me` arrives before the snapshot, so the state changes while `today` is still nil.
      await waitUntil { store.state.me != nil }
      #expect(store.state.me != nil)
      try? await Task.sleep(for: .milliseconds(50))
      #expect(store.state.today == nil)
      #expect(!controller.isExpandedVisible)

      release.yield()
      await waitUntil { controller.isExpandedVisible }
      #expect(controller.isExpandedVisible)
      let openedAt = controller.expandedOpenedAt

      controller.hideExpanded()
      store.stop()
      try? await Task.sleep(for: .milliseconds(50))
      #expect(!controller.isExpandedVisible)
      #expect(controller.expandedOpenedAt == openedAt)
    }
  }
}
