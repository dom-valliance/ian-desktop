import Foundation
import Store
import Surface
import SwiftUI

/// Today: the field, then the Now list, This week and Later, then the selection footer. The
/// list is the accessible path; the field is never the only way to an item (spec 6.3).
struct TodayView: View {
  let store: IanStore
  let model: TodayModel
  /// When the expanded client last opened, for the pillars' rise.
  let openedAt: TimeInterval?
  let isAnimating: Bool
  let reducedMotion: Bool
  let layout: PaneLayout
  let onNavigate: (ClientSection) -> Void

  /// The pane's height, read from its geometry so only a change in height (not in width, as a
  /// sidebar drag makes) rebuilds this view. A plausible height until the first layout.
  @State private var containerHeight = 600.0

  /// What makes the scene stale: any applied event or snapshot, the selection, or a new opening.
  private struct SceneTrigger: Hashable {
    let lastEventID: UInt64?
    let lastUpdatedAt: Date?
    let selection: TodaySelection?
    let openedAt: TimeInterval?
  }

  private var trigger: SceneTrigger {
    SceneTrigger(
      lastEventID: store.state.lastEventID, lastUpdatedAt: store.lastUpdatedAt,
      selection: model.selection, openedAt: openedAt)
  }

  var body: some View {
    let selection = model.resolvedSelection(in: store)
    // Each rebuild redraws the rows, so a row leaving with its pillar goes when it is done.
    let _ = model.revision
    VStack(spacing: 0) {
      FieldPane(
        layout: layout, containerHeight: containerHeight, scene: model.scene,
        isAnimating: isAnimating, reducedMotion: reducedMotion,
        onSelect: { key in
          if let today = store.state.today {
            model.selectPillar(key, in: today)
          }
        })
      TodayListsView(
        list: TodayListModel(
          state: store.state, removals: store.removals, statuses: ItemStatuses(store: store),
          at: Date.now),
        hasToday: store.state.today != nil,
        selection: Binding(get: { selection }, set: { model.select($0) })
      )
      Divider().overlay(ClientPalette.line)
      SelectionFooter(
        store: store, selection: selection, onSelect: { model.select($0) },
        onNavigate: onNavigate, keys: model.footerKeys)
    }
    .background { FooterKeyCommands(keys: model.footerKeys) }
    .onChange(of: selection) { model.footerKeys.exit() }
    .onGeometryChange(for: Double.self, of: { $0.size.height }) { containerHeight = $0 }
    .task(id: trigger) { await keepSceneCurrent() }
  }

  /// Rebuilds the scene now, and again once a pillar that is sinking has finished, so a cell
  /// that left Today can go.
  private func keepSceneCurrent() async {
    var isSinking = model.refresh(
      store: store, openedAt: openedAt, now: Date().timeIntervalSinceReferenceDate)
    while isSinking && !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(750))
      isSinking = model.refresh(
        store: store, openedAt: openedAt, now: Date().timeIntervalSinceReferenceDate)
    }
  }
}

/// The field in the top pane, and the divider under it that resizes it. The field fills the
/// pane and scales its 540 by 420 box to fit, so its per-frame redraws never re-lay out the lists
/// or the footer. Its clock lives inside `PillarsFieldView` alone, and only this view reads the
/// pane's height, so a drag does not rebuild the rest of Today.
private struct FieldPane: View {
  let layout: PaneLayout
  let containerHeight: Double
  let scene: FieldSceneModel?
  let isAnimating: Bool
  let reducedMotion: Bool
  let onSelect: (PillarCellKey) -> Void

  var body: some View {
    let height = layout.fieldHeight(containerHeight: containerHeight)
    Group {
      if let scene {
        PillarsFieldView(
          scene: scene.pillarsScene, isAnimating: isAnimating, reducedMotion: reducedMotion,
          angle: layout.angle, onTurn: { layout.commitAngle($0) }, onSelect: onSelect)
      } else {
        Color.clear
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    PaneDivider(
      direction: .horizontal, colour: ClientPalette.line, value: { height },
      onChange: { layout.resizeField(to: $0, containerHeight: containerHeight) },
      onEnd: { layout.commitPanes() })
  }
}

/// Binds Return, Left, Right and Escape to `FooterKeys`. They are key equivalents, so they reach
/// the window whatever has focus and with Keyboard navigation off. Return is claimed only while a
/// target exists and no prompt is open, and the arrows and Escape only inside the mode, so a text
/// field, a prompt or the panel's own Escape keeps its key the rest of the time. The buttons draw
/// nothing and VoiceOver skips them: the footer's own buttons are its accessible controls.
private struct FooterKeyCommands: View {
  let keys: FooterKeys

  var body: some View {
    Group {
      if keys.handlesReturn {
        key("Act on the footer", .return) { keys.pressReturn() }
      }
      if keys.isActive {
        key("Previous target", .leftArrow) { keys.move(-1) }
        key("Next target", .rightArrow) { keys.move(1) }
        key("Back to the list", .escape) { keys.pressEscape() }
      }
    }
  }

  private func key(_ title: String, _ equivalent: KeyEquivalent, _ action: @escaping () -> Void)
    -> some View
  {
    Button(title, action: action)
      .keyboardShortcut(equivalent, modifiers: [])
      .opacity(0)
      .frame(width: 0, height: 0)
      .focusable(false)
      .accessibilityHidden(true)
  }
}
