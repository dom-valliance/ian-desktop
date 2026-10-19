import Contract
import Foundation

/// What the Pillars field draws, in the contract's own terms. D5's wiring maps it to the
/// field's `PillarsScene`; the logic of what stands, what is selected and what sinks lives here,
/// where it is tested without a view.
struct FieldSceneModel: Equatable {
  var unitIDs: [String]
  /// A cell per `field.cells` entry, and a cell that has just left Today while it finishes
  /// sinking, with the last pressure it had.
  var cells: [Components.Schemas.FieldCell]
  var selected: FieldCellRef?
  /// When the expanded client opened, in seconds since the reference date.
  var openedAt: TimeInterval?
  /// The time each sinking cell started to sink, in seconds since the reference date.
  var sinking: [FieldCellRef: TimeInterval]
}

/// What the builder remembers between two builds, so a cell that leaves Today can finish
/// sinking after the server's update has dropped it.
struct FieldMemory: Equatable {
  fileprivate var cells: [FieldCellRef: Components.Schemas.FieldCell] = [:]
  fileprivate var sinking: [FieldCellRef: TimeInterval] = [:]

  /// Whether a cell has started to sink and not finished, so the caller builds again once it
  /// has, and the cell that left Today can go.
  func hasUnfinishedSinking(at now: TimeInterval) -> Bool {
    sinking.values.contains { now - $0 < FieldSceneBuilder.sinkDuration }
  }
}

/// Builds the field's scene from Today and the store (spec 6.3, design README, Pillars).
///
/// A pillar sinks when the server settles every item in its cell, and never on a click: an
/// action marks its item pending and the item stays in the store until the server's event
/// removes it. "Settled" is therefore the absence of every item the cell names. The removal
/// record only says when the item left, so the sink starts then.
enum FieldSceneBuilder {
  /// How long a pillar takes to sink (design README: `sink` over 0.7 seconds).
  static let sinkDuration: TimeInterval = 0.7

  /// - Parameters:
  ///   - hasItem: Whether the store still holds the item.
  ///   - removedAt: When the server removed each item the removal record holds.
  ///   - now: Seconds since the reference date.
  static func build(
    today: Components.Schemas.Today, hasItem: (String) -> Bool, removedAt: [String: TimeInterval],
    selected: FieldCellRef?, openedAt: TimeInterval?, memory: FieldMemory, now: TimeInterval
  ) -> (scene: FieldSceneModel, memory: FieldMemory) {
    let unitIDs = today.field.units.map(\.id)
    var cells = today.field.cells
    var next = FieldMemory()
    var current: Set<FieldCellRef> = []

    func sinkStart(of cell: Components.Schemas.FieldCell, _ ref: FieldCellRef) -> TimeInterval? {
      guard cell.itemIds.allSatisfy({ !hasItem($0) }) else { return nil }
      return memory.sinking[ref] ?? cell.itemIds.compactMap { removedAt[$0] }.max() ?? now
    }

    for cell in today.field.cells {
      let ref = TodaySelectionModel.ref(cell)
      current.insert(ref)
      next.cells[ref] = cell
      next.sinking[ref] = sinkStart(of: cell, ref)
    }
    // A cell Today dropped keeps sinking from its last values, until it has finished.
    for (ref, old) in memory.cells where !current.contains(ref) && unitIDs.contains(ref.unitID) {
      guard let start = sinkStart(of: old, ref), now - start < sinkDuration else { continue }
      cells.append(old)
      next.cells[ref] = old
      next.sinking[ref] = start
    }
    return (
      FieldSceneModel(
        unitIDs: unitIDs, cells: cells, selected: selected, openedAt: openedAt,
        sinking: next.sinking),
      next
    )
  }
}
