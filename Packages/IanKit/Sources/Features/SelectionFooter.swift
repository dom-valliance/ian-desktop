import Contract
import Store
import SwiftUI

/// What the footer says about the selection: a monospaced "KIND / UNIT / HORIZON" line, the
/// title, the meta line, and then the item's actions, or for an item the server has just
/// removed, its outcome line (design README, selection footer). Pure, so it is tested without a
/// view.
struct FooterContent: Equatable {
  enum Trailing: Equatable {
    /// The item's own actions, drawn by the action component.
    case actions
    /// The server's one line for a removed item. `nil` text means the server sent none.
    case outcome(String?)
    /// The items of a rolled-up week group, each one selectable.
    case members([String])
    case none
  }

  let kicker: String
  let title: String
  let meta: String
  let trailing: Trailing

  /// - Returns: Nil when the selection names an item the store neither holds nor remembers.
  init?(selection: TodaySelection, state: StoreState, removals: [String: IanStore.Removal]) {
    switch selection {
    case .item(let id):
      if let item = state.items[id] {
        self.init(item: item, trailing: .actions)
      } else if let removal = removals[id] {
        self.init(item: removal.item, trailing: .outcome(removal.outcome))
      } else {
        return nil
      }
    case .week(let unitID):
      guard let group = state.today?.lists.week.first(where: { $0.unitId == unitID }) else {
        return nil
      }
      let unit = Self.unitName(unitID, in: state)
      self.init(
        kicker: "Rolled up / \(unit) / This week", title: unit,
        meta: TodayListModel.itemsPhrase(group.itemIds.count), trailing: .members(group.itemIds))
    case .later(let unitID):
      guard let group = state.today?.lists.later.first(where: { $0.unitId == unitID }) else {
        return nil
      }
      let unit = Self.unitName(unitID, in: state)
      self.init(
        kicker: "Rolled up / \(unit) / Later", title: unit,
        meta: group.counts.map { ItemKindStyle.phrase($0.kind, count: $0.count) }
          .joined(separator: ", "),
        trailing: Trailing.none)
    }
  }

  private init(item: Components.Schemas.Item, trailing: Trailing) {
    self.init(
      kicker: [
        ItemKindStyle.name(item.kind), item.unit.name, ItemKindStyle.name(item.horizon),
      ].joined(separator: " / "),
      title: item.title, meta: item.meta, trailing: trailing)
  }

  private init(kicker: String, title: String, meta: String, trailing: Trailing) {
    self.kicker = kicker.uppercased()
    self.title = title
    self.meta = meta
    self.trailing = trailing
  }

  private static func unitName(_ id: String, in state: StoreState) -> String {
    state.today?.field.units.first { $0.id == id }?.name ?? id
  }
}

struct SelectionFooter: View {
  let store: IanStore
  let selection: TodaySelection?
  let onSelect: (TodaySelection) -> Void

  var body: some View {
    if let selection,
      let content = FooterContent(
        selection: selection, state: store.state, removals: store.removals)
    {
      HStack(alignment: .center, spacing: 20) {
        VStack(alignment: .leading, spacing: 2) {
          Text(content.kicker)
            .font(ClientPalette.label)
            .tracking(ClientPalette.labelTracking)
            .foregroundStyle(ClientPalette.secondary(0.7))
            .lineLimit(1)
          Text(content.title)
            .font(.system(size: 16, weight: .medium))
            .lineLimit(2)
          Text(content.meta)
            .font(.system(size: 13))
            .foregroundStyle(ClientPalette.secondary())
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        trailing(content.trailing, selection: selection)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
  }

  @ViewBuilder private func trailing(_ trailing: FooterContent.Trailing, selection: TodaySelection)
    -> some View
  {
    switch trailing {
    case .actions:
      if case .item(let id) = selection, let item = store.state.items[id] {
        ItemActionsView(store: store, item: item).id(item.id)
      }
    case .outcome(let text):
      Text(text ?? "Closed")
        .font(.system(size: 13))
        .foregroundStyle(ClientPalette.resolved)
        .frame(maxWidth: 320, alignment: .trailing)
        .multilineTextAlignment(.trailing)
    case .members(let ids):
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(ids, id: \.self) { id in
            if let item = store.state.items[id] {
              Button {
                onSelect(.item(id))
              } label: {
                HStack(spacing: 10) {
                  RoundedRectangle(cornerRadius: 2)
                    .fill(ItemKindStyle.colour(item.kind))
                    .frame(width: 10, height: 10)
                  Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .buttonStyle(ListRowButtonStyle(isSelected: false))
              .accessibilityLabel("\(ItemKindStyle.name(item.kind)), \(item.title)")
            }
          }
        }
      }
      .frame(width: 320)
      .frame(maxHeight: 110)
    case .none:
      EmptyView()
    }
  }
}
