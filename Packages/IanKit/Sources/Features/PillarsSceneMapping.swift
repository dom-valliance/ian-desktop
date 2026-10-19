import Contract
import Surface

/// The field draws `PillarsScene`, which Surface defines without the contract; these map the
/// contract's horizon, kind and cells to it and back.
extension FieldCellRef {
  var pillarKey: PillarCellKey {
    let horizon: PillarHorizon
    switch self.horizon {
    case .now: horizon = .now
    case .week: horizon = .week
    case .later: horizon = .later
    }
    return PillarCellKey(unitID: unitID, horizon: horizon)
  }

  init(_ key: PillarCellKey) {
    let horizon: Components.Schemas.Horizon
    switch key.horizon {
    case .now: horizon = .now
    case .week: horizon = .week
    case .later: horizon = .later
    }
    self.init(unitID: key.unitID, horizon: horizon)
  }
}

extension FieldSceneModel {
  var pillarsScene: PillarsScene {
    PillarsScene(
      unitIDs: unitIDs,
      cells: cells.map {
        PillarCell(
          key: TodaySelectionModel.ref($0).pillarKey, pressure: $0.pressure,
          kind: ItemKindStyle.pillarKind($0.kind), working: $0.working)
      },
      selected: selected?.pillarKey, openedAt: openedAt,
      sinking: Dictionary(uniqueKeysWithValues: sinking.map { ($0.key.pillarKey, $0.value) }))
  }
}
