/// The four rungs of the attention ladder (spec 6.6), named for the notification settings.
public enum NotificationRung: String, CaseIterable, Sendable {
  case ambient, needsYou, urgent, stop
}

/// How a rung notifies. Spec 6.6 gives Urgent a banner and the lower rungs none, so the levels
/// are Off and Banner; Stop always notifies and has no level to choose.
public enum NotificationLevel: String, CaseIterable, Sendable {
  case off, banner
}

extension NotificationRung {
  /// What spec 6.6 says before the principal changes anything.
  public var defaultLevel: NotificationLevel {
    switch self {
    case .ambient, .needsYou: .off
    case .urgent, .stop: .banner
    }
  }

  /// False for Stop, which always notifies (spec 6.6).
  public var isConfigurable: Bool { self != .stop }

  /// The `UserDefaults` key D8 reads, or nil for Stop, which is never saved.
  public var defaultsKey: String? {
    switch self {
    case .ambient: "IanNotificationLevelAmbient"
    case .needsYou: "IanNotificationLevelNeedsYou"
    case .urgent: "IanNotificationLevelUrgent"
    case .stop: nil
    }
  }
}
