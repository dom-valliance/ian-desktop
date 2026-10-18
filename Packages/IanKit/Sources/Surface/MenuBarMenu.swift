import AppKit
import Store
import SwiftUI

/// The version 0 placeholder for the menu bar extra's content. D3 adds the status readout; D4
/// replaces the whole menu with Open, Pause me, Settings and Quit.
public struct MenuBarMenu: View {
  private let store: IanStore

  public init(store: IanStore) {
    self.store = store
  }

  public var body: some View {
    DebugStatus(store: store)
    Divider()
    Button("Quit Ian") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
