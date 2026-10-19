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
    "lists the alert groups views names, in order, with P0 pinned", arguments: ViewScenario.names)
  func alerts(_ name: String) {
    let scenario = ViewScenario.load(name)
    let model = AlertsListModel(state: scenario.state)

    #expect(shape(model.pinned + model.scrolling) == shape(scenario.views.alerts))
    #expect(model.pinned.allSatisfy { $0.items.allSatisfy { $0.severity == .p0 } })
    #expect(model.scrolling.allSatisfy { $0.items.allSatisfy { $0.severity != .p0 } })
  }

  @Test("pins the P0 group of the incident scenario and nothing in the others")
  func pinsP0() {
    #expect(!AlertsListModel(state: ViewScenario.load("incident").state).pinned.isEmpty)
    #expect(AlertsListModel(state: ViewScenario.load("normal").state).pinned.isEmpty)
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
