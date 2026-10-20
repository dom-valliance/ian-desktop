import Testing

@testable import Attention

private let quiet = Suppression.none
private let paused = Suppression(
  cameraLive: false, externalMeeting: false, quietHours: false, userPaused: true)

@Suite("The attention ladder")
struct AttentionLadderTests {
  @Test("ambient shows state only and notifies only at the Banner level")
  func ambient() {
    let off = AttentionLadder.behaviour(of: .ambient, level: .off, suppression: quiet)
    #expect(off == AttentionBehaviour(orbit: .stateOnly, notification: .none, showsItemText: true))
    let banner = AttentionLadder.behaviour(of: .ambient, level: .banner, suppression: quiet)
    #expect(banner.orbit == .stateOnly)
    #expect(banner.notification == .banner)
  }

  @Test("needs you grows and holds colour, and notifies only at the Banner level")
  func needsYou() {
    let off = AttentionLadder.behaviour(of: .needsYou, level: .off, suppression: quiet)
    #expect(
      off
        == AttentionBehaviour(
          orbit: .growsAndHoldsColour, notification: .none, showsItemText: true))
    let banner = AttentionLadder.behaviour(of: .needsYou, level: .banner, suppression: quiet)
    #expect(banner.orbit == .growsAndHoldsColour)
    #expect(banner.notification == .banner)
  }

  @Test("urgent whispers whatever its level, and shows a banner at the Banner level")
  func urgent() {
    let banner = AttentionLadder.behaviour(of: .urgent, level: .banner, suppression: quiet)
    #expect(
      banner == AttentionBehaviour(orbit: .whisper, notification: .banner, showsItemText: true))
    let off = AttentionLadder.behaviour(of: .urgent, level: .off, suppression: quiet)
    #expect(off.orbit == .whisper)
    #expect(off.notification == .none)
  }

  @Test("stop opens the panel on the next pointer movement and always notifies")
  func stop() {
    for level in NotificationLevel.allCases {
      let behaviour = AttentionLadder.behaviour(of: .stop, level: level, suppression: quiet)
      #expect(
        behaviour
          == AttentionBehaviour(
            orbit: .opensOnPointerMovement, notification: .always, showsItemText: true))
    }
  }

  @Test("while suppressed no rung shows item text")
  func suppressedHidesText() {
    for rung in NotificationRung.allCases {
      for level in NotificationLevel.allCases {
        let behaviour = AttentionLadder.behaviour(of: rung, level: level, suppression: paused)
        #expect(!behaviour.showsItemText)
      }
    }
  }

  @Test("while suppressed only stop notifies, and nothing whispers or opens the panel")
  func suppressedHoldsBack() {
    for rung in NotificationRung.allCases {
      for level in NotificationLevel.allCases {
        let behaviour = AttentionLadder.behaviour(of: rung, level: level, suppression: paused)
        #expect(behaviour.notification == (rung == .stop ? .always : .none))
        #expect(behaviour.orbit != .whisper)
        #expect(behaviour.orbit != .opensOnPointerMovement)
      }
    }
  }

  @Test("every trigger suppresses the same way")
  func everyTrigger() {
    let triggers = [
      Suppression(cameraLive: true, externalMeeting: false, quietHours: false, userPaused: false),
      Suppression(cameraLive: false, externalMeeting: true, quietHours: false, userPaused: false),
      Suppression(cameraLive: false, externalMeeting: false, quietHours: true, userPaused: false),
    ]
    for suppression in triggers {
      let urgent = AttentionLadder.behaviour(of: .urgent, level: .banner, suppression: suppression)
      #expect(urgent.notification == .none)
      #expect(!urgent.showsItemText)
    }
  }

  @Test("the rungs are ordered from ambient to stop")
  func ordering() {
    #expect(NotificationRung.ambient < .needsYou)
    #expect(NotificationRung.needsYou < .urgent)
    #expect(NotificationRung.urgent < .stop)
  }
}
