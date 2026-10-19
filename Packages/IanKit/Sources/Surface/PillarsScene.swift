import Foundation

/// A row of the Pillars field. The raw value is the design's row index, so `now` is the front.
public enum PillarHorizon: Int, Sendable, CaseIterable {
  case later = 0
  case week = 1
  case now = 2
}

/// What a pillar is made of, which fixes its colour. The server decides it (AGENTS.md Q16).
public enum PillarKind: Sendable, Equatable {
  case proposal, commitmentBy, commitmentTo, task, alert
}

public struct PillarCellKey: Hashable, Sendable {
  public let unitID: String
  public let horizon: PillarHorizon

  public init(unitID: String, horizon: PillarHorizon) {
    self.unitID = unitID
    self.horizon = horizon
  }
}

public struct PillarCell: Equatable, Sendable {
  public let key: PillarCellKey
  /// The server's aggregate pressure, 0 to 1. The client never computes it.
  public let pressure: Double
  public let kind: PillarKind
  public let working: Bool

  public init(key: PillarCellKey, pressure: Double, kind: PillarKind, working: Bool) {
    self.key = key
    self.pressure = pressure
    self.kind = kind
    self.working = working
  }
}

/// Everything the field draws, apart from the clock. Times are seconds since the reference date.
public struct PillarsScene: Equatable, Sendable {
  /// Columns left to right, in `field.units` order, at most five.
  public var unitIDs: [String]
  /// Cells absent here draw as empty tiles.
  public var cells: [PillarCell]
  public var selected: PillarCellKey?
  /// Growth starts here. Nil means fully grown.
  public var openedAt: TimeInterval?
  /// A cell's sink starts here.
  public var sinking: [PillarCellKey: TimeInterval]

  public init(
    unitIDs: [String], cells: [PillarCell], selected: PillarCellKey?, openedAt: TimeInterval?,
    sinking: [PillarCellKey: TimeInterval]
  ) {
    self.unitIDs = unitIDs
    self.cells = cells
    self.selected = selected
    self.openedAt = openedAt
    self.sinking = sinking
  }
}
