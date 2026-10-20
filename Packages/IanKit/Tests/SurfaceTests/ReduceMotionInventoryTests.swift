import Foundation
import Testing

/// Every place Ian starts an animation by name, so a new one cannot arrive without someone
/// deciding what Reduce Motion does to it (spec 6.8, AGENTS.md rule 7). Each entry names the test
/// that proves its behaviour; the full table is in the D9 phase log entry.
@Suite("Reduce Motion inventory")
struct ReduceMotionInventoryTests {
  /// File name to the animation APIs it may use.
  private static let known: [String: Set<String>] = [
    // The panel's fade and rise: ExpandedEntranceTests. The Orbit's glide to a corner:
    // MotionPreferenceTests.
    "SurfaceController.swift": ["NSAnimationContext", "animator()", "animate:"],
    // The breath and the pulse: OrbitMotionTests (nothing runs under Reduce Motion).
    "OrbitMotion.swift": ["CABasicAnimation"],
    // A 15 second refresh of the data's age, which moves nothing on screen.
    "ExpandedClientView.swift": [".animation("],
  ]

  private static let tokens = [
    "withAnimation", ".animation(", ".transition(", "NSAnimationContext", "animator()",
    "CABasicAnimation", "CAKeyframeAnimation", "CASpringAnimation", "CATransition", "animate:",
    "symbolEffect", "contentTransition",
  ]

  private func sources() -> [URL] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources")
    return ["Surface", "Features"].flatMap { module in
      let folder = root.appendingPathComponent(module)
      let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
      return names.filter { $0.hasSuffix(".swift") }.map { folder.appendingPathComponent($0) }
    }
  }

  @Test("starts an animation only where Reduce Motion has been decided")
  func knownAnimations() throws {
    var found: [String: Set<String>] = [:]
    for url in sources() {
      let text = try String(contentsOf: url, encoding: .utf8)
      let used = Set(Self.tokens.filter { text.contains($0) })
      if !used.isEmpty { found[url.lastPathComponent] = used }
    }
    #expect(
      found == Self.known,
      "An animation was added or removed. Decide what Reduce Motion does to it, test that, then update this list."
    )
  }

  @Test("lets nothing animate a frame change without asking the motion preference")
  func noUnconditionalFrameAnimation() throws {
    for url in sources() {
      let text = try String(contentsOf: url, encoding: .utf8)
      #expect(!text.contains("animate: true"), "\(url.lastPathComponent) animates unconditionally")
    }
  }
}
