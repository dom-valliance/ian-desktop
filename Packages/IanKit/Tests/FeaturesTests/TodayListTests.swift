import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

@Suite("Today lists")
struct TodayListModelTests {
  private func model(
    removals: [String: IanStore.Removal] = [:], statuses: ItemStatuses = ItemStatuses()
  ) -> TodayListModel {
    TodayListModel(
      state: TodayScenario.state, removals: removals, statuses: statuses, at: Date())
  }

  @Test("lists the Now rows in the order the server sent, with the kind of each item")
  func nowRowsInServerOrder() {
    let rows = model().now

    #expect(rows.map(\.id) == ["alrt_b1", "prop_a1", "cmt_a2"])
    #expect(rows.map(\.kind) == [.alert, .proposal, .commitmentBy])
    #expect(rows.map(\.title) == ["Title of alrt_b1", "Title of prop_a1", "Title of cmt_a2"])
    #expect(rows.allSatisfy { !$0.isSettled })
  }

  @Test("rolls This week up into one row per unit with its item count")
  func weekRows() {
    let rows = model().week

    #expect(rows.map(\.unitName) == ["[CLIENT A]"])
    #expect(rows.map(\.itemIDs) == [["task_a3", "cmt_a4"]])
    #expect(rows.first?.kind == .task)
  }

  @Test("shows Later as counts by kind per column, each linking to the view of its kind")
  func laterRows() {
    let rows = model().later

    #expect(rows.map(\.unitName) == ["[CLIENT A]", "[CLIENT B]"])
    #expect(rows[0].counts.map(\.kind) == [.task, .proposal])
    #expect(rows[0].counts.map(\.section) == [.tasks, .proposals])
    #expect(rows[0].counts.map(\.phrase) == ["1 task", "1 proposal"])
    #expect(rows[1].counts.map(\.section) == [.tasks])
  }

  @Test("links an owed-by-you count and an owed-to-you count to Commitments")
  func commitmentCountsLinkToCommitments() {
    #expect(ItemKindStyle.section(for: .commitmentBy) == .commitments)
    #expect(ItemKindStyle.section(for: .commitmentTo) == .commitments)
    #expect(ItemKindStyle.section(for: .alert) == .alerts)
  }

  @Test(
    "keeps a removed item's dimmed row and its outcome footer after the today update that follows")
  @MainActor
  func settledRowAndOutcomeSurviveTheTodayUpdate() async {
    let (store, _, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    let model = TodayModel()
    model.select(.item("prop_a1"))

    // The server's order: the removal, then the Today that no longer lists the item. Nothing
    // refreshes between them.
    await TodayScenario.send(
      Fixtures.removedJSON("prop_a1", outcome: "Settled. Recorded on the ledger"), id: 11,
      to: feed, on: store)
    await TodayScenario.send(
      TodayScenario.todayUpdatedJSON(dropping: ["prop_a1"]), id: 12, to: feed, on: store)

    let removedAt = store.removals["prop_a1"]!.removedAt
    let rows = TodayListModel(
      state: store.state, removals: store.removals, statuses: ItemStatuses(store: store),
      at: removedAt.addingTimeInterval(0.1)
    ).now
    #expect(rows.map(\.id) == ["alrt_b1", "prop_a1", "cmt_a2"])
    #expect(rows.map(\.isSettled) == [false, true, false])

    let selection = model.resolvedSelection(in: store)
    #expect(selection == .item("prop_a1"))
    let footer = FooterContent(
      selection: selection!, state: store.state, removals: store.removals)
    #expect(footer?.trailing == .outcome("Settled. Recorded on the ledger"))
  }

  @Test("lets the dimmed row go once its pillar has finished sinking")
  @MainActor
  func settledRowLeavesWithItsPillar() async {
    let (store, _, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    await TodayScenario.send(Fixtures.removedJSON("prop_a1"), id: 11, to: feed, on: store)
    await TodayScenario.send(
      TodayScenario.todayUpdatedJSON(dropping: ["prop_a1"]), id: 12, to: feed, on: store)
    let removedAt = store.removals["prop_a1"]!.removedAt

    func rows(after seconds: TimeInterval) -> [String] {
      TodayListModel(
        state: store.state, removals: store.removals, statuses: ItemStatuses(),
        at: removedAt.addingTimeInterval(seconds)
      ).now.map(\.id)
    }

    #expect(rows(after: 0.5) == ["alrt_b1", "prop_a1", "cmt_a2"])
    #expect(rows(after: 0.8) == ["alrt_b1", "cmt_a2"])
  }

  @Test("leaves out a row whose item the store neither holds nor remembers")
  func missingItemHasNoRow() {
    var state = TodayScenario.state
    state.items["cmt_a2"] = nil

    let rows = TodayListModel(state: state, removals: [:], statuses: ItemStatuses(), at: Date()).now

    #expect(rows.map(\.id) == ["alrt_b1", "prop_a1"])
  }

  @Test("labels a row with its kind, title and horizon for VoiceOver")
  func rowLabels() {
    let list = model()

    #expect(list.now[0].accessibilityLabel == "Alert, Title of alrt_b1, now")
    #expect(list.now[2].accessibilityLabel == "Owed by you, Title of cmt_a2, now")
    #expect(list.week[0].accessibilityLabel == "This week, [CLIENT A], 2 items")
    #expect(list.later[0].accessibilityLabel == "Later, [CLIENT A], 1 task, 1 proposal")
  }

  @Test("says when an agent is working on an item, before any pending state")
  func workingLabel() {
    var state = TodayScenario.state
    state.items["prop_a1"]?.working = true

    let rows = TodayListModel(
      state: state, removals: [:], statuses: ItemStatuses(pending: ["prop_a1"]), at: Date()
    ).now

    #expect(
      rows[1].accessibilityLabel == "Proposal, Title of prop_a1, now, being worked on, pending")
  }

  @Test("adds pending, error and changed states to a row's label")
  func rowLabelsCarryState() {
    let statuses = ItemStatuses(
      pending: ["prop_a1"], notices: ["cmt_a2": .failed("Not allowed."), "alrt_b1": .changed])

    let rows = model(statuses: statuses).now

    #expect(rows[0].accessibilityLabel == "Alert, Title of alrt_b1, now, changed")
    #expect(rows[1].accessibilityLabel == "Proposal, Title of prop_a1, now, pending")
    #expect(rows[2].accessibilityLabel == "Owed by you, Title of cmt_a2, now, error: Not allowed.")
  }

  @Test("labels a settled row as settled")
  func settledRowLabel() {
    var state = TodayScenario.state
    let removed = state.items.removeValue(forKey: "prop_a1")!

    let rows = TodayListModel(
      state: state, removals: ["prop_a1": .make(removed, outcome: nil)], statuses: ItemStatuses(),
      at: Date()
    ).now

    #expect(rows[1].accessibilityLabel == "Proposal, Title of prop_a1, now, settled")
  }

  @Test("has no rows before the first snapshot")
  func emptyBeforeSnapshot() {
    let list = TodayListModel(
      state: StoreState(), removals: [:], statuses: ItemStatuses(), at: Date())
    #expect(list.now.isEmpty && list.week.isEmpty && list.later.isEmpty)
  }
}

@Suite("Selection footer")
struct FooterContentTests {
  private let state = TodayScenario.state

  @Test("names the kind, unit and horizon, then the title and meta, for an item")
  func itemFooter() {
    let footer = FooterContent(selection: .item("cmt_a2"), state: state, removals: [:])

    #expect(footer?.kicker == "OWED BY YOU / [CLIENT A] / NOW")
    #expect(footer?.title == "Title of cmt_a2")
    #expect(footer?.meta == "Meta of cmt_a2")
    #expect(footer?.trailing == .actions)
  }

  @Test("shows the outcome line instead of actions for a removed item")
  func removedItemFooter() {
    var state = state
    let removed = state.items.removeValue(forKey: "prop_a1")!

    let footer = FooterContent(
      selection: .item("prop_a1"), state: state,
      removals: ["prop_a1": .make(removed, outcome: "Settled. Recorded on the ledger")])

    #expect(footer?.kicker == "PROPOSAL / [CLIENT A] / NOW")
    #expect(footer?.trailing == .outcome("Settled. Recorded on the ledger"))
  }

  @Test("has no footer for an item the store neither holds nor remembers")
  func goneItemHasNoFooter() {
    #expect(FooterContent(selection: .item("task_unknown"), state: state, removals: [:]) == nil)
  }

  @Test("lists the items of a week group, in the order sent")
  func weekGroupFooter() {
    let footer = FooterContent(selection: .week(unitID: "unit_a"), state: state, removals: [:])

    #expect(footer?.kicker == "ROLLED UP / [CLIENT A] / THIS WEEK")
    #expect(footer?.title == "[CLIENT A]")
    #expect(footer?.meta == "2 items")
    #expect(footer?.trailing == .members(["task_a3", "cmt_a4"]))
  }

  @Test("summarises a later group by kind and links each count to its view")
  func laterGroupFooter() {
    let footer = FooterContent(selection: .later(unitID: "unit_a"), state: state, removals: [:])

    #expect(footer?.meta == "1 task, 1 proposal")
    guard case .counts(let counts)? = footer?.trailing else {
      Issue.record("A later group's footer carries its counts.")
      return
    }
    #expect(counts.map(\.section) == [.tasks, .proposals])
  }
}

extension IanStore.Removal {
  fileprivate static func make(_ item: Components.Schemas.Item, outcome: String?) -> Self {
    Self(item: item, outcome: outcome, removedAt: Date(), nowListIndex: nil)
  }
}
