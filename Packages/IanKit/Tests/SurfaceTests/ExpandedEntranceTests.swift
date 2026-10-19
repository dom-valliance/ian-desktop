import CoreGraphics
import Testing

@testable import Surface

@Suite("Expanded client entrance")
struct ExpandedEntranceTests {
  private let end = CGRect(x: 100, y: 200, width: 1040, height: 720)

  @Test("starts 14 points below its resting place and rises when motion is on")
  func rises() {
    let entrance = ExpandedEntrance(endFrame: end, reducedMotion: false)
    #expect(entrance.startFrame == end.offsetBy(dx: 0, dy: -14))
    #expect(entrance.endFrame == end)
    #expect(entrance.rises)
  }

  @Test("only fades under Reduce Motion, starting where it rests")
  func fadesOnly() {
    let entrance = ExpandedEntrance(endFrame: end, reducedMotion: true)
    #expect(entrance.startFrame == end)
    #expect(!entrance.rises)
  }

  @Test("fades over 0.3 seconds and rises over 0.35")
  func durations() {
    #expect(ExpandedEntrance.fadeDuration == 0.3)
    #expect(ExpandedEntrance.riseDuration == 0.35)
  }
}
