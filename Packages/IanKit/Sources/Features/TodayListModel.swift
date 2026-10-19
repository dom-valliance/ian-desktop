import Contract
import Store

/// The rows under the field, from `today.lists` in the order the server sent them (spec 6.3).
/// Nothing is sorted, counted or filtered here: a row is built for each id or group the server
/// named, from the item the store holds or the item it has just removed.
struct TodayListModel: Equatable {
  typealias Kind = Components.Schemas.ItemKind

  struct NowRow: Equatable, Identifiable {
    let id: String
    let title: String
    let kind: Kind
    /// The server has removed the item; the row dims until it leaves.
    let isSettled: Bool
    let accessibilityLabel: String
  }

  struct WeekRow: Equatable, Identifiable {
    var id: String { unitID }
    let unitID: String
    let unitName: String
    let itemIDs: [String]
    /// The week pillar's kind, which colours the row.
    let kind: Kind?
    let accessibilityLabel: String
  }

  struct LaterCount: Equatable {
    let kind: Kind
    let count: Int
    /// The view the count links to.
    let section: ClientSection
    let phrase: String
  }

  struct LaterRow: Equatable, Identifiable {
    var id: String { unitID }
    let unitID: String
    let unitName: String
    let kind: Kind?
    let counts: [LaterCount]
    let accessibilityLabel: String
  }

  let now: [NowRow]
  let week: [WeekRow]
  let later: [LaterRow]

  init(state: StoreState, removals: [String: IanStore.Removal], statuses: ItemStatuses) {
    guard let today = state.today else {
      now = []
      week = []
      later = []
      return
    }
    let unitNames = Dictionary(
      today.field.units.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    func kind(of unitID: String, _ horizon: Components.Schemas.Horizon) -> Kind? {
      today.field.cells.first { $0.unitId == unitID && $0.horizon == horizon }?.kind
    }

    now = today.lists.now.compactMap { id in
      let removal = removals[id]
      guard let item = state.items[id] ?? removal?.item else { return nil }
      return NowRow(
        id: id, title: item.title, kind: item.kind, isSettled: removal != nil,
        accessibilityLabel: Self.label(
          [ItemKindStyle.name(item.kind), item.title, "now"],
          status: removal != nil ? "settled" : statuses.description(of: id)))
    }
    week = today.lists.week.map { group in
      let name = unitNames[group.unitId] ?? group.unitId
      return WeekRow(
        unitID: group.unitId, unitName: name, itemIDs: group.itemIds,
        kind: kind(of: group.unitId, .week),
        accessibilityLabel: Self.label(
          ["This week", name, Self.itemsPhrase(group.itemIds.count)], status: nil))
    }
    later = today.lists.later.map { group in
      let name = unitNames[group.unitId] ?? group.unitId
      let counts = group.counts.map {
        LaterCount(
          kind: $0.kind, count: $0.count, section: ItemKindStyle.section(for: $0.kind),
          phrase: ItemKindStyle.phrase($0.kind, count: $0.count))
      }
      return LaterRow(
        unitID: group.unitId, unitName: name,
        kind: kind(of: group.unitId, .later) ?? group.counts.first?.kind, counts: counts,
        accessibilityLabel: Self.label(["Later", name] + counts.map(\.phrase), status: nil))
    }
  }

  static func itemsPhrase(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
  }

  private static func label(_ parts: [String], status: String?) -> String {
    (parts + [status].compactMap { $0 }).joined(separator: ", ")
  }
}

/// The pending mark and the notice the store holds for each item, as words for a label.
struct ItemStatuses: Equatable {
  var pending: Set<String> = []
  var notices: [String: IanStore.Notice] = [:]

  init(pending: Set<String> = [], notices: [String: IanStore.Notice] = [:]) {
    self.pending = pending
    self.notices = notices
  }

  @MainActor
  init(store: IanStore) {
    self.init(pending: Set(store.pending.keys), notices: store.notices)
  }

  /// "pending", the error, or "changed"; nil when the item has none of them.
  func description(of itemID: String) -> String? {
    if pending.contains(itemID) { return "pending" }
    switch notices[itemID] {
    case .failed(let message): return "error: \(message)"
    case .changed: return "changed"
    case nil: return nil
    }
  }
}
