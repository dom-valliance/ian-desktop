import AppKit
import SwiftUI

/// The Pillars field: the drawing, driven by a display link that runs only while something moves.
///
/// The link stops when the field is hidden, occluded or suppressed (`isAnimating` false). The
/// yaw sways for as long as the field is visible, so under motion the link runs at 60 frames a
/// second (spec 6.9). Under Reduce Motion it runs only through a growth or a sink, which are then
/// fades. A stopped field is drawn in its still pose.
///
/// Dragging sideways turns the field about its vertical axis, a click selects a pillar and a
/// double-click returns the field to 45 degrees (`FieldPointer`). The turn is the drawing view's
/// own state, so a drag redraws the field alone. `angle` is where the field starts.
///
/// The field is not the accessible path (non-negotiable 8): every pillar is also a row in the
/// lists below it, so VoiceOver meets one label and none of the internals.
public struct PillarsFieldView: View {
  private let scene: PillarsScene
  private let isAnimating: Bool
  private let reducedMotion: Bool
  private let angle: Double
  private let onSelect: (PillarCellKey) -> Void
  private let onTurn: (Double) -> Void

  public init(
    scene: PillarsScene, isAnimating: Bool, reducedMotion: Bool,
    angle: Double = FieldTurn.defaultAngle, onTurn: @escaping (Double) -> Void = { _ in },
    onSelect: @escaping (PillarCellKey) -> Void
  ) {
    self.scene = scene
    self.isAnimating = isAnimating
    self.reducedMotion = reducedMotion
    self.angle = angle
    self.onSelect = onSelect
    self.onTurn = onTurn
  }

  public var body: some View {
    PillarsFieldRepresentable(
      scene: scene, isAnimating: isAnimating, reducedMotion: reducedMotion, angle: angle,
      onTurn: onTurn, onSelect: onSelect
    )
    .accessibilityHidden(true)
    // The field only describes itself. Taking the mouse in the drawing view means VoiceOver's
    // activation cannot select or clear a pillar, so the labelled element is a separate one with
    // no action.
    .overlay {
      Color.clear
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pillars field. Each pillar is also a row in the lists below.")
    }
  }

  /// The time to draw at. A field whose clock is stopped, hidden or suppressed, draws its
  /// finished pose: a clock frozen before `openedAt` would otherwise draw every pillar unrisen.
  static func drawTime(scene: PillarsScene, isAnimating: Bool, clock: Double) -> Double {
    isAnimating ? clock : max(clock, scene.transitionEnd)
  }
}

private struct PillarsFieldRepresentable: NSViewRepresentable {
  let scene: PillarsScene
  let isAnimating: Bool
  let reducedMotion: Bool
  let angle: Double
  let onTurn: (Double) -> Void
  let onSelect: (PillarCellKey) -> Void

  func makeNSView(context: Context) -> PillarsFieldNSView {
    PillarsFieldNSView(
      scene: scene, isAnimating: isAnimating, reducedMotion: reducedMotion, angle: angle,
      onTurn: onTurn, onSelect: onSelect)
  }

  func updateNSView(_ view: PillarsFieldNSView, context: Context) {
    view.onTurn = onTurn
    view.onSelect = onSelect
    view.reducedMotion = reducedMotion
    view.isAnimating = isAnimating
    view.scene = scene
  }
}

extension PillarsScene {
  /// When the last growth or sink finishes.
  var transitionEnd: TimeInterval {
    let grow = openedAt.map { $0 + PillarsRenderer.longestGrow } ?? 0
    let sink = (sinking.values.max() ?? 0) + PillarsRenderer.sinkDuration
    return max(grow, sink)
  }
}
