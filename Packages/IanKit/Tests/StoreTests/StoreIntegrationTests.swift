import Auth
import Client
import Foundation
import Testing

@testable import Store

/// These run only against a live mock server (D2). Start it, then run
/// `IAN_MOCK_URL=http://localhost:4317 swift test --filter Integration`.
let mockOrigin = ProcessInfo.processInfo.environment["IAN_MOCK_URL"]

let integrationTimeout = Duration.seconds(30)

struct MockServer {
  let origin: URL

  init?(_ text: String?) {
    guard let text, let url = URL(string: text) else { return nil }
    origin = url
  }

  func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
    var request = URLRequest(url: origin.appending(path: path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    try #require((200..<300).contains(status), "POST \(path) answered \(status)")
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  /// A read of `path` with the development token, as the app's own requests carry it.
  func get(_ path: String) async throws -> [String: Any] {
    var request = URLRequest(url: origin.appending(path: path))
    request.setValue("Bearer \(DevTokenProvider.bearerToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    try #require((200..<300).contains(status), "GET \(path) answered \(status)")
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  func use(scenario: String) async throws {
    _ = try await post("__mock/scenario", ["scenario": scenario])
  }

  @MainActor
  func startStore() -> IanStore {
    let service = DesktopAPI(
      baseURL: origin.appending(path: "desktop/v1"), tokens: DevTokenProvider(),
      clientVersion: "0.1.0")
    let store = IanStore(
      service: service, profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    return store
  }
}

/// Polls with real time, since these tests talk to a real server.
@MainActor
func settles(
  _ description: String, _ condition: @MainActor @escaping @Sendable () -> Bool
) async -> Bool {
  let limit = ContinuousClock.now.advanced(by: integrationTimeout)
  while ContinuousClock.now < limit {
    if await MainActor.run(body: { condition() }) { return true }
    try? await Task.sleep(for: .milliseconds(50))
  }
  return false
}

/// Serialised because every test drives the one shared mock, and switching it to `offline` in one
/// test would cut another's stream.
@Suite("Mock integration", .serialized, .enabled(if: mockOrigin != nil))
@MainActor
struct StoreIntegrationTests {
  let mock = MockServer(mockOrigin)!

  @Test("shows the normal scenario arriving, live, with its items and Today")
  func normalScenarioArrives() async throws {
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    defer { store.stop() }

    #expect(
      await settles("the snapshot") { store.connection == .live && !store.state.items.isEmpty })

    #expect(store.state.today != nil)
    #expect(store.state.views != nil)
    #expect(store.state.settings != nil)
    #expect(!store.state.agents.isEmpty)
    #expect(store.state.me != nil)
  }

  @Test("applies an event the mock emits")
  func emittedEventIsApplied() async throws {
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    defer { store.stop() }
    #expect(await settles("live") { store.connection == .live })

    let emitted = try await mock.post("__mock/emit", ["recipe": "alert", "severity": "P1"])
    let itemID = try #require(emitted["itemId"] as? String)

    #expect(await settles("the alert") { store.state.items[itemID] != nil })
  }

  @Test("recovers after the stream is killed and applies events that follow")
  func recoversAfterStreamIsKilled() async throws {
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    defer { store.stop() }
    #expect(await settles("live") { store.connection == .live })

    try await mock.use(scenario: "offline")
    #expect(await settles("offline") { store.connection == .offline })
    // D2's offline scenario closes open streams and destroys every /desktop/v1 connection, and
    // loading it publishes the diff from the previous world first, so only presence of data
    // is asserted, not which items remain.
    #expect(store.state.today != nil)
    #expect(!store.actionsEnabled)

    try await mock.use(scenario: "normal")
    #expect(await settles("live again") { store.connection == .live })
    let emitted = try await mock.post("__mock/emit", ["recipe": "alert", "severity": "P1"])
    let itemID = try #require(emitted["itemId"] as? String)

    #expect(await settles("the alert after recovery") { store.state.items[itemID] != nil })
  }
}
