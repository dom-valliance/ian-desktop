import Store

/// The view of the expanded client that holds an item (spec 6.2), which a notification opens.
/// Attention names it so that Surface and Features can agree on it without importing each other.
public enum ItemDestination: String, Equatable, Sendable {
  case today, proposals, commitments, tasks, alerts

  public init(item: StoreState.Item) {
    switch item.kind {
    case .proposal: self = .proposals
    case .commitmentBy, .commitmentTo: self = .commitments
    case .task: self = .tasks
    case .alert: self = .alerts
    }
  }
}

/// One button on a notification. The identifier is what the system sends back.
public struct NotificationButton: Equatable, Sendable {
  public static let openIdentifier = "ian.open"
  static let actionPrefix = "ian.action."

  public let identifier: String
  public let title: String

  /// The item's own action, with its id and label as the server sent them.
  init(actionID: String, label: String) {
    identifier = Self.actionPrefix + actionID
    title = label
  }

  static let open = NotificationButton(identifier: openIdentifier, title: "Open")

  private init(identifier: String, title: String) {
    self.identifier = identifier
    self.title = title
  }

  /// The server's action id behind a button identifier, or nil for Open and the default tap.
  public static func actionID(forIdentifier identifier: String) -> String? {
    identifier.hasPrefix(actionPrefix) ? String(identifier.dropFirst(actionPrefix.count)) : nil
  }
}

/// A set of buttons the system registers under an id.
public struct NotificationCategory: Equatable, Sendable {
  public let id: String
  public let buttons: [NotificationButton]

  /// The ids of the item's actions a notification button may run: those with no `confirm` and no
  /// `input`, in the order sent. The others are reached through Open, where the expanded client
  /// asks for what they need.
  public static func quickActionIDs(of item: StoreState.Item) -> [String] {
    item.actions.filter { $0.confirm == nil && $0.input == .none }.map(\.id)
  }

  /// One category per notification, named for the item's id (not item text), because two items
  /// can share an action id and show different labels. While suppressed there is only Open, under
  /// one shared id, so no action label (item text) reaches the screen.
  public init(item: StoreState.Item, showsItemText: Bool) {
    guard showsItemText else {
      id = "ian.item.open"
      buttons = [.open]
      return
    }
    let quick = Set(Self.quickActionIDs(of: item))
    id = "ian.item." + item.id
    buttons =
      item.actions.filter { quick.contains($0.id) }.map {
        NotificationButton(actionID: $0.id, label: $0.label)
      } + [.open]
  }
}

/// A notification ready for the system. It is built from the item and holds the item's text only
/// when `showsItemText` is true.
public struct NotificationContent: Equatable, Sendable {
  /// What a suppressed notification says. It names no item.
  public static let suppressedTitle = "Ian"
  public static let suppressedBody = "Something needs you now."

  /// The item's id, so a newer notification for the item replaces the one before it.
  public let id: String
  public let title: String
  public let body: String
  public let category: NotificationCategory
  /// Stop plays the default sound; the other rungs are silent.
  public let playsSound: Bool

  public init(item: StoreState.Item, rung: NotificationRung, showsItemText: Bool) {
    id = item.id
    title = showsItemText ? item.title : Self.suppressedTitle
    body = showsItemText ? item.meta : Self.suppressedBody
    category = NotificationCategory(item: item, showsItemText: showsItemText)
    playsSound = rung == .stop
  }
}
