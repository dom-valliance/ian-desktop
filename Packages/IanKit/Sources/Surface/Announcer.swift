import AppKit

/// Speaks a line to VoiceOver. The line is item text, so callers post it only while nothing
/// suppresses item text.
@MainActor
enum Announcer {
  static func post(_ text: String) {
    NSAccessibility.post(
      element: NSApplication.shared, notification: .announcementRequested,
      userInfo: [
        .announcement: text,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
  }
}
