import AppKit
import Attention
import SwiftUI
import Testing

@testable import Surface

/// Each trigger driven through the controller: the store's context flags and a fake camera.
@Suite("Suppression on the surface")
@MainActor
struct SuppressionSurfaceTests {
  private enum Trigger: CaseIterable {
    case camera, externalMeeting, quietHours, userPause
  }

  private func controller(
    _ trigger: Trigger?, defaults: UserDefaults
  ) async -> (SurfaceController, store: IanStoreBox) {
    let camera = FakeCamera()
    camera.isLive = trigger == .camera
    let signals = SuppressionSignals(camera: camera)
    signals.start()
    signals.isPaused = trigger == .userPause
    let store = await loadedStore(
      OrbitScenario.load("normal"), externalMeeting: trigger == .externalMeeting,
      quietHours: trigger == .quietHours)
    return (
      SurfaceController(store: store, signals: signals, defaults: defaults, quit: {}),
      IanStoreBox(store)
    )
  }

  /// Whether a hosted view paints no visible pixel at all, so no text and no pill is drawn.
  private func isBlank(_ view: some View) -> Bool {
    let host = NSHostingView(rootView: view.frame(width: 320, height: 30))
    host.frame = CGRect(x: 0, y: 0, width: 320, height: 30)
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1) > 0 {
        return false
      }
    }
    return true
  }

  @Test("shows the top item's title in the hover when nothing suppresses")
  func hoverShownWhenClear() async {
    await withScratchDefaultsAsync { defaults in
      let (controller, box) = await controller(nil, defaults: defaults)
      defer { box.store.stop() }
      let scenario = OrbitScenario.load("normal")
      let top = scenario.items.first { $0.id == scenario.today.orbit.itemIds[0] }
      #expect(controller.presentation.hoverText == top?.title)
      #expect(!isBlank(HoverLabelView(controller: controller)))
    }
  }

  @Test("shows no hover text and draws no label for each trigger alone")
  func hoverHiddenForEachTrigger() async {
    for trigger in Trigger.allCases {
      await withScratchDefaultsAsync { defaults in
        let (controller, box) = await controller(trigger, defaults: defaults)
        defer { box.store.stop() }
        #expect(controller.suppression.isActive, "\(trigger)")
        #expect(controller.presentation.hoverText == nil, "\(trigger)")
        #expect(isBlank(HoverLabelView(controller: controller)), "blank \(trigger)")
      }
    }
  }

  @Test("keeps item text out of the status lines and the menu")
  func statusAndMenuCarryNoItemText() async {
    await withScratchDefaultsAsync { defaults in
      let (controller, box) = await controller(nil, defaults: defaults)
      defer { box.store.stop() }
      let scenario = OrbitScenario.load("normal")
      var strings = DebugStatus(store: box.store).lines
      strings.append(controller.menuBarTitle)
      for case .command(_, let title, _, _) in controller.menuEntries { strings.append(title) }
      #expect(!strings.isEmpty)
      for string in strings {
        for item in scenario.items {
          #expect(!string.contains(item.title))
          #expect(!string.contains(item.meta))
        }
      }
    }
  }
}
