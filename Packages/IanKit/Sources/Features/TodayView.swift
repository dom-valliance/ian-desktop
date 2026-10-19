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
  let onNavigate: (ClientSection) -> Void

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
      field
      Divider().overlay(ClientPalette.line)
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
        onNavigate: onNavigate)
    }
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

extension TodayView {
  /// The field in a fixed frame, scaled to fit its 540 by 420 box, so its per-frame redraws never
  /// re-lay out the lists or the footer. Its clock lives inside `PillarsFieldView` alone.
  @ViewBuilder fileprivate var field: some View {
    Group {
      if let scene = model.scene {
        PillarsFieldView(
          scene: scene.pillarsScene, isAnimating: isAnimating, reducedMotion: reducedMotion,
          onSelect: { key in
            if let today = store.state.today {
              model.selectPillar(key, in: today)
            }
          })
      } else {
        Color.clear
      }
    }
    .aspectRatio(PillarsRenderer.boxSize, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .frame(height: 300)
  }
}
