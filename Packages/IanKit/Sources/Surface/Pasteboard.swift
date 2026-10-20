import AppKit

/// The general pasteboard, for the diagnostics report. Features does not import AppKit.
public enum Pasteboard {
  public static func copy(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }
}
