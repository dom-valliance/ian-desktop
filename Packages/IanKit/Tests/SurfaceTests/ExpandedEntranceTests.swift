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

  @Test("gives each kind the colour the design names, once for every surface")
  func kindPalette() {
    #expect(KindPalette.colour(for: .proposal) == OrbitColour(240, 185, 226))
    #expect(KindPalette.colour(for: .task) == OrbitColour(0x7F, 0xBF, 0xC1))
    #expect(OrbitPalette.colour(for: .alert) == KindPalette.colour(for: .alert))
  }
}
