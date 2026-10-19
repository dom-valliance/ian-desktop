import Contract
import Store
import Surface
import SwiftUI

/// The expanded client: a header, the sidebar of seven views and the selected view (spec 6.2).
/// The app passes it to `SurfaceController.setExpandedContent`.
public struct ExpandedClientView: View {
  private let store: IanStore
  // Weak, so the controller, its panel and this view do not keep each other alive.
  private weak var controller: SurfaceController?
  private let model: ClientModel
  @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

  public init(store: IanStore, controller: SurfaceController, model: ClientModel) {
    self.store = store
    self.controller = controller
    self.model = model
    controller.onOpenSettings = { [weak model] in model?.section = .settings }
  }

  public var body: some View {
    VStack(spacing: 0) {
      ClientHeader(
        store: store, isTicking: controller?.isExpandedOnScreen ?? false,
        close: { controller?.hideExpanded() })
      Divider().overlay(ClientPalette.line)
      GeometryReader { geometry in
        HStack(spacing: 0) {
          SidebarPane(
            layout: model.layout, containerWidth: geometry.size.width,
            counts: store.state.views?.counts,
            selection: Binding(get: { model.section }, set: { model.section = $0 }))
          content
        }
      }
    }
    .foregroundStyle(ClientPalette.text)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder private var content: some View {
    switch model.section {
    case .today:
      TodayView(
        store: store, model: model.today, openedAt: controller?.expandedOpenedAt,
        isAnimating: controller?.isExpandedAnimating ?? false,
        reducedMotion: (controller?.reducedMotionSetting ?? false) || systemReducesMotion,
        layout: model.layout, onNavigate: { model.section = $0 })
    case .proposals, .commitments, .tasks, .alerts, .agents, .settings:
      Text(model.section.title)
        .font(.system(size: 18, weight: .medium))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

/// The sidebar and the divider that resizes it. Only this view reads the width, so a drag does
/// not rebuild the selected view.
private struct SidebarPane: View {
  let layout: PaneLayout
  let containerWidth: Double
  let counts: Components.Schemas.ViewCounts?
  @Binding var selection: ClientSection

  var body: some View {
    let width = layout.sidebarWidth(containerWidth: containerWidth)
    HStack(spacing: 0) {
      SidebarView(counts: counts, width: width, selection: $selection)
      PaneDivider(
        direction: .vertical, colour: ClientPalette.line, value: { width },
        onChange: { layout.resizeSidebar(to: $0, containerWidth: containerWidth) },
        onEnd: { layout.commitPanes() })
    }
  }
}

/// "Ian", the environment when it is not `mock`, the data's age when the connection is not live,
/// and the banner for offline, sign-in and upgrade states (spec 6.2 and 6.7).
private struct ClientHeader: View {
  let store: IanStore
  /// The age text changes with time, so it refreshes only while the panel is on screen.
  let isTicking: Bool
  let close: () -> Void

  var body: some View {
    TimelineView(.animation(minimumInterval: 15, paused: !isTicking)) { timeline in
      let status = ClientStatus(
        environmentName: store.profile.isMock ? nil : store.profile.displayName,
        phase: store.phase, connection: store.connection, lastUpdatedAt: store.lastUpdatedAt,
        isSigningIn: store.isSigningIn, now: timeline.date)
      VStack(spacing: 0) {
        HStack(spacing: 16) {
          Text("Ian")
            .font(.system(size: 18, weight: .medium))
          Spacer()
          if let environment = status.environment {
            Text(environment.uppercased())
              .font(ClientPalette.label)
              .tracking(ClientPalette.labelTracking)
              .foregroundStyle(ClientPalette.secondary(0.7))
          }
          if let age = status.dataAge {
            Text(age)
              .font(.system(size: 13))
              .foregroundStyle(ClientPalette.secondary())
          }
          Button("Close", action: close)
            .buttonStyle(ActionButtonStyle(style: .secondary))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        if let banner = status.banner {
          BannerView(banner: banner, signIn: { Task { await store.signIn() } })
        }
      }
    }
  }
}

private struct BannerView: View {
  let banner: ClientStatus.Banner
  let signIn: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(banner.message)
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
      if case .signInRequired(_, let isSigningIn) = banner, !isSigningIn {
        Button("Sign in", action: signIn)
          .buttonStyle(ActionButtonStyle(style: .primary))
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
    .background(Color.white.opacity(0.06))
  }
}
