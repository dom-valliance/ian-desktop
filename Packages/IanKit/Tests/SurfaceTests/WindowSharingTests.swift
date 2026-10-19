import AppKit
import Attention
import Client
import Store
import TestSupport
import Testing

@testable import Surface

@MainActor
private final class StillCamera: CameraMonitoring {
  var isLive = false
  func start(onChange: @escaping @MainActor () -> Void) {}
  func stop() {}
}

@Suite("Window sharing")
@MainActor
struct WindowSharingTests {
  init() {
    _ = NSApplication.shared
  }

  private func controller(defaults: UserDefaults = UserDefaults(suiteName: "ian.tests.reads")!)
    -> SurfaceController
  {
    let store = IanStore(
      service: ScriptedService(), profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    return SurfaceController(
      store: store, signals: SuppressionSignals(camera: StillCamera()),
      defaults: defaults, quit: {})
  }

  @Test("hides every panel the factory makes from screen capture")
  func factoryPanels() {
    let panels = [
      WindowFactory.makeOrbitPanel(content: NSView()),
      WindowFactory.makeHoverPanel(content: NSView(), size: CGSize(width: 100, height: 30)),
      WindowFactory.makeExpandedPanel(content: NSView()),
    ]
    for panel in panels {
      #expect(panel.sharingType == .none)
    }
  }

  @Test("hides every window the controller owns from screen capture")
  func controllerWindows() {
    let controller = controller()
    #expect(!controller.windows.isEmpty)
    for window in controller.windows {
      #expect(window.sharingType == .none)
    }
  }

  @Test("keeps sharing off once the windows are shown")
  func afterShowing() {
    let controller = controller()
    controller.showExpanded()
    for window in controller.windows {
      #expect(window.sharingType == .none)
    }
    controller.hideExpanded()
  }

  @Test("never lets the Orbit take key focus, and lets the expanded client")
  func keyability() {
    let controller = controller()
    #expect(controller.windows[0].canBecomeKey == false)
    #expect(controller.windows[2].canBecomeKey == true)
  }

  @Test("sizes the expanded client to 1,040 by 720 with a minimum of 880 by 600")
  func expandedSize() {
    let panel = WindowFactory.makeExpandedPanel(content: NSView())
    #expect(panel.frame.size == CGSize(width: 1040, height: 720))
    #expect(panel.minSize == CGSize(width: 880, height: 600))
  }

  @Test("floats the Orbit over every Space and full-screen apps")
  func orbitBehaviour() {
    let panel = WindowFactory.makeOrbitPanel(content: NSView())
    #expect(panel.level == .floating)
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(!panel.hasShadow)
  }

  @Test("closes the expanded client on Escape")
  func escapeCloses() {
    let controller = controller()
    controller.showExpanded()
    #expect(controller.isExpandedVisible)
    controller.windows[2].cancelOperation(nil)
    #expect(!controller.isExpandedVisible)
  }

  @Test("toggles the expanded client from a click")
  func toggles() {
    let controller = controller()
    controller.toggleExpanded()
    #expect(controller.isExpandedVisible)
    controller.toggleExpanded()
    #expect(!controller.isExpandedVisible)
  }

  @Test("checks Pause me after the menu command and suppresses")
  func pauseSuppresses() {
    let controller = controller()
    #expect(!controller.suppression.isActive)
    controller.perform(.togglePause)
    #expect(controller.suppression.triggers == [.userPaused])
    controller.perform(.togglePause)
    #expect(!controller.suppression.isActive)
  }

  @Test("remembers the corner in the settings it was given")
  func cornerRead() {
    withScratchDefaults { defaults in
      CornerSetting(defaults: defaults).corner = .topLeft
      #expect(controller(defaults: defaults).corner == .topLeft)
    }
  }
}
