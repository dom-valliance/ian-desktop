import SwiftUI

/// The Orbit's SwiftUI content: the avatar, its accessibility label, and the press action
/// VoiceOver uses (the mouse is handled by `OrbitHostView`).
struct OrbitRootView: View {
  let controller: SurfaceController
  @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

  var body: some View {
    let presentation = controller.presentation
    OrbitView(
      model: presentation.model,
      reducedMotion: controller.reducedMotionSetting || systemReducesMotion,
      isAnimating: controller.isOrbitOnScreen && !presentation.isSuppressed
    )
    .frame(width: OrbitPlacement.avatarSize, height: OrbitPlacement.avatarSize)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.accessibilityLabel)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { controller.toggleExpanded() }
  }
}

/// The top item's title beside the Orbit. It draws nothing while suppressed.
struct HoverLabelView: View {
  let controller: SurfaceController

  var body: some View {
    HStack {
      if controller.corner.isRight { Spacer(minLength: 0) }
      if let text = controller.presentation.hoverText {
        Text(text)
          .font(.system(size: 12))
          .foregroundStyle(Color.white)
          .lineLimit(1)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            Capsule().fill(OrbitPalette.chipFill.color)
              .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)))
      }
      if !controller.corner.isRight { Spacer(minLength: 0) }
    }
    .accessibilityHidden(true)
  }
}

/// The expanded client until D5 fills it: the panel's surface and nothing else, so no item text
/// can show through it.
struct ExpandedPlaceholderView: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 16)
      .fill(Color(.sRGB, red: 28 / 255, green: 27 / 255, blue: 27 / 255, opacity: 0.96))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
  }
}
