import Store
import SwiftUI

/// The content of the menu bar extra: D3's temporary status lines (D5 removes them), then the
/// shared menu.
public struct MenuBarMenu: View {
  private let store: IanStore
  private let controller: SurfaceController

  public init(store: IanStore, controller: SurfaceController) {
    self.store = store
    self.controller = controller
  }

  public var body: some View {
    DebugStatus(store: store)
    Divider()
    ForEach(Array(controller.menuEntries.enumerated()), id: \.offset) { _, entry in
      switch entry {
      case .separator:
        Divider()
      case .command(let command, let title, let isChecked, let shortcut):
        if let isChecked {
          Toggle(
            title, isOn: Binding(get: { isChecked }, set: { _ in controller.perform(command) }))
        } else if let shortcut {
          Button(title) { controller.perform(command) }
            .keyboardShortcut(KeyEquivalent(shortcut))
        } else {
          Button(title) { controller.perform(command) }
        }
      }
    }
  }
}
