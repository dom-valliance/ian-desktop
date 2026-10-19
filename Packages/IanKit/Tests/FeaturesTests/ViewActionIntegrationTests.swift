import Auth
import Client
import Contract
import Foundation
import Store
import Testing

@testable import Features

/// These run only against a live mock server. Start it with `scripts/dev.sh --mock-only`, then
/// run `IAN_MOCK_URL=http://localhost:4317 swift test --filter Integration`.
private let mockOrigin = ProcessInfo.processInfo.environment["IAN_MOCK_URL"]

private let settleLimit = Duration.seconds(30)

private struct MockServer {
  let origin: URL

  init?(_ text: String?) {
    guard let text, let url = URL(string: text) else { return nil }
    origin = url
  }

  func loadNormalScenario() async throws {
    var request = URLRequest(url: origin.appending(path: "__mock/scenario"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(#"{"scenario":"normal"}"#.utf8)
    let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    try #require((200..<300).contains(status), "the mock answered \(status) to the scenario")
  }

  @MainActor
  func liveStore() async -> IanStore {
    let service = DesktopAPI(
      baseURL: origin.appending(path: "desktop/v1"), tokens: DevTokenProvider(),
      clientVersion: "0.1.0")
    let store = IanStore(
      service: service, profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    _ = await settles { store.connection == .live && store.state.views != nil }
    return store
  }
}

/// Polls with real time, since these tests talk to a real server.
@MainActor
private func settles(_ condition: @MainActor @escaping @Sendable () -> Bool) async -> Bool {
  let limit = ContinuousClock.now.advanced(by: settleLimit)
  while ContinuousClock.now < limit {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(25))
  }
  return false
}

/// One item of a view and each action it offers, taken from the view's own model.
private struct ActionCase: CustomTestStringConvertible, Sendable {
  let view: String
  let itemID: String
  let actionID: String
  var testDescription: String { "\(view) \(itemID) \(actionID)" }
}

@MainActor
private func actionCases(in store: IanStore) -> [ActionCase] {
  let state = store.state
  let candidates: [(view: String, item: Components.Schemas.Item?)] = [
    ("Proposals", ProposalsListModel(state: state).groups.first?.items.first),
    ("Commitments, owed by me", CommitmentsListModel(state: state).items(in: .owedByMe).first),
    ("Commitments, owed to me", CommitmentsListModel(state: state).items(in: .owedToMe).first),
    ("Commitments, to confirm", CommitmentsListModel(state: state).items(in: .toConfirm).first),
    ("Tasks", TasksListModel(state: state).sections.first?.groups.first?.items.first),
    ("Alerts", AlertsListModel(state: state).scrolling.first?.items.first),
  ]
  return candidates.flatMap { view, item in
    (item?.actions ?? []).map { ActionCase(view: view, itemID: item!.id, actionID: $0.id) }
  }
}

@Suite("View actions against the mock", .serialized, .enabled(if: mockOrigin != nil))
@MainActor
struct ViewActionIntegrationTests {
  private let mock = MockServer(mockOrigin)!

  @Test("offers an item in each of the four views in the normal scenario")
  func everyViewHasAnItem() async throws {
    try await mock.loadNormalScenario()
    let store = await mock.liveStore()
    defer { store.stop() }

    let views = Set(
      actionCases(in: store).map { $0.view.split(separator: ",").first.map(String.init) })
    #expect(views == ["Proposals", "Commitments", "Tasks", "Alerts"])
  }

  @Test("keeps each action's item pending until the server's event moves it")
  func everyActionRoundTrips() async throws {
    try await mock.loadNormalScenario()
    let listing = await mock.liveStore()
    let cases = actionCases(in: listing)
    listing.stop()
    #expect(!cases.isEmpty)

    for actionCase in cases {
      try await mock.loadNormalScenario()
      let store = await mock.liveStore()
      defer { store.stop() }
      let id = actionCase.itemID
      let before = try #require(store.state.items[id], "\(actionCase.testDescription) is missing")
      let action = try #require(before.actions.first { $0.id == actionCase.actionID })
      let cursor = store.state.lastEventID

      await store.run(
        actionID: action.id, on: id,
        until: action.input == .until ? Date().addingTimeInterval(86_400) : nil,
        note: action.input == .note ? "Following up." : nil)

      #expect(
        store.pending[id] != nil, "\(actionCase.testDescription) is not pending after the click")
      #expect(
        store.state.items[id]?.version == before.version,
        "\(actionCase.testDescription) moved on the click")
      #expect(
        store.notices[id] == nil,
        "\(actionCase.testDescription) failed: \(String(describing: store.notices[id]))")

      let cleared = await settles { store.pending[id] == nil }
      #expect(cleared, "\(actionCase.testDescription) stayed pending")
      #expect(
        (store.state.lastEventID ?? 0) > (cursor ?? 0),
        "\(actionCase.testDescription) cleared without an event")
    }
  }

  @Test("keeps a handed-over item pending until the server's event, then lets it act again")
  func handoffRoundTrips() async throws {
    try await mock.loadNormalScenario()
    let store = await mock.liveStore()
    defer { store.stop() }
    #expect(store.offersHandoff)
    let item = try #require(
      TasksListModel(state: store.state).sections.first?.groups.first?.items.first)

    await store.handOff(itemID: item.id, instruction: "Start with the agenda.")

    #expect(store.pending[item.id] != nil)
    #expect(store.notices[item.id] == nil)
    #expect(await settles { store.pending[item.id] == nil })
  }
}
