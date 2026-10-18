import AppKit
import Store
import Surface
import SwiftUI

@main
struct IanApp: App {
  @State private var store: IanStore

  init() {
    let store = IanStore.live(openURL: { url in
      await MainActor.run { _ = NSWorkspace.shared.open(url) }
    })
    _store = State(initialValue: store)
    store.start()
  }

  var body: some Scene {
    MenuBarExtra("Ian") {
      MenuBarMenu(store: store)
    }
  }
}
