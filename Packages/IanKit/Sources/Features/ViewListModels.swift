import Contract
import Foundation
import Store

/// An item a view lists: the one the store holds, or the one the server has just removed, which
/// the view draws leaving (the contract allows `views` to name an item that has just left).
struct ListedItem: Equatable, Identifiable {
  let item: Components.Schemas.Item
  let removal: IanStore.Removal?

  var id: String { item.id }

  /// Resolves an id from the open items, then from the removals. An id found in neither is nil:
  /// nothing is invented, and the server's next `views.updated` settles it.
  static func resolve(_ id: String, in state: StoreState, removals: [String: IanStore.Removal])
    -> ListedItem?
  {
    if let item = state.items[id] { return ListedItem(item: item, removal: nil) }
    return removals[id].map { ListedItem(item: $0.item, removal: $0) }
  }
}

/// One labelled group of items, as `views` sent it.
struct ListedGroup: Equatable, Identifiable {
  let id: String
  let label: String
  let entries: [ListedItem]
  /// The server asked for this group to stay in view above the groups that scroll.
  let isPinned: Bool

  init(
    _ group: Components.Schemas.ViewGroup, in state: StoreState,
    removals: [String: IanStore.Removal], idPrefix: String = ""
  ) {
    id = idPrefix + group.id
    label = group.label
    isPinned = group.pinned ?? false
    entries = group.itemIds.compactMap { ListedItem.resolve($0, in: state, removals: removals) }
  }
}

/// Proposals: the groups of `views.proposals` in the order sent, each headed by its action class
/// label (spec 6.3, ADR 0009). Nothing is grouped, sorted or counted here.
struct ProposalsListModel: Equatable {
  /// False until the first snapshot, so an empty list is not shown as "nothing waiting".
  let isLoaded: Bool
  let groups: [ListedGroup]

  init(state: StoreState, removals: [String: IanStore.Removal] = [:]) {
    isLoaded = state.views != nil
    groups = (state.views.map { LeavingItems.proposals($0, removals: removals) } ?? []).map {
      ListedGroup($0, in: state, removals: removals)
    }
  }
}

/// Commitments: the three tabs of `views.commitments`, each in the order sent.
struct CommitmentsListModel: Equatable {
  enum Tab: String, CaseIterable, Identifiable {
    case owedByMe, owedToMe, toConfirm

    var id: String { rawValue }

    /// The digit that, with Command, shows this tab while Commitments is on screen.
    var shortcutKey: Character {
      switch self {
      case .owedByMe: "1"
      case .owedToMe: "2"
      case .toConfirm: "3"
      }
    }

    var title: String {
      switch self {
      case .owedByMe: "Owed by me"
      case .owedToMe: "Owed to me"
      case .toConfirm: "To confirm"
      }
    }

    var emptyText: String {
      switch self {
      case .owedByMe: "Nothing is owed by you."
      case .owedToMe: "Nothing is owed to you."
      case .toConfirm: "Nothing is waiting for you to confirm."
      }
    }
  }

  let isLoaded: Bool
  private let byTab: [Tab: [ListedItem]]

  init(state: StoreState, removals: [String: IanStore.Removal] = [:]) {
    isLoaded = state.views != nil
    let tabs = state.views.map { LeavingItems.commitments($0, removals: removals) }
    func entries(_ ids: [String]?) -> [ListedItem] {
      (ids ?? []).compactMap { ListedItem.resolve($0, in: state, removals: removals) }
    }
    byTab = [
      .owedByMe: entries(tabs?.owedByMe), .owedToMe: entries(tabs?.owedToMe),
      .toConfirm: entries(tabs?.toConfirm),
    ]
  }

  func entries(in tab: Tab) -> [ListedItem] { byTab[tab] ?? [] }
}

/// Tasks: the horizon sections of `views.tasks`, each holding its unit groups, as sent.
struct TasksListModel: Equatable {
  struct Section: Equatable, Identifiable {
    var id: String { horizon.rawValue }
    let horizon: Components.Schemas.Horizon
    let label: String
    let groups: [ListedGroup]
  }

  let isLoaded: Bool
  let sections: [Section]

  init(state: StoreState, removals: [String: IanStore.Removal] = [:]) {
    isLoaded = state.views != nil
    sections = (state.views.map { LeavingItems.tasks($0, removals: removals) } ?? []).map {
      section in
      Section(
        horizon: section.horizon, label: section.label,
        // A unit repeats across horizons, so its group id is scoped by the horizon.
        groups: section.groups.map {
          ListedGroup($0, in: state, removals: removals, idPrefix: "\(section.horizon.rawValue)/")
        })
    }
  }
}

/// Alerts: the groups of `views.alerts` in the order sent. A group the server marks `pinned`
/// is drawn above the list and stays in view; the others scroll. Which groups are pinned is the
/// server's, never read from an item's severity.
struct AlertsListModel: Equatable {
  let isLoaded: Bool
  let pinned: [ListedGroup]
  let scrolling: [ListedGroup]

  init(state: StoreState, removals: [String: IanStore.Removal] = [:]) {
    isLoaded = state.views != nil
    let groups = (state.views.map { LeavingItems.alerts($0, removals: removals) } ?? []).map {
      ListedGroup($0, in: state, removals: removals)
    }
    pinned = groups.filter(\.isPinned)
    scrolling = groups.filter { !$0.isPinned }
  }
}
