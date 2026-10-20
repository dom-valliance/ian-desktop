/// What the system sends back when the principal uses a notification.
public struct NotificationResponse: Equatable, Sendable {
  public enum Choice: Equatable, Sendable {
    /// The notification itself, or its Open button.
    case open
    /// One of the item's own actions, by the server's action id.
    case action(String)
  }

  public let itemID: String
  public let choice: Choice

  public init(itemID: String, choice: Choice) {
    self.itemID = itemID
    self.choice = choice
  }
}

/// The notification centre, so that nothing but the app creates the real one: it raises an
/// exception in a process with no bundle, which a test process is (ADR 0020).
public protocol NotificationDelivering: Sendable {
  /// Asks for permission to show alerts and play sounds. Nothing depends on the answer: the
  /// system drops what it may not show.
  func requestAuthorisation() async
  /// Replaces the categories the system knows.
  func setCategories(_ categories: [NotificationCategory]) async
  /// Delivers the notification, replacing one with the same id.
  func add(_ content: NotificationContent) async
  func withdraw(ids: [String]) async
  /// Removes every notification Ian delivered, including those of an earlier launch.
  func withdrawAll() async
  /// Sets who hears about taps and buttons. Called once, before the first notification.
  func setResponseHandler(_ handler: @escaping @MainActor @Sendable (NotificationResponse) -> Void)
}
