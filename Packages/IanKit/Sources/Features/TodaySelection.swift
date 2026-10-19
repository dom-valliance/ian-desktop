import Contract

/// What the list has selected: a Now item, a rolled-up week group or a later group. A group is
/// named by its unit, which is always one of `field.units`.
enum TodaySelection: Hashable, Sendable {
  case item(String)
  case week(unitID: String)
  case later(unitID: String)
}

/// A pillar: one field cell, named by its column and horizon.
struct FieldCellRef: Hashable, Sendable {
  let unitID: String
  let horizon: Components.Schemas.Horizon
}

/// Selecting a pillar selects its list row and the reverse (spec 6.3). Pure: it reads the
/// server's field and chooses nothing the server did not send.
enum TodaySelectionModel {
  typealias Today = Components.Schemas.Today

  /// The row a pillar selects: its first item for Now, or its unit's week or later group.
  /// Nil when the pillar is not in the field.
  static func selection(forPillar pillar: FieldCellRef, in today: Today) -> TodaySelection? {
    guard let cell = cell(at: pillar, in: today) else { return nil }
    switch pillar.horizon {
    case .now: return cell.itemIds.first.map(TodaySelection.item)
    case .week: return .week(unitID: pillar.unitID)
    case .later: return .later(unitID: pillar.unitID)
    }
  }

  /// The pillar a row selects: the one holding the item, or the unit's week or later cell.
  /// Nil when the field has no such pillar, or the unit is not one of `field.units`.
  static func pillar(for selection: TodaySelection, in today: Today) -> FieldCellRef? {
    switch selection {
    case .item(let id):
      return today.field.cells.first { $0.itemIds.contains(id) }.flatMap {
        existing(ref($0), in: today)
      }
    case .week(let unitID):
      return existing(FieldCellRef(unitID: unitID, horizon: .week), in: today)
    case .later(let unitID):
      return existing(FieldCellRef(unitID: unitID, horizon: .later), in: today)
    }
  }

  static func ref(_ cell: Components.Schemas.FieldCell) -> FieldCellRef {
    FieldCellRef(unitID: cell.unitId, horizon: cell.horizon)
  }

  private static func cell(at pillar: FieldCellRef, in today: Today)
    -> Components.Schemas.FieldCell?
  {
    guard today.field.units.contains(where: { $0.id == pillar.unitID }) else { return nil }
    return today.field.cells.first { ref($0) == pillar }
  }

  private static func existing(_ pillar: FieldCellRef, in today: Today) -> FieldCellRef? {
    cell(at: pillar, in: today) == nil ? nil : pillar
  }
}
