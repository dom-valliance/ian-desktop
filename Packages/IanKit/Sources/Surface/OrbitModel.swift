import Attention
import Foundation
import Store

/// What the Orbit shows, taken from `GET /today` and the items it names. The client counts,
/// sorts and filters nothing here: satellites are `orbit.itemIds` in the server's order, and
/// every number is the server's (ADR 0001).
public struct OrbitModel: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case commitmentBy, commitmentTo, proposal, task, alert
  }

  public struct Satellite: Equatable, Sendable {
    /// The position in the server's list, which fixes the satellite's angle.
    public let slot: Int
    public let kind: Kind

    public init(slot: Int, kind: Kind) {
      self.slot = slot
      self.kind = kind
    }
  }

  public var satellites: [Satellite]
  public var overflow: Int
  public var load: Int
  public var median: Double
  public var working: Bool
  /// The first satellite's item title, for the hover. Nil while suppressed: item text never
  /// reaches the Orbit then (spec 6.5).
  public var topTitle: String?

  public init(
    satellites: [Satellite] = [], overflow: Int = 0, load: Int = 0, median: Double = 1,
    working: Bool = false, topTitle: String? = nil
  ) {
    self.satellites = satellites
    self.overflow = overflow
    self.load = load
    self.median = median
    self.working = working
    self.topTitle = topTitle
  }

  /// A satellite whose item is not in the store is skipped, and the others keep their slots.
  public init(state: StoreState, suppression: Suppression) {
    guard let orbit = state.today?.orbit else {
      self.init()
      return
    }
    var satellites: [Satellite] = []
    for (slot, id) in orbit.itemIds.enumerated() {
      guard let item = state.items[id] else { continue }
      let kind: Kind
      switch item.kind {
      case .proposal: kind = .proposal
      case .commitmentBy: kind = .commitmentBy
      case .commitmentTo: kind = .commitmentTo
      case .task: kind = .task
      case .alert: kind = .alert
      }
      satellites.append(Satellite(slot: slot, kind: kind))
    }
    let top = orbit.itemIds.first.flatMap { state.items[$0]?.title }
    self.init(
      satellites: satellites, overflow: orbit.overflow, load: orbit.load, median: orbit.median,
      working: orbit.working, topTitle: suppression.isActive ? nil : top)
  }
}

/// Everything the surface says about the Orbit, from one store state and one suppression.
public struct OrbitPresentation: Equatable, Sendable {
  public let model: OrbitModel
  public let accessibilityLabel: String
  /// The server's count of `now` items, for the menu bar title.
  public let nowCount: Int
  public let isSuppressed: Bool

  /// The hover text: the top item's title, or nil while suppressed.
  public var hoverText: String? { model.topTitle }

  public init(state: StoreState, suppression: Suppression) {
    model = OrbitModel(state: state, suppression: suppression)
    let orbit = state.today?.orbit
    nowCount = orbit?.nowCount ?? 0
    accessibilityLabel = OrbitAccessibility.label(
      nowCount: nowCount, load: orbit?.load ?? 0, urgentCount: orbit?.urgentCount ?? 0)
    isSuppressed = suppression.isActive
  }
}
