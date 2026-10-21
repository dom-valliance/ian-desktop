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
    /// A later group's counts by kind, each linking to the view that holds them.
    case counts([TodayListModel.LaterCount])
  }

  let kicker: String
  let title: String
  let meta: String
  let trailing: Trailing

  /// What the footer is about, for the container VoiceOver enters from the list.
  var accessibilityLabel: String { "Selected: \(title)" }

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
        trailing: .counts(group.counts.map(TodayListModel.LaterCount.init)))
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
  let onNavigate: (ClientSection) -> Void
  let keys: FooterKeys

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
      .accessibilityElement(children: .contain)
      .accessibilityLabel(content.accessibilityLabel)
      .onChange(of: content.trailing, initial: true) { _, trailing in
        // An item's actions report their own count; a group's members or counts are counted here.
        switch trailing {
        case .actions: break
        case .outcome: keys.setTargetCount(0)
        case .members(let ids): keys.setTargetCount(ids.count)
        case .counts(let counts): keys.setTargetCount(counts.count)
        }
      }
      .onChange(of: keys.activations) { activate(content.trailing) }
    }
  }

  /// Return in Today's action mode on a group: opens the highlighted member item, or the view
  /// the highlighted count links to. An item's own actions are run by the action component.
  private func activate(_ trailing: FooterContent.Trailing) {
    switch trailing {
    case .members(let ids):
      if ids.indices.contains(keys.highlighted) { onSelect(.item(ids[keys.highlighted])) }
      keys.exit()
    case .counts(let counts):
      if counts.indices.contains(keys.highlighted) { onNavigate(counts[keys.highlighted].section) }
      keys.exit()
    case .actions, .outcome:
      break
    }
  }

  @ViewBuilder private func trailing(_ trailing: FooterContent.Trailing, selection: TodaySelection)
    -> some View
  {
    switch trailing {
    case .actions:
      if case .item(let id) = selection, let item = store.state.items[id] {
        ItemActionsView(store: store, item: item, keys: keys).id(item.id)
      }
    case .outcome(let text):
      Text(text ?? "Closed")
        .font(.system(size: 13))
        .foregroundStyle(ClientPalette.resolved)
        .frame(maxWidth: 320, alignment: .trailing)
        .multilineTextAlignment(.trailing)
    case .members(let ids):
      let statuses = ItemStatuses(store: store)
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(ids.enumerated()), id: \.element) { index, id in
            if let item = store.state.items[id] {
              Button {
                onSelect(.item(id))
              } label: {
                HStack(spacing: 10) {
                  KindSwatch(kind: item.kind)
                  Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .buttonStyle(ListRowButtonStyle(isSelected: selection == .item(id)))
              .keyboardHighlight(keys.isActive && keys.highlighted == index)
              .accessibilityLabel(
                TodayListModel.itemLabel(
                  item, horizon: "this week", status: statuses.description(of: id),
                  attention: ItemKindStyle.urgency(of: item)?.lowercased()))
            }
          }
        }
        // Room for the keyboard highlight, which the scroll view would otherwise clip.
        .padding(4)
      }
      .frame(width: 320)
      .frame(maxHeight: 110)
    case .counts(let counts):
      HStack(spacing: 6) {
        ForEach(Array(counts.enumerated()), id: \.element.kind) { index, count in
          Button {
            onNavigate(count.section)
          } label: {
            Text(count.phrase.uppercased())
              .font(ClientPalette.label)
              .tracking(ClientPalette.labelTracking)
          }
          .buttonStyle(ActionButtonStyle(style: .secondary))
          .keyboardHighlight(keys.isActive && keys.highlighted == index)
          .accessibilityLabel("\(count.phrase), open \(count.section.title)")
        }
      }
    }
  }
}
