import SwiftUI

/// The Orbit's SwiftUI content: the avatar, its accessibility label, and the press action
/// VoiceOver uses (the mouse is handled by `OrbitHostView`).
struct OrbitRootView: View {
  // Weak, so the controller, its panels and their views do not keep each other alive.
  private weak var controller: SurfaceController?
  @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

  init(controller: SurfaceController) {
    self.controller = controller
  }

  var body: some View {
    if let controller {
      avatar(of: controller)
    }
  }

  @ViewBuilder private func avatar(of controller: SurfaceController) -> some View {
    let presentation = controller.presentation
    OrbitView(
      model: presentation.model,
      reducedMotion: controller.reducedMotionSetting || systemReducesMotion,
      isAnimating: controller.isOrbitAnimating
    )
    .frame(width: OrbitPlacement.avatarSize, height: OrbitPlacement.avatarSize)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.accessibilityLabel)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { controller.toggleExpanded() }
  }
}

/// The top item's title, or the urgent item's whisper, beside the Orbit. It draws nothing while
/// suppressed.
struct HoverLabelView: View {
  private weak var controller: SurfaceController?

  init(controller: SurfaceController) {
    self.controller = controller
  }

  var body: some View {
    if let controller {
      label(of: controller)
    }
  }

  @ViewBuilder private func label(of controller: SurfaceController) -> some View {
    HStack {
      if controller.corner.isRight { Spacer(minLength: 0) }
      if let text = controller.hoverLabel {
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

/// The expanded client's surface: the rounded, translucent panel every view sits on. Until the
/// app gives the panel content it is empty, so no item text can show through it.
struct ExpandedPanelSurface<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .background(Color(.sRGB, red: 28 / 255, green: 27 / 255, blue: 27 / 255, opacity: 0.96))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
  }
}
