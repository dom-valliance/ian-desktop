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
    VStack(spacing: 0) {
      FieldPlaceholder()
        .frame(height: 300)
      Divider().overlay(ClientPalette.line)
      ScrollView {
        TodayListsView(
          list: TodayListModel(
            state: store.state, removals: store.removals, statuses: ItemStatuses(store: store)),
          selection: selection, onSelect: { model.select($0) }, onNavigate: onNavigate
        )
        .padding(.horizontal, 8)
      }
      Divider().overlay(ClientPalette.line)
      SelectionFooter(store: store, selection: selection, onSelect: { model.select($0) })
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

/// Stands where the Pillars field goes until it is wired in. It draws no item text.
private struct FieldPlaceholder: View {
  var body: some View {
    Color.clear
      .accessibilityHidden(true)
  }
}
