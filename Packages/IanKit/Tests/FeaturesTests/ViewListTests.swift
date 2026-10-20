import Contract
import Foundation
import Store
import Testing

@testable import Features

private typealias Schemas = Components.Schemas

/// Each group as the pair the server sent: its id, label and item ids.
private func shape(_ groups: [ListedGroup]) -> [[String]] {
  groups.map { [$0.id, $0.label] + $0.items.map(\.id) }
}

private func shape(_ groups: [Schemas.ViewGroup]) -> [[String]] {
  groups.map { [$0.id, $0.label] + $0.itemIds }
}

@Suite("The four views draw views as sent")
struct ViewListTests {
  @Test("lists the proposal groups and items views names, in order", arguments: ViewScenario.names)
  func proposals(_ name: String) {
    let scenario = ViewScenario.load(name)
    let model = ProposalsListModel(state: scenario.state)

    #expect(model.isLoaded)
    #expect(shape(model.groups) == shape(scenario.views.proposals))
  }

  @Test("lists the three commitment tabs views names, in order", arguments: ViewScenario.names)
  func commitments(_ name: String) {
    let scenario = ViewScenario.load(name)
    let model = CommitmentsListModel(state: scenario.state)
    let tabs = scenario.views.commitments

    #expect(model.items(in: .owedByMe).map(\.id) == tabs.owedByMe)
    #expect(model.items(in: .owedToMe).map(\.id) == tabs.owedToMe)
    #expect(model.items(in: .toConfirm).map(\.id) == tabs.toConfirm)
    #expect(
      CommitmentsListModel.Tab.allCases.map(\.title) == ["Owed by me", "Owed to me", "To confirm"])
  }

  @Test(
    "lists the task sections, unit groups and items views names, in order",
    arguments: ViewScenario.names)
  func tasks(_ name: String) {
    let scenario = ViewScenario.load(name)
    let model = TasksListModel(state: scenario.state)

    #expect(model.sections.map(\.label) == scenario.views.tasks.map(\.label))
    #expect(model.sections.map(\.horizon) == scenario.views.tasks.map(\.horizon))
    for (section, sent) in zip(model.sections, scenario.views.tasks) {
      #expect(section.groups.map(\.label) == sent.groups.map(\.label))
      #expect(section.groups.map { $0.items.map(\.id) } == sent.groups.map(\.itemIds))
    }
  }

  @Test(
    "pins the alert groups the server marks pinned, and scrolls the rest",
    arguments: ViewScenario.names)
  func alerts(_ name: String) {
    let scenario = ViewScenario.load(name)
    let model = AlertsListModel(state: scenario.state)
    let sent = scenario.views.alerts

    #expect(shape(model.pinned) == shape(sent.filter { $0.pinned == true }))
    #expect(shape(model.scrolling) == shape(sent.filter { $0.pinned != true }))
  }

  @Test("pins the P0 group of the incident scenario and nothing in the others")
  func pinsP0() {
    let incident = AlertsListModel(state: ViewScenario.load("incident").state)

    #expect(!incident.pinned.isEmpty)
    #expect(incident.pinned.flatMap(\.items).allSatisfy { $0.severity == .p0 })
    #expect(AlertsListModel(state: ViewScenario.load("normal").state).pinned.isEmpty)
  }

  @Test("pins by the server's flag and not by severity")
  func pinsByFlagNotSeverity() {
    var state = ViewScenario.load("incident").state
    var views = try! #require(state.views)
    views.alerts = views.alerts.map { group in
      var group = group
      group.pinned = group.id == "P2"
      return group
    }
    state.views = views

    let model = AlertsListModel(state: state)

    #expect(model.pinned.map(\.id) == ["P2"])
    #expect(model.scrolling.map(\.id) == ["P0"])
  }

  @Test(
    "names every listed item, and no item twice, in each scenario", arguments: ViewScenario.names)
  func inventsNothing(_ name: String) {
    let state = ViewScenario.load(name).state
    let commitments = CommitmentsListModel(state: state)
    let alerts = AlertsListModel(state: state)
    var listed: [String] = ProposalsListModel(state: state).groups.flatMap(\.items).map(\.id)
    for tab in CommitmentsListModel.Tab.allCases {
      listed += commitments.items(in: tab).map(\.id)
    }
    for section in TasksListModel(state: state).sections {
      listed += section.groups.flatMap(\.items).map(\.id)
    }
    listed += (alerts.pinned + alerts.scrolling).flatMap(\.items).map(\.id)

    #expect(Set(listed).isSubset(of: Set(state.items.keys)))
    #expect(Set(listed).count == listed.count)
  }

  @Test("skips an id the store does not hold instead of inventing an item")
  func skipsUnknownIDs() {
    var state = ViewScenario.load("normal").state
    let first = try! #require(state.views?.proposals.first?.itemIds.first)
    state.items[first] = nil

    let model = ProposalsListModel(state: state)

    #expect(!model.groups.flatMap(\.items).map(\.id).contains(first))
  }

  @Test("draws an item the server has just removed, from the removals, in its place")
  func listsLeavingItems() throws {
    var state = ViewScenario.load("normal").state
    let id = try #require(state.views?.proposals.first?.itemIds.first)
    let item = try #require(state.items[id])
    state.items[id] = nil
    let removal = IanStore.Removal(item: item, outcome: "Rejected.", removedAt: Date())

    let model = ProposalsListModel(state: state, removals: [id: removal])

    let entries = try #require(model.groups.first?.entries)
    #expect(entries.first?.id == id)
    #expect(entries.first?.removal?.outcome == "Rejected.")
    #expect(entries.dropFirst().allSatisfy { $0.removal == nil })
  }

  @Test("still skips an id found in neither the items nor the removals")
  func skipsIDsInNeither() throws {
    var state = ViewScenario.load("normal").state
    let id = try #require(state.views?.proposals.first?.itemIds.first)
    state.items[id] = nil

    let model = ProposalsListModel(state: state, removals: [:])

    #expect(!model.groups.flatMap(\.items).map(\.id).contains(id))
  }

  @Test("is not loaded, and lists nothing, before the first snapshot")
  func emptyBeforeSnapshot() {
    let state = StoreState()

    #expect(!ProposalsListModel(state: state).isLoaded)
    #expect(ProposalsListModel(state: state).groups.isEmpty)
    #expect(CommitmentsListModel(state: state).items(in: .owedByMe).isEmpty)
    #expect(TasksListModel(state: state).sections.isEmpty)
    #expect(AlertsListModel(state: state).pinned.isEmpty)
  }
}

@Suite("Commitments tab keys")
struct CommitmentsTabKeyTests {
  @Test("maps Command-1, Command-2 and Command-3 to the tabs in their order")
  func digitsFollowTheTabs() {
    let tabs = CommitmentsListModel.Tab.allCases
    #expect(tabs.map(\.shortcutKey) == ["1", "2", "3"])
    #expect(tabs.map(\.title) == ["Owed by me", "Owed to me", "To confirm"])
  }
}
