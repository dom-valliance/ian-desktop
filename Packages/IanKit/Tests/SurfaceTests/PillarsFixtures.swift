import Contract

@testable import Surface

/// Maps a mock scenario's `today.field` to a scene. Surface has no Contract types, so the
/// mapping lives here; the Today view owns the real one.
extension OrbitScenario {
  var pillarsScene: PillarsScene {
    PillarsScene(
      unitIDs: today.field.units.map(\.id),
      cells: today.field.cells.map { cell in
        PillarCell(
          key: PillarCellKey(
            unitID: cell.unitId, horizon: PillarHorizon(cell.horizon)),
          pressure: cell.pressure, kind: PillarKind(cell.kind), working: cell.working)
      },
      selected: nil, openedAt: nil, sinking: [:])
  }
}

extension PillarHorizon {
  init(_ horizon: Components.Schemas.Horizon) {
    switch horizon {
    case .now: self = .now
    case .week: self = .week
    case .later: self = .later
    }
  }
}

extension PillarKind {
  init(_ kind: Components.Schemas.ItemKind) {
    switch kind {
    case .proposal: self = .proposal
    case .commitmentBy: self = .commitmentBy
    case .commitmentTo: self = .commitmentTo
    case .task: self = .task
    case .alert: self = .alert
    }
  }
}
