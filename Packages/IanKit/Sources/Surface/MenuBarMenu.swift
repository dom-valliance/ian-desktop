import SwiftUI

/// The content of the menu bar extra: the shared menu. The environment, the data's age and the
/// connection state are in the expanded client's header.
public struct MenuBarMenu: View {
  private let controller: SurfaceController

  public init(controller: SurfaceController) {
    self.controller = controller
  }

  public var body: some View {
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
