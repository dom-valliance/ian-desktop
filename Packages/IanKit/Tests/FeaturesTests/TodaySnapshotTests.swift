import AppKit
import Client
import Contract
import Foundation
import Store
import SwiftUI
import TestSupport
import Testing

@testable import Features

/// Today's lists and the selection footer drawn from the scenario fixtures, as Today stacks them
/// under the field: the three lists, a rule, then the footer. The field is not drawn here; the
/// Pillars snapshots cover it.
@Suite("Today snapshots")
@MainActor
struct TodaySnapshotTests {
  private static let size = CGSize(width: 640, height: 720)
  private nonisolated static let now = Date(timeIntervalSince1970: 1_792_137_600)

  private struct Harness {
    let store: IanStore
    let feed: TodayScenario.Feed
    let scenario: ViewScenario
  }

  /// A store that has loaded the scenario with its stream live, at a fixed clock. The caller
  /// stops it.
  private func harness(_ name: String) async -> Harness {
    let scenario = ViewScenario.load(name)
    var snapshot = Fixtures.snapshot()
    snapshot.today = scenario.today
    snapshot.views = scenario.views
    snapshot.items = scenario.items
    let service = ScriptedService(me: scenario.me, snapshots: [.success(snapshot)])
    let feed = service.planStream()
    let store = IanStore(
      service: service, profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0),
      now: { Self.now })
    store.start()
    _ = await eventually("live") {
      await MainActor.run { store.connection == .live && store.state.views != nil }
    }
    return Harness(store: store, feed: feed, scenario: scenario)
  }

  private func lower(
    _ store: IanStore, selection: TodaySelection?, at time: Date = TodaySnapshotTests.now,
    keys: FooterKeys = FooterKeys()
  ) -> some View {
    VStack(spacing: 0) {
      TodayListsView(
        list: TodayListModel(
          state: store.state, removals: store.removals, statuses: ItemStatuses(store: store),
          at: time),
        hasToday: store.state.today != nil, selection: .constant(selection))
      Divider().overlay(ClientPalette.line)
      SelectionFooter(
        store: store, selection: selection, onSelect: { _ in }, onNavigate: { _ in },
        keys: keys)
    }
  }

  private func check(_ view: some View, named name: String) {
    SnapshotHarness.check(
      SnapshotHarness.image(of: view, size: Self.size, inWindow: true), named: name,
      testName: "today")
  }

  @Test("draws the lists with nothing selected in each scenario", arguments: ScenarioFixtures.names)
  func unselected(scenario: String) async {
    let harness = await harness(scenario)
    defer { harness.store.stop() }
    check(lower(harness.store, selection: nil), named: "lists-\(scenario)")
  }

  @Test("draws the footer for a Now item with its actions in the order sent")
  func itemSelected() async throws {
    let harness = await harness("normal")
    defer { harness.store.stop() }
    let id = try #require(harness.scenario.today.lists.now.first)
    check(lower(harness.store, selection: .item(id)), named: "footer-item")
  }

  @Test("draws the footer for a rolled-up week group, then for a later group")
  func groupSelected() async throws {
    let harness = await harness("normal")
    defer { harness.store.stop() }
    let week = try #require(harness.scenario.today.lists.week.first)
    check(lower(harness.store, selection: .week(unitID: week.unitId)), named: "footer-week")
    let later = try #require(harness.scenario.today.lists.later.first)
    check(lower(harness.store, selection: .later(unitID: later.unitId)), named: "footer-later")
  }

  @Test("draws a removed item's dimmed row and its outcome line in the footer")
  func removedItem() async throws {
    let harness = await harness("normal")
    defer { harness.store.stop() }
    let id = try #require(harness.scenario.today.lists.now.first)
    await TodayScenario.send(
      Fixtures.removedJSON(id, outcome: "Approved. Recorded on the ledger"), id: 11,
      to: harness.feed, on: harness.store)
    check(
      lower(harness.store, selection: .item(id), at: Self.now.addingTimeInterval(0.1)),
      named: "footer-removed")
  }

  @Test("draws the keyboard highlight on the second action, and on a week group's second member")
  func keyboardHighlight() async throws {
    let harness = await harness("normal")
    defer { harness.store.stop() }
    let id = try #require(harness.scenario.today.lists.now.first)
    let keys = FooterKeys()
    keys.setTargetCount(2)
    keys.pressReturn()
    keys.move(1)
    check(lower(harness.store, selection: .item(id), keys: keys), named: "footer-item-keyboard")

    let week = try #require(harness.scenario.today.lists.week.first)
    let groupKeys = FooterKeys()
    groupKeys.setTargetCount(2)
    groupKeys.pressReturn()
    groupKeys.move(1)
    check(
      lower(harness.store, selection: .week(unitID: week.unitId), keys: groupKeys),
      named: "footer-week-keyboard")
  }
}
