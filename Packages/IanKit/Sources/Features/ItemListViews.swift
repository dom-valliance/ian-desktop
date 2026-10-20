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

/// The scrolling column every view draws its cards in. A `ScrollView` holding a plain `VStack`,
/// not a `List` and not lazy: buttons inside a `List` row are outside the Tab order, so the cards'
/// actions and the hand-off would be unreachable from the keyboard. Here each is an ordinary
/// control in the key view loop, as the footer's buttons on Today are. Each group is a focus
/// section, so directional movement stays within it.
struct CardList<Content: View>: View {
  let emptyText: String?
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) { content }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .overlay {
      if let emptyText {
        Text(emptyText)
          .font(.system(size: 13))
          .foregroundStyle(ClientPalette.secondary(0.6))
      }
    }
  }
}

/// A group's cards under its heading.
struct GroupSection: View {
  let store: IanStore
  let group: ListedGroup

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GroupHeading(text: group.label)
      ForEach(group.entries) { ItemCardView(store: store, entry: $0) }
    }
    .focusSection()
  }
}

/// Proposals in the action-class groups `views.proposals` names.
struct ProposalsView: View {
  let store: IanStore

  var body: some View {
    let model = ProposalsListModel(state: store.state, removals: store.removals)
    CardList(emptyText: model.isLoaded && model.groups.isEmpty ? "No proposals are waiting." : nil)
    {
      ForEach(model.groups) { GroupSection(store: store, group: $0) }
    }
  }
}

/// Commitments in the three tabs of `views.commitments`.
struct CommitmentsView: View {
  let store: IanStore
  @State private var tab: CommitmentsListModel.Tab

  init(store: IanStore, tab: CommitmentsListModel.Tab = .owedByMe) {
    self.store = store
    _tab = State(initialValue: tab)
  }

  var body: some View {
    let model = CommitmentsListModel(state: store.state, removals: store.removals)
    let entries = model.entries(in: tab)
    VStack(spacing: 0) {
      Picker("Commitments", selection: $tab) {
        ForEach(CommitmentsListModel.Tab.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel("Commitments tabs")
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      CardList(emptyText: model.isLoaded && entries.isEmpty ? tab.emptyText : nil) {
        ForEach(entries) { ItemCardView(store: store, entry: $0).focusSection() }
      }
    }
    .background { tabShortcuts }
  }

  /// Command-1 to Command-3 while Commitments is shown. The buttons draw nothing and VoiceOver
  /// skips them: the picker is the control, these are its keys.
  private var tabShortcuts: some View {
    ForEach(CommitmentsListModel.Tab.allCases) { shortcut in
      Button(shortcut.title) { tab = shortcut }
        .keyboardShortcut(KeyEquivalent(shortcut.shortcutKey), modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
  }
}

/// Tasks in the horizon sections and unit groups `views.tasks` names.
struct TasksView: View {
  let store: IanStore

  var body: some View {
    let model = TasksListModel(state: store.state, removals: store.removals)
    CardList(emptyText: model.isLoaded && model.sections.isEmpty ? "No tasks are open." : nil) {
      ForEach(model.sections) { section in
        VStack(alignment: .leading, spacing: 14) {
          GroupHeading(text: section.label)
          ForEach(section.groups) { group in
            VStack(alignment: .leading, spacing: 10) {
              Text(group.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClientPalette.secondary(0.75))
                .accessibilityAddTraits(.isHeader)
              ForEach(group.entries) { ItemCardView(store: store, entry: $0) }
            }
            .focusSection()
          }
        }
      }
    }
  }
}

/// Alerts in the groups `views.alerts` names. The groups the server marks `pinned` sit above the
/// list, outside its scrolling, so they stay in view.
struct AlertsView: View {
  let store: IanStore

  var body: some View {
    let model = AlertsListModel(state: store.state, removals: store.removals)
    VStack(spacing: 0) {
      if !model.pinned.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(model.pinned) { GroupSection(store: store, group: $0) }
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
        ForEach(model.scrolling) { GroupSection(store: store, group: $0) }
      }
    }
  }
}
