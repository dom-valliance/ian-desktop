import Testing

@testable import Attention

@Suite("The quiet line")
struct SuppressionLineTests {
  private func suppression(
    camera: Bool = false, meeting: Bool = false, quietHours: Bool = false, paused: Bool = false
  ) -> Suppression {
    Suppression(
      cameraLive: camera, externalMeeting: meeting, quietHours: quietHours, userPaused: paused)
  }

  @Test("says nothing while nothing suppresses")
  func none() {
    #expect(Suppression.none.quietLine == nil)
  }

  @Test("names each trigger alone")
  func each() {
    #expect(suppression(camera: true).quietLine == "Quiet while your camera is on")
    #expect(suppression(meeting: true).quietLine == "Quiet during an external meeting")
    #expect(suppression(quietHours: true).quietLine == "Quiet in your quiet hours")
    #expect(suppression(paused: true).quietLine == "Quiet while paused")
  }

  @Test("names two triggers in the order of the trigger list")
  func two() {
    #expect(
      suppression(camera: true, quietHours: true).quietLine
        == "Quiet while your camera is on and in your quiet hours")
    #expect(
      suppression(meeting: true, paused: true).quietLine
        == "Quiet during an external meeting and while paused")
  }

  @Test("names the first of three or more and says and more")
  func several() {
    #expect(
      suppression(camera: true, meeting: true, quietHours: true).quietLine
        == "Quiet while your camera is on and more")
    #expect(
      suppression(camera: true, meeting: true, quietHours: true, paused: true).quietLine
        == "Quiet while your camera is on and more")
    #expect(
      suppression(meeting: true, quietHours: true, paused: true).quietLine
        == "Quiet during an external meeting and more")
  }

  @Test("gives every trigger a reason")
  func everyTriggerHasAReason() {
    for trigger in Suppression.Trigger.allCases {
      #expect(!trigger.quietReason.isEmpty)
    }
  }
}

@MainActor
@Suite("The suppression change log")
struct SuppressionChangeLogTests {
  private func log() -> (SuppressionChangeLog, () -> [String]) {
    let box = LineBox()
    return (SuppressionChangeLog { box.lines.append($0) }, { box.lines })
  }

  private final class LineBox: @unchecked Sendable {
    var lines: [String] = []
  }

  @Test("logs nothing for a start with nothing suppressing")
  func quietStart() {
    let (log, lines) = log()
    log.record(.none)
    #expect(lines().isEmpty)
  }

  @Test("logs a change once, however often the same value is recorded")
  func onceOnChange() {
    let (log, lines) = log()
    let camera = Suppression(
      cameraLive: true, externalMeeting: false, quietHours: false, userPaused: false)
    for _ in 0..<5 { log.record(camera) }
    #expect(lines() == ["suppression on: cameraLive"])
  }

  @Test("logs the trigger names, then logs when suppression ends")
  func namesAndEnd() {
    let (log, lines) = log()
    log.record(
      Suppression(cameraLive: true, externalMeeting: false, quietHours: true, userPaused: false))
    log.record(.none)
    log.record(.none)
    #expect(lines() == ["suppression on: cameraLive, quietHours", "suppression off"])
  }
}
