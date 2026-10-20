/// The menu behind the menu bar extra and the Orbit's right-click, built once so the two cannot
/// differ (spec 6.1).
public enum AppMenu {
  public enum Command: Equatable, Sendable {
    case open, togglePause, openSettings, quit
  }

  public enum Entry: Equatable, Sendable {
    /// `isChecked` is nil for an entry that is not a toggle.
    case command(Command, title: String, isChecked: Bool?, shortcut: Character?)
    case separator
  }

  /// "Settings" opens the expanded client on its Settings view.
  public static func entries(isPaused: Bool) -> [Entry] {
    [
      .command(.open, title: "Open", isChecked: nil, shortcut: nil),
      .command(.togglePause, title: "Pause me", isChecked: isPaused, shortcut: nil),
      .command(.openSettings, title: "Settings", isChecked: nil, shortcut: ","),
      .separator,
      .command(.quit, title: "Quit Ian", isChecked: nil, shortcut: "q"),
    ]
  }

  /// "Ian", followed by the server's `nowCount` when it is above zero.
  public static func barTitle(nowCount: Int) -> String {
    nowCount > 0 ? "Ian \(nowCount)" : "Ian"
  }
}
