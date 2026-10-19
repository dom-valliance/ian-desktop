import CoreGraphics

/// How the expanded client appears (design README, Panel entrance): opacity eases in over 0.3
/// seconds and the panel rises 14 points over 0.35 seconds. Reduce Motion keeps the fade and drops
/// the rise. Pure, so it is tested without a window.
struct ExpandedEntrance: Equatable {
  static let fadeDuration = 0.3
  static let riseDuration = 0.35
  static let riseDistance: CGFloat = 14

  /// Where the panel starts. AppKit's y grows upward, so it starts below its resting place.
  let startFrame: CGRect
  let endFrame: CGRect
  let rises: Bool

  init(endFrame: CGRect, reducedMotion: Bool) {
    self.endFrame = endFrame
    rises = !reducedMotion
    startFrame = reducedMotion ? endFrame : endFrame.offsetBy(dx: 0, dy: -Self.riseDistance)
  }
}
