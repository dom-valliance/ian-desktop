import AppKit
import Attention
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
    _store = State(initialValue: store)
    _surface = State(initialValue: surface)
    store.start()
    surface.start()
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarMenu(store: store, controller: surface)
    } label: {
      Text(surface.menuBarTitle)
    }
  }
}
