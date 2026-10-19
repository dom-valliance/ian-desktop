import AppKit
import Attention
import Features
import Store
import Surface
import SwiftUI

@main
struct IanApp: App {
  @State private var store: IanStore
  @State private var surface: SurfaceController

  init() {
    let store = IanStore.live(openURL: { url in
      await MainActor.run { _ = NSWorkspace.shared.open(url) }
    })
    let surface = SurfaceController(
      store: store, signals: SuppressionSignals(camera: CoreMediaCameraMonitor()))
    surface.setExpandedContent(
      ExpandedClientView(store: store, controller: surface, model: ClientModel()))
    _store = State(initialValue: store)
    _surface = State(initialValue: surface)
    // Read from the argument domain only, so it is never saved (scripts/measure-cpu.sh).
    let opensPanelOnLaunch =
      UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[
        "IanOpenPanelOnLaunch"] as? String == "YES"
    // Start once launching has finished, when the screens and the status bar exist.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil
    ) { _ in
      MainActor.assumeIsolated {
        store.start()
        surface.start()
        if opensPanelOnLaunch { surface.showExpandedAfterFirstSnapshot() }
      }
    }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu(controller: surface)
    } label: {
      Text(surface.menuBarTitle)
        .accessibilityLabel(surface.presentation.accessibilityLabel)
    }
  }
}
