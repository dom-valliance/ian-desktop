import AppKit
import Client
import Contract
import SnapshotTesting
import Store
import SwiftUI
import TestSupport
import Testing

@testable import Features

/// The four views drawn from the scenario fixtures at 640 by 720 points, through the
/// views the app uses. Each is hosted in an `NSHostingView` that never enters a window, since
/// the pickers and fields are AppKit controls that `ImageRenderer` would draw as placeholders.
@Suite("View snapshots")
@MainActor
struct ViewSnapshotTests {
  private static let size = CGSize(width: 640, height: 720)

  /// A store that has loaded the snapshot, with its stream live. Card dates follow the fixture's
  /// `me.timeZone`, so they agree with the server's meta lines. The caller stops it.
  private func liveStore(_ snapshot: Components.Schemas.Snapshot, me: Components.Schemas.Me)
    async -> IanStore
  {
    let store = IanStore(
      service: ScriptedService(me: me, snapshots: [.success(snapshot)]), profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    _ = await eventually("live") {
      await MainActor.run { store.connection == .live && store.state.views != nil }
    }
    return store
  }

  private func scenarioStore(_ name: String) async -> IanStore {
    let scenario = ViewScenario.load(name)
    var snapshot = Fixtures.snapshot()
    snapshot.today = scenario.today
    snapshot.views = scenario.views
    snapshot.items = scenario.items
    return await liveStore(snapshot, me: scenario.me)
  }

  private func emptyStore() async -> IanStore {
    await liveStore(Fixtures.snapshot(items: []), me: Fixtures.me())
  }

  private func image(of view: some View, size: CGSize = Self.size) -> NSImage {
    let hosting = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height)
        .background(ClientPalette.ground).foregroundStyle(ClientPalette.text)
        .environment(\.colorScheme, .dark))
    hosting.appearance = NSAppearance(named: .darkAqua)
    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
      preconditionFailure("The view did not produce a bitmap.")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }

  private func check(_ image: NSImage, named name: String) {
    assertSnapshot(
      of: image, as: .image(precision: 0.998, perceptualPrecision: 0.98), named: name,
      testName: "views")
  }

  @Test("draws Proposals in normal")
  func proposals() async {
    let store = await scenarioStore("normal")
    defer { store.stop() }
    check(image(of: ProposalsView(store: store)), named: "proposals-normal")
  }

  @Test("draws each Commitments tab in normal", arguments: CommitmentsListModel.Tab.allCases)
  func commitments(tab: CommitmentsListModel.Tab) async {
    let store = await scenarioStore("normal")
    defer { store.stop() }
    check(
      image(of: CommitmentsView(store: store, tab: tab)),
      named: "commitments-normal-\(tab.rawValue)"
    )
  }

  @Test("draws Tasks in normal")
  func tasks() async {
    let store = await scenarioStore("normal")
    defer { store.stop() }
    check(image(of: TasksView(store: store)), named: "tasks-normal")
  }

  @Test("draws Alerts in incident with the P0 group pinned, and in normal without one")
  func alerts() async {
    let incident = await scenarioStore("incident")
    defer { incident.stop() }
    check(image(of: AlertsView(store: incident)), named: "alerts-incident")
    let normal = await scenarioStore("normal")
    defer { normal.stop() }
    check(image(of: AlertsView(store: normal)), named: "alerts-normal")
  }

  @Test("draws the empty states")
  func emptyStates() async {
    let store = await emptyStore()
    defer { store.stop() }
    check(image(of: ProposalsView(store: store)), named: "proposals-empty")
    check(image(of: CommitmentsView(store: store)), named: "commitments-empty")
    check(image(of: TasksView(store: store)), named: "tasks-empty")
    check(image(of: AlertsView(store: store)), named: "alerts-empty")
    let quiet = await scenarioStore("quiet")
    defer { quiet.stop() }
    check(image(of: AlertsView(store: quiet)), named: "alerts-quiet")
    check(
      image(of: CommitmentsView(store: quiet, tab: .owedToMe)),
      named: "commitments-quiet-owed-to-me")
  }

  @Test("draws a card whose actions have invented ids and labels as exactly those buttons")
  func inventedActions() async throws {
    let actions: [Fixtures.ActionSpec] = [
      .init("qq_9"), .init("aa_1", input: "note"), .init("mm_5", input: "until"),
    ]
    let snapshot = Fixtures.snapshot(items: [Fixtures.itemJSON(id: "task_1", actions: actions)])
    let store = await liveStore(snapshot, me: Fixtures.me())
    defer { store.stop() }
    let item = try #require(store.state.items["task_1"])
    check(
      image(
        of: ItemCardView(store: store, entry: ListedItem(item: item, removal: nil)).padding(20),
        size: CGSize(width: 640, height: 260)),
      named: "card-invented-actions")
  }
}
