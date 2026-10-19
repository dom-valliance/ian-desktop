import Contract
import Foundation
import Observation
import Store
import Surface

/// The Today view's own state: what the list has selected, and the field's scene. The scene is
/// rebuilt when the store, the selection or the opening time changes, so a pillar can keep
/// sinking after the server's update has dropped it.
@MainActor
@Observable
final class TodayModel {
  /// What the principal selected. It may name an item that has since gone; `resolvedSelection`
  /// says whether it still stands.
  private(set) var selection: TodaySelection?
  private(set) var scene: FieldSceneModel?
  @ObservationIgnored private var memory = FieldMemory()

  init() {}

  func select(_ selection: TodaySelection?) {
    self.selection = selection
  }

  /// A pillar was chosen in the field: select its row.
  func selectPillar(_ pillar: FieldCellRef, in today: Components.Schemas.Today) {
    selection = TodaySelectionModel.selection(forPillar: pillar, in: today)
  }

  /// The field reported a tap on a pillar: select its row.
  func selectPillar(_ key: PillarCellKey, in today: Components.Schemas.Today) {
    selectPillar(FieldCellRef(key), in: today)
  }

  /// The selection, unless it names an item the store no longer holds and has no record of.
  func resolvedSelection(in store: IanStore) -> TodaySelection? {
    guard case .item(let id) = selection else { return selection }
    return store.state.items[id] != nil || store.removals[id] != nil ? selection : nil
  }

  /// Rebuilds the scene from the store. Returns whether a pillar is still sinking, so the
  /// caller builds again when it has finished.
  @discardableResult
  func refresh(store: IanStore, openedAt: TimeInterval?, now: TimeInterval) -> Bool {
    guard let today = store.state.today else {
      if scene != nil { scene = nil }
      memory = FieldMemory()
      return false
    }
    let selected = resolvedSelection(in: store).flatMap {
      TodaySelectionModel.pillar(for: $0, in: today)
    }
    let removedAt = store.removals.mapValues { $0.removedAt.timeIntervalSinceReferenceDate }
    let built = FieldSceneBuilder.build(
      today: today, hasItem: { store.state.items[$0] != nil }, removedAt: removedAt,
      selected: selected, openedAt: openedAt, memory: memory, now: now)
    if scene != built.scene { scene = built.scene }
    memory = built.memory
    return memory.hasUnfinishedSinking(at: now)
  }
}
