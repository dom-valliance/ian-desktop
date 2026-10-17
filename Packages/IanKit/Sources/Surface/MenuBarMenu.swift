import AppKit
import SwiftUI

/// The version 0 placeholder for the menu bar extra's content. D4 replaces it with Open, Pause me,
/// Settings and Quit.
public struct MenuBarMenu: View {
  public init() {}

  public var body: some View {
    Button("Quit Ian") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
