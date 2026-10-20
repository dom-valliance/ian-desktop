import Store

extension NotificationRung: Comparable {
  private var rank: Int {
    switch self {
    case .ambient: 0
    case .needsYou: 1
    case .urgent: 2
    case .stop: 3
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

  /// The server's rung for an item (ADR 0009, Q17). The client maps it and decides nothing.
  public init(item: StoreState.Item) {
    switch item.attention {
    case .ambient: self = .ambient
    case .needsYou: self = .needsYou
    case .urgent: self = .urgent
    case .stop: self = .stop
    }
  }
}

/// What a rung does on the Orbit and in the notification centre (spec 6.6), and whether item text
/// may be shown while it does it.
public struct AttentionBehaviour: Equatable, Sendable {
  /// The strongest cue on the Orbit. Each rung keeps the cues of the rungs below it.
  public enum OrbitCue: Equatable, Sendable {
    /// State only, with no text.
    case stateOnly
    /// The Orbit grows and holds its colour. It draws this from the server's Orbit block.
    case growsAndHoldsColour
    /// A one-line whisper beside the Orbit for eight seconds.
    case whisper
    /// The expanded panel opens on the next pointer movement.
    case opensOnPointerMovement
  }

  public enum Notification: Equatable, Sendable {
    case none
    /// A banner with the item's own actions.
    case banner
    /// Delivered whatever the principal's levels say (P0).
    case always
  }

  public let orbit: OrbitCue
  public let notification: Notification
  /// False while suppressed: no item text on the Orbit, the whisper or a notification.
  public let showsItemText: Bool

  public init(orbit: OrbitCue, notification: Notification, showsItemText: Bool) {
    self.orbit = orbit
    self.notification = notification
    self.showsItemText = showsItemText
  }
}

/// The attention ladder of spec 6.6 as one pure function (ADR 0020). The rung is the server's;
/// nothing here computes one.
public enum AttentionLadder {
  /// - Parameters:
  ///   - level: The principal's level for the rung (ADR 0019). Stop ignores it.
  ///   - suppression: While active, no item text appears, only Stop notifies, nothing whispers and
  ///     Stop does not open the panel.
  public static func behaviour(
    of rung: NotificationRung, level: NotificationLevel, suppression: Suppression
  ) -> AttentionBehaviour {
    let suppressed = suppression.isActive
    let banner: AttentionBehaviour.Notification =
      level == .banner && !suppressed ? .banner : .none
    switch rung {
    case .ambient:
      return AttentionBehaviour(
        orbit: .stateOnly, notification: banner, showsItemText: !suppressed)
    case .needsYou:
      return AttentionBehaviour(
        orbit: .growsAndHoldsColour, notification: banner, showsItemText: !suppressed)
    case .urgent:
      return AttentionBehaviour(
        orbit: suppressed ? .growsAndHoldsColour : .whisper, notification: banner,
        showsItemText: !suppressed)
    case .stop:
      return AttentionBehaviour(
        orbit: suppressed ? .growsAndHoldsColour : .opensOnPointerMovement,
        notification: .always, showsItemText: !suppressed)
    }
  }
}
