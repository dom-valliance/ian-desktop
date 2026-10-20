import SwiftUI

/// The one prompt a window may have open. Every card holds its own note, time or hand-off
/// prompt, and Return and Escape reach every one a window shows, so opening a prompt closes the
/// one already open: Return then acts on the prompt in front of the principal and no other.
@MainActor
final class PromptOwner {
  private var open: (key: String, close: () -> Void)?

  /// The key of the prompt that is open, if any.
  var openKey: String? { open?.key }

  /// A prompt opened. The one open before it, if it is another, is closed first.
  func opened(_ key: String, close: @escaping () -> Void) {
    if let open, open.key != key { open.close() }
    open = (key, close)
  }

  /// A prompt closed on its own. A prompt that was already displaced changes nothing.
  func closed(_ key: String) {
    if open?.key == key { open = nil }
  }
}

extension EnvironmentValues {
  /// Set by the expanded client. Without one, as in a lone card, prompts do not displace each
  /// other.
  @Entry var promptOwner: PromptOwner?
}
