import Contract
import Store
import SwiftUI

/// The small monospaced heading over a group of cards.
struct GroupHeading: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(ClientPalette.label)
      .tracking(ClientPalette.labelTracking)
      .foregroundStyle(ClientPalette.secondary(0.6))
      .accessibilityAddTraits(.isHeader)
  }
}

/// One card as a list row, with the insets and the clear ground the card views share.
struct CardRow: View {
  let store: IanStore
  let item: Components.Schemas.Item

  var body: some View {
    ItemCardView(store: store, item: item)
      .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
  }
}

/// The list every view draws its cards in. A real `List`, so the keyboard and VoiceOver reach
/// every card and every action in it the way they reach a row on Today.
struct CardList<Content: View>: View {
  let emptyText: String?
  @ViewBuilder let content: Content

  var body: some View {
    List { content }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .overlay {
        if let emptyText {
          Text(emptyText)
            .font(.system(size: 13))
            .foregroundStyle(ClientPalette.secondary(0.6))
        }
      }
  }
}

/// A group's cards under its heading, as list rows.
struct GroupRows: View {
  let store: IanStore
  let group: ListedGroup

  var body: some View {
    Section {
      ForEach(group.items, id: \.id) { CardRow(store: store, item: $0) }
    } header: {
      GroupHeading(text: group.label)
    }
  }
}

/// Proposals in the action-class groups `views.proposals` names.
struct ProposalsView: View {
  let store: IanStore

  var body: some View {
    let model = ProposalsListModel(state: store.state)
    CardList(emptyText: model.isLoaded && model.groups.isEmpty ? "No proposals are waiting." : nil)
    {
      ForEach(model.groups) { GroupRows(store: store, group: $0) }
    }
  }
}

/// Commitments in the three tabs of `views.commitments`.
struct CommitmentsView: View {
  let store: IanStore
  @State private var tab: CommitmentsListModel.Tab = .owedByMe

  var body: some View {
    let model = CommitmentsListModel(state: store.state)
    let items = model.items(in: tab)
    VStack(spacing: 0) {
      Picker("Commitments", selection: $tab) {
        ForEach(CommitmentsListModel.Tab.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel("Commitments tabs")
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      CardList(emptyText: model.isLoaded && items.isEmpty ? tab.emptyText : nil) {
        ForEach(items, id: \.id) { CardRow(store: store, item: $0) }
      }
    }
  }
}

/// Tasks in the horizon sections and unit groups `views.tasks` names.
struct TasksView: View {
  let store: IanStore

  var body: some View {
    let model = TasksListModel(state: store.state)
    CardList(emptyText: model.isLoaded && model.sections.isEmpty ? "No tasks are open." : nil) {
      ForEach(model.sections) { section in
        Section {
          ForEach(section.groups) { group in
            Text(group.label)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(ClientPalette.secondary(0.75))
              .listRowSeparator(.hidden)
              .listRowBackground(Color.clear)
              .accessibilityAddTraits(.isHeader)
            ForEach(group.items, id: \.id) { CardRow(store: store, item: $0) }
          }
        } header: {
          GroupHeading(text: section.label)
        }
      }
    }
  }
}

/// Alerts in the severity groups `views.alerts` names. The P0 groups sit above the list, outside
/// its scrolling, so they stay in view.
struct AlertsView: View {
  let store: IanStore

  var body: some View {
    let model = AlertsListModel(state: store.state)
    VStack(spacing: 0) {
      if !model.pinned.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(model.pinned) { group in
              GroupHeading(text: group.label)
              ForEach(group.items, id: \.id) { ItemCardView(store: store, item: $0) }
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
        }
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
        Divider().overlay(ClientPalette.line)
      }
      CardList(
        emptyText: model.isLoaded && model.pinned.isEmpty && model.scrolling.isEmpty
          ? "No alerts are open." : nil
      ) {
        ForEach(model.scrolling) { GroupRows(store: store, group: $0) }
      }
    }
  }
}
