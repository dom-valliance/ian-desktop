import Contract
import Foundation

/// What the server last told the client, and the reducer that keeps it current (ADR 0001).
///
/// The client computes nothing here. A snapshot replaces everything; an event replaces the whole
/// object it carries or removes the item it names. Order, grouping, counts and pressure are the
/// server's, and live in `today` and `views`.
public struct StoreState: Equatable, Sendable {
  public typealias Item = Components.Schemas.Item

  public var me: Components.Schemas.Me?
  public var today: Components.Schemas.Today?
  public var views: Components.Schemas.Views?
  /// Every open item by id. The views and Today carry the order.
  public var items: [String: Item] = [:]
  public var agents: [Components.Schemas.Agent] = []
  public var costToday: Components.Schemas.CostToday?
  public var settings: Components.Schemas.Settings?
  /// The id of the last event applied, or the snapshot's cursor.
  public private(set) var lastEventID: UInt64?

  public init() {}

  /// What applying an event meant for the rest of the store.
  public struct Effects: Equatable, Sendable {
    /// False when the event was a repeat or older than the last applied one.
    public var applied = false
    /// The action or hand-off that caused the event, which clears its pending mark.
    public var correlationID: String?
    public var removedItemID: String?
    /// The item as it was held when `item.removed` or `alert.cleared` took it away.
    public var removedItem: Item?
    /// The one-line `outcome` of `item.removed`. An `alert.cleared` event carries none.
    public var removalOutcome: String?
    /// The minimum version from `client.deprecated`.
    public var deprecatedBelow: String?
  }

  public mutating func apply(snapshot: Components.Schemas.Snapshot) {
    today = snapshot.today
    views = snapshot.views
    items = Dictionary(
      snapshot.items.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    agents = snapshot.agents.agents
    costToday = snapshot.agents.costToday
    settings = snapshot.settings
    lastEventID = UInt64(snapshot.cursor)
  }

  /// Applies one event, unless its id is at or below the last applied one.
  /// - Parameter id: The event's id. Nil for `heartbeat`, which is never stored or replayed.
  @discardableResult
  public mutating func apply(event: Components.Schemas.StreamEvent, id: String?) -> Effects {
    if let id {
      guard let number = UInt64(id), lastEventID.map({ number > $0 }) ?? true else {
        return Effects()
      }
      lastEventID = number
    }
    var effects = Effects(applied: true)
    switch event {
    case .item_upserted(let event):
      items[event.item.id] = event.item
      effects.correlationID = event.correlationId
    case .alert_raised(let event):
      items[event.item.id] = event.item
      effects.correlationID = event.correlationId
    case .item_removed(let event):
      effects.removedItem = items[event.itemId]
      effects.removalOutcome = event.outcome
      items[event.itemId] = nil
      effects.removedItemID = event.itemId
      effects.correlationID = event.correlationId
    case .alert_cleared(let event):
      effects.removedItem = items[event.itemId]
      items[event.itemId] = nil
      effects.removedItemID = event.itemId
      effects.correlationID = event.correlationId
    case .today_updated(let event):
      today = event.today
    case .views_updated(let event):
      views = event.views
    case .agent_updated(let event):
      if let index = agents.firstIndex(where: { $0.id == event.agent.id }) {
        agents[index] = event.agent
      } else {
        agents.append(event.agent)
      }
      costToday = event.costToday
    case .settings_updated(let event):
      settings = event.settings
    case .client_deprecated(let event):
      effects.deprecatedBelow = event.minClientVersion
    case .heartbeat:
      break
    }
    return effects
  }
}
