import AppKit
import Attention
import Client
import Store
import TestSupport
import Testing

@testable import Surface

@Suite("Window sharing")
@MainActor
struct WindowSharingTests {
  init() {
    _ = NSApplication.shared
  }

  private func makeController(
    defaults: UserDefaults, camera: FakeCamera = FakeCamera()
  ) -> SurfaceController {
    let store = IanStore(
      service: ScriptedService(), profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    return SurfaceController(
      store: store, signals: SuppressionSignals(camera: camera), defaults: defaults, quit: {})
  }

  private func withController(_ body: (SurfaceController) throws -> Void) rethrows {
    try withScratchDefaults { try body(makeController(defaults: $0)) }
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
    withController { controller in
      #expect(!controller.windows.isEmpty)
      for window in controller.windows {
        #expect(window.sharingType == .none)
      }
    }
  }

  @Test("hides every window of the app from screen capture once started")
  func everyAppWindowAfterStart() {
    withScratchDefaults { defaults in
      let camera = FakeCamera()
      let controller = makeController(defaults: defaults, camera: camera)
      let stray = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
        backing: .buffered, defer: true)
      stray.sharingType = .readOnly
      controller.start()
      controller.showExpanded()
      #expect(camera.started)
      #expect(stray.sharingType == .none)
      #expect(NSApp.windows.allSatisfy { $0.sharingType == .none })
      controller.stop()
      #expect(camera.stopped)
    }
  }

  @Test("hides a window that appears when a menu starts tracking")
  func sweepsOnMenuTracking() {
    withScratchDefaults { defaults in
      let controller = makeController(defaults: defaults)
      controller.start()
      let menuWindow = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
        backing: .buffered, defer: true)
      menuWindow.sharingType = .readWrite
      NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
      #expect(menuWindow.sharingType == .none)
      controller.stop()
    }
  }

  @Test("hides a window whose occlusion state changes")
  func sweepsOnOcclusionChange() {
    withScratchDefaults { defaults in
      let controller = makeController(defaults: defaults)
      controller.start()
      let shown = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
        backing: .buffered, defer: true)
      shown.sharingType = .readOnly
      NotificationCenter.default.post(
        name: NSWindow.didChangeOcclusionStateNotification, object: shown)
      #expect(shown.sharingType == .none)
      controller.stop()
    }
  }

  @Test("stops reacting to windows after stop")
  func stopRemovesObservers() {
    withScratchDefaults { defaults in
      let controller = makeController(defaults: defaults)
      controller.start()
      controller.stop()
      let late = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
        backing: .buffered, defer: true)
      late.sharingType = .readOnly
      NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
      #expect(late.sharingType == .readOnly)
    }
  }

  @Test("keeps sharing off once the windows are shown")
  func afterShowing() {
    withController { controller in
      controller.showExpanded()
      for window in controller.windows {
        #expect(window.sharingType == .none)
      }
      controller.hideExpanded()
    }
  }

  @Test("never lets the Orbit take key focus, and lets the expanded client")
  func keyability() {
    withController { controller in
      #expect(controller.windows[0].canBecomeKey == false)
      #expect(controller.windows[2].canBecomeKey == true)
    }
  }

  @Test("sizes the expanded client to 1,040 by 720 with a minimum of 880 by 600")
  func expandedSize() {
    let panel = WindowFactory.makeExpandedPanel(content: NSView())
    #expect(panel.frame.size == CGSize(width: 1040, height: 720))
    #expect(panel.minSize == CGSize(width: 880, height: 600))
  }

  @Test("lets the expanded client see pointer movement")
  func expandedAcceptsMouseMoved() {
    #expect(WindowFactory.makeExpandedPanel(content: NSView()).acceptsMouseMovedEvents)
  }

  @Test("floats the Orbit over every Space and full-screen apps, and keeps it in place")
  func orbitBehaviour() {
    for panel in [
      WindowFactory.makeOrbitPanel(content: NSView()),
      WindowFactory.makeHoverPanel(content: NSView(), size: CGSize(width: 100, height: 30)),
    ] {
      #expect(panel.level == .floating)
      #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
      #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
      #expect(panel.collectionBehavior.contains(.stationary))
      #expect(panel.styleMask.contains(.nonactivatingPanel))
      #expect(!panel.hasShadow)
    }
  }

  @Test("closes the expanded client on a synthetic Escape key press")
  func escapeCloses() throws {
    try withController { controller in
      controller.showExpanded()
      #expect(controller.isExpandedVisible)
      let panel = controller.windows[2]
      let escape = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: panel.windowNumber, context: nil, characters: "\u{1B}",
          charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
      panel.sendEvent(escape)
      #expect(!controller.isExpandedVisible)
    }
  }

  @Test("toggles the expanded client from a click")
  func toggles() {
    withController { controller in
      controller.toggleExpanded()
      #expect(controller.isExpandedVisible)
      controller.toggleExpanded()
      #expect(!controller.isExpandedVisible)
    }
  }

  @Test("checks Pause me after the menu command and suppresses")
  func pauseSuppresses() {
    withController { controller in
      #expect(!controller.suppression.isActive)
      controller.perform(.togglePause)
      #expect(controller.suppression.triggers == [.userPaused])
      controller.perform(.togglePause)
      #expect(!controller.suppression.isActive)
    }
  }

  @Test("builds the Orbit's menu from the same entries as the menu bar extra")
  func orbitMenuMatchesModel() {
    withController { controller in
      let menu = controller.makeMenu()
      let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
      let expected = controller.menuEntries.compactMap { entry -> String? in
        if case .command(_, let title, _, _) = entry { title } else { nil }
      }
      #expect(titles == expected)
    }
  }

  @Test("remembers the corner in the settings it was given")
  func cornerRead() {
    withScratchDefaults { defaults in
      CornerSetting(defaults: defaults).corner = .topLeft
      #expect(makeController(defaults: defaults).corner == .topLeft)
    }
  }
}
