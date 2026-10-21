import Foundation
import Testing

/// Every place Ian starts motion by name, with how many times, so a new one cannot arrive
/// without someone deciding what Reduce Motion does to it (spec 6.8, AGENTS.md rule 7).
///
/// It reads the code of `Surface` and `Features`, subfolders included, with comments removed,
/// and counts each animation API per file. It catches a new use of a listed API, in a new file or
/// a second use in a known one. It does not catch motion made another way, such as a timer that
/// changes a value, a third-party library, an animation a system control draws by itself, or an
/// API missing from the list below. The list is the place to add one when a new kind of motion
/// is needed. Each entry's Reduce Motion behaviour is proved by the test named beside it, and the
/// full table is in the phase log's D9 entry once that exists.
@Suite("Reduce Motion inventory")
struct ReduceMotionInventoryTests {
  /// File name to the animation APIs it uses and how many times each appears.
  private static let known: [String: [String: Int]] = [
    // The panel's fade and rise: ExpandedEntranceTests. The Orbit's glide to a corner:
    // MotionPreferenceTests.
    "SurfaceController.swift": ["NSAnimationContext": 2, "animator()": 2, "animate:": 1],
    // The breath and the pulse: OrbitMotionTests (nothing runs under Reduce Motion).
    "OrbitMotion.swift": ["CABasicAnimation": 4],
    // The field's clock, which pauses under Reduce Motion: PillarsFieldViewTests.
    "PillarsFieldNSView.swift": ["CADisplayLink": 1, "displayLink(": 1],
    // A 15 second refresh of the data's age, which moves nothing on screen.
    "ExpandedClientView.swift": ["TimelineView": 1, ".animation(": 1],
  ]

  private static let tokens = [
    "withAnimation", ".animation(", ".transition(", "NSAnimationContext", "animator()",
    "CABasicAnimation", "CAKeyframeAnimation", "CASpringAnimation", "CATransition", "animate:",
    "CADisplayLink", "displayLink(", "TimelineView", "phaseAnimator", "keyframeAnimator",
    "withTransaction", "Transaction(", "matchedGeometryEffect", "symbolEffect", "contentTransition",
  ]

  private static var sourceRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources")
  }

  private func sources() -> [URL] {
    let root = Self.sourceRoot
    return ["Surface", "Features"].flatMap { module -> [URL] in
      let folder = root.appendingPathComponent(module)
      let paths = FileManager.default.enumerator(atPath: folder.path)?.allObjects as? [String] ?? []
      return paths.filter { $0.hasSuffix(".swift") }.map { folder.appendingPathComponent($0) }
    }
  }

  /// The text with `//` comments, which include `///`, and `/* */` comments removed. A string
  /// holding `//` loses its tail, which only hides text after it on that line.
  static func withoutComments(_ text: String) -> String {
    var result = text.replacingOccurrences(
      of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
    result = result.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
    return result
  }

  private static func count(of token: String, in text: String) -> Int {
    text.components(separatedBy: token).count - 1
  }

  @Test("starts motion only where Reduce Motion has been decided")
  func knownAnimations() throws {
    var found: [String: [String: Int]] = [:]
    for url in sources() {
      let text = Self.withoutComments(try String(contentsOf: url, encoding: .utf8))
      var counts: [String: Int] = [:]
      for token in Self.tokens {
        let number = Self.count(of: token, in: text)
        if number > 0 { counts[token] = number }
      }
      if !counts.isEmpty {
        found[url.lastPathComponent, default: [:]].merge(counts, uniquingKeysWith: +)
      }
    }
    #expect(
      found == Self.known,
      "Motion was added or removed. Decide what Reduce Motion does to it, test that, then update this list."
    )
  }

  @Test("lets nothing animate a frame change without asking the motion preference")
  func noUnconditionalFrameAnimation() throws {
    for url in sources() {
      let text = Self.withoutComments(try String(contentsOf: url, encoding: .utf8))
      #expect(!text.contains("animate: true"), "\(url.lastPathComponent) animates unconditionally")
    }
  }

  @Test("ignores a token that only a comment mentions")
  func commentsAreStripped() {
    let text = "// withAnimation here\n/// animator()\nlet a = 1 /* CABasicAnimation */\nlet b = 2"
    let stripped = Self.withoutComments(text)
    #expect(Self.tokens.allSatisfy { !stripped.contains($0) })
    #expect(stripped.contains("let b = 2"))
  }

  @Test("counts a second use of a token in a file")
  func countsRepeats() {
    #expect(Self.count(of: "animator()", in: "a.animator() b.animator()") == 2)
  }
}
