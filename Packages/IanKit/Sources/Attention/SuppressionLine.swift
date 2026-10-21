extension Suppression.Trigger {
  /// The reason as a phrase that follows "Quiet", for the panel header and the menu.
  public var quietReason: String {
    switch self {
    case .cameraLive: "while your camera is on"
    case .externalMeeting: "during an external meeting"
    case .quietHours: "in your quiet hours"
    case .userPaused: "while paused"
    }
  }
}

extension Suppression {
  /// The line that tells the principal why Ian is quiet, or nil when nothing suppresses. It names
  /// one or two triggers in the order of `Trigger.allCases`; three or more name the first and say
  /// "and more", which keeps the line to one short sentence. It never carries item content.
  public var quietLine: String? {
    guard let first = triggers.first else { return nil }
    switch triggers.count {
    case 1: return "Quiet \(first.quietReason)"
    case 2: return "Quiet \(first.quietReason) and \(triggers[1].quietReason)"
    default: return "Quiet \(first.quietReason) and more"
    }
  }
}
