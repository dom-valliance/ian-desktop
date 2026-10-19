import Contract
import Foundation
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

    init(_ count: Components.Schemas.KindCount) {
      kind = count.kind
      self.count = count.count
      section = ItemKindStyle.section(for: count.kind)
      phrase = ItemKindStyle.phrase(count.kind, count: count.count)
    }
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

  init(
    state: StoreState, removals: [String: IanStore.Removal], statuses: ItemStatuses, at date: Date
  ) {
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

    self.now = Self.nowIDs(today.lists.now, removals: removals, at: date).compactMap { id in
      let removal = removals[id]
      guard let item = state.items[id] ?? removal?.item else { return nil }
      return NowRow(
        id: id, title: item.title, kind: item.kind, isSettled: removal != nil,
        accessibilityLabel: Self.itemLabel(
          item, horizon: "now", status: removal != nil ? "settled" : statuses.description(of: id)))
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
      let counts = group.counts.map(LaterCount.init)
      return LaterRow(
        unitID: group.unitId, unitName: name,
        kind: kind(of: group.unitId, .later) ?? group.counts.first?.kind, counts: counts,
        accessibilityLabel: Self.label(["Later", name] + counts.map(\.phrase), status: nil))
    }
  }

  static func itemsPhrase(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
  }

  /// The Now list as the server sent it, with each item the server has just removed kept at the
  /// place it stood, until its pillar has finished sinking. The row then leaves with its pillar.
  static func nowIDs(_ listed: [String], removals: [String: IanStore.Removal], at now: Date)
    -> [String]
  {
    var ids = listed
    let leaving = removals.values.filter {
      !listed.contains($0.item.id) && $0.nowListIndex != nil
        && now.timeIntervalSince($0.removedAt) < FieldSceneBuilder.sinkDuration
    }
    for removal in leaving.sorted(by: { ($0.nowListIndex ?? 0) < ($1.nowListIndex ?? 0) }) {
      ids.insert(removal.item.id, at: min(removal.nowListIndex ?? 0, ids.count))
    }
    return ids
  }

  /// "Proposal, Title, now, being worked on, pending": the kind, title and horizon, whether an
  /// agent is acting on the item, and its pending or error state.
  static func itemLabel(_ item: Components.Schemas.Item, horizon: String, status: String?)
    -> String
  {
    label(
      [ItemKindStyle.name(item.kind), item.title, horizon]
        + (item.working ? ["being worked on"] : []), status: status)
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
