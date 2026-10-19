import Auth
import Contract
import Foundation
import OpenAPIRuntime
import TestSupport
import Testing

@testable import Client

// MARK: Versions and backoff

@Test("compares versions by number, so 0.10.0 is above 0.9.0")
private func comparesVersionsNumerically() throws {
  let low = try #require(SemanticVersion("0.9.0"))
  let high = try #require(SemanticVersion("0.10.0"))

  #expect(low < high)
  #expect(SemanticVersion("1") == SemanticVersion(major: 1, minor: 0, patch: 0))
  #expect(SemanticVersion("1.2.3.4") == nil)
  #expect(SemanticVersion("1.x") == nil)
}

@Test("keeps every backoff delay within half the ceiling and the 30 second cap", arguments: 0...12)
private func backoffStaysWithinBounds(attempt: Int) {
  let backoff = Backoff()
  let ceiling = min(Duration.seconds(30), .seconds(1) * Double(1 << attempt))

  for jitter in [0.0, 0.25, 0.5, 1.0] {
    let delay = backoff.delay(attempt: attempt, jitter: jitter)
    #expect(delay >= ceiling * 0.5)
    #expect(delay <= ceiling)
    #expect(delay <= .seconds(30))
  }
}

@Test("doubles the backoff ceiling until it reaches the cap")
private func backoffDoubles() {
  let backoff = Backoff()

  #expect(backoff.delay(attempt: 0, jitter: 1) == .seconds(1))
  #expect(backoff.delay(attempt: 1, jitter: 1) == .seconds(2))
  #expect(backoff.delay(attempt: 3, jitter: 1) == .seconds(8))
  #expect(backoff.delay(attempt: 9, jitter: 1) == .seconds(30))
}

// MARK: Profiles

@Test("starts on the mock profile when nothing names an environment")
private func defaultsToMock() throws {
  let profile = try EnvironmentProfile.resolve(requested: nil, info: [:])

  #expect(profile == .mock)
  #expect(profile.baseURL.absoluteString == "http://localhost:4317/desktop/v1")
  #expect(profile.signIn == .devToken)
}

@Test("points lance-dev at the dev api host and reads its sign-in settings from Info.plist")
private func lanceDevReadsConfiguration() throws {
  let info: [String: Any] = [
    "IanLanceTenantID": "tenant-1", "IanLanceClientID": "client-1", "IanLanceScope": "api://x/y",
  ]

  let profile = try EnvironmentProfile.resolve(requested: "lance-dev", info: info)

  #expect(
    profile.baseURL.absoluteString
      == "https://ca-lance-api-dev.graygrass-c682ce2c.uksouth.azurecontainerapps.io/desktop/v1")
  #expect(
    profile.signIn
      == .entra(EntraConfiguration(tenantID: "tenant-1", clientID: "client-1", scope: "api://x/y")))
  #expect(profile.displayName == "Lance dev")
  #expect(!profile.isMock)
}

@Test("leaves unset lance-dev settings empty so sign-in names them")
private func lanceDevLeavesMissingSettingsEmpty() throws {
  let profile = try EnvironmentProfile.resolve(
    requested: "lance-dev", info: ["IanLanceTenantID": "tenant-1"])

  guard case .entra(let configuration) = profile.signIn else {
    Issue.record("lance-dev must sign in with Entra")
    return
  }
  #expect(configuration.clientID.isEmpty)
  #expect(configuration.scope.isEmpty)
}

@Test("rejects an unknown profile name and lists the known ones")
private func rejectsUnknownProfile() {
  let error = #expect(throws: EnvironmentProfile.ResolutionError.self) {
    try EnvironmentProfile.resolve(requested: "production", info: [:])
  }

  #expect(error?.errorDescription?.contains("mock, lance-dev") == true)
}

@Test("uses one Keychain service per profile")
private func keychainServicePerProfile() {
  let lanceDev = EnvironmentProfile.lanceDev(
    entra: EntraConfiguration(tenantID: "", clientID: "", scope: ""))

  #expect(
    lanceDev.keychainService(bundleIdentifier: "ai.valliance.ian.desktop")
      == "ai.valliance.ian.desktop.lance-dev")
  #expect(
    EnvironmentProfile.mock.keychainService(bundleIdentifier: "ai.valliance.ian.desktop")
      == "ai.valliance.ian.desktop.mock")
}

// MARK: Stream decoding

private func sse(_ id: String?, _ event: String?, _ data: String?) -> ServerSentEvent {
  ServerSentEvent(id: id, event: event, data: data)
}

@Test("decodes a known event, with times in UTC and milliseconds")
private func decodesKnownEvent() throws {
  let message = StreamMessageDecoder().message(
    for: sse("42", "item.upserted", Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_9"))))

  guard case .event(let id, .item_upserted(let upserted)) = message else {
    Issue.record("expected item.upserted, got \(message)")
    return
  }
  #expect(id == "42")
  #expect(upserted.item.id == "task_9")
  #expect(upserted.item.dueAt == Date(timeIntervalSince1970: 1_792_170_000))
}

@Test("carries no id for a heartbeat")
private func heartbeatHasNoID() {
  let message = StreamMessageDecoder().message(
    for: sse(nil, "heartbeat", Fixtures.heartbeatJSON))

  #expect(message == .event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))
}

@Test("ignores an event type it does not know")
private func ignoresUnknownType() {
  let message = StreamMessageDecoder().message(
    for: sse("7", "pillar.sunk", "{\"type\":\"pillar.sunk\"}"))

  #expect(message == .ignored)
}

@Test("ignores a message with no event field")
private func ignoresMessageWithoutEvent() {
  #expect(StreamMessageDecoder().message(for: sse("7", nil, "{}")) == .ignored)
}

@Test("reports a known type whose data does not decode, so the client refetches")
private func reportsUndecodableKnownType() {
  #expect(
    StreamMessageDecoder().message(for: sse("8", "item.upserted", "{\"type\":\"item.upserted\"}"))
      == .undecodable)
  #expect(StreamMessageDecoder().message(for: sse("9", "item.removed", "not json")) == .undecodable)
}

// MARK: HTTP

private func api(
  tokens: any TokenProvider = DevTokenProvider(),
  handler: @escaping StubURLProtocol.Handler
) -> DesktopAPI {
  let stub = StubURLProtocol.session(handler: handler)
  return DesktopAPI(
    baseURL: URL(string: "https://stub.test/desktop/v1")!, tokens: tokens, clientVersion: "0.1.0",
    session: stub.session)
}

private final class Captured: @unchecked Sendable {
  // `requests` is read and written only while holding `lock`.
  private let lock = NSLock()
  private var requests: [URLRequest] = []
  private var bodies: [String] = []
  func record(_ request: URLRequest) {
    lock.withLock {
      requests.append(request)
      bodies.append(bodyText(of: request))
    }
  }
  var all: [URLRequest] { lock.withLock { requests } }
  var allBodies: [String] { lock.withLock { bodies } }
}

@Test("sends the bearer and the client version on every request")
private func sendsHeaders() async throws {
  let captured = Captured()
  let service = api { request in
    captured.record(request)
    return .json(Fixtures.meJSON())
  }

  let me = try await service.me()

  #expect(me.principalId == "prin_1")
  let request = try #require(captured.all.first)
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dev-local")
  #expect(request.value(forHTTPHeaderField: "Desktop-Client-Version") == "0.1.0")
  #expect(request.url?.path == "/desktop/v1/me")
}

@Test("decodes a snapshot whose times carry milliseconds")
private func decodesSnapshot() async throws {
  let service = api { _ in .json(Fixtures.snapshotJSON(cursor: "55")) }

  let snapshot = try await service.snapshot()

  #expect(snapshot.cursor == "55")
  #expect(snapshot.items.count == 1)
  #expect(snapshot.serverTime == Date(timeIntervalSince1970: 1_792_137_600))
}

@Test("maps 401 to unauthorised")
private func mapsUnauthorised() async {
  let service = api { _ in
    .problem("{\"type\":\"about:blank\",\"title\":\"No\",\"status\":401}", status: 401)
  }

  await #expect(throws: DesktopError.unauthorised) { try await service.snapshot() }
}

@Test("maps 426 to upgradeRequired with the minimum version")
private func mapsUpgradeRequired() async {
  let service = api { _ in
    .problem(
      "{\"type\":\"about:blank\",\"title\":\"Upgrade\",\"status\":426,\"minClientVersion\":\"0.4.0\"}",
      status: 426)
  }

  await #expect(throws: DesktopError.upgradeRequired(minClientVersion: "0.4.0")) {
    try await service.me()
  }
}

@Test("maps an unreachable server to offline")
private func mapsOffline() async {
  let service = api { _ in StubResponse(failure: URLError(.cannotConnectToHost)) }

  await #expect(throws: DesktopError.offline) { try await service.snapshot() }
}

@Test("treats a missing token as unauthorised without sending the request")
private func missingTokenIsUnauthorised() async {
  struct NoToken: TokenProvider {
    func token() async throws -> String { throw AuthError.signInRequired }
    func signIn() async throws {}
    func signOut() async {}
  }
  let captured = Captured()
  let service = api(tokens: NoToken()) { request in
    captured.record(request)
    return .json(Fixtures.meJSON())
  }

  await #expect(throws: DesktopError.unauthorised) { try await service.me() }
  #expect(captured.all.isEmpty)
}

@Test("posts the action with the item version and the input it was given")
private func postsAction() async throws {
  let captured = Captured()
  let service = api { request in
    captured.record(request)
    return .json("{\"correlationId\":\"corr_7\"}", status: 202)
  }
  let until = Date(timeIntervalSince1970: 1_792_137_600)

  let correlationID = try await service.runAction(
    itemID: "task_1", actionID: "snooze", version: 4, until: until, note: nil)

  #expect(correlationID == "corr_7")
  let request = try #require(captured.all.first)
  #expect(request.httpMethod == "POST")
  #expect(request.url?.path == "/desktop/v1/items/task_1/actions/snooze")
  let body = try #require(captured.allBodies.first)
  let fields = try #require(
    try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
  #expect(fields["version"] as? Int == 4)
  #expect(fields["until"] as? String == "2026-10-16T08:00:00.000Z")
  #expect(fields["note"] == nil)
}

@Test("maps 409 to a conflict that carries the item as the server now holds it")
private func mapsConflictWithCurrentItem() async throws {
  let service = api { _ in
    .problem(
      "{\"type\":\"about:blank\",\"title\":\"Changed\",\"status\":409,\"item\":"
        + Fixtures.itemJSON(id: "task_1", version: 9) + "}",
      status: 409)
  }

  let error = await #expect(throws: DesktopError.self) {
    try await service.runAction(
      itemID: "task_1", actionID: "done", version: 1, until: nil, note: nil)
  }

  guard case .conflict(let item) = error else {
    Issue.record("expected a conflict, got \(String(describing: error))")
    return
  }
  #expect(item.version == 9)
}

@Test("resumes the stream from Last-Event-ID and skips events of unknown types")
private func streamResumesAndSkipsUnknownTypes() async throws {
  let captured = Captured()
  let body =
    Fixtures.sse(
      id: "11", event: "item.removed", data: Fixtures.removedJSON("task_1"))
    + Fixtures.sse(id: "12", event: "pillar.sunk", data: "{\"type\":\"pillar.sunk\"}")
    + Fixtures.sse(id: nil, event: "heartbeat", data: Fixtures.heartbeatJSON)
    + Fixtures.sse(id: "13", event: "item.upserted", data: "{\"type\":\"item.upserted\"}")
  let service = api { request in
    captured.record(request)
    return .eventStream(body)
  }

  var messages: [StreamMessage] = []
  for try await message in try await service.stream(lastEventID: "10") {
    messages.append(message)
  }

  #expect(captured.all.first?.value(forHTTPHeaderField: "Last-Event-ID") == "10")
  #expect(messages.count == 4)
  #expect(messages[0] == .event(id: "11", Fixtures.event(Fixtures.removedJSON("task_1"))))
  #expect(messages[1] == .ignored)
  #expect(messages[2] == .event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))
  #expect(messages[3] == .undecodable)
}

@Test("opens the stream without Last-Event-ID when no cursor is given")
private func streamWithoutCursor() async throws {
  let captured = Captured()
  let service = api { request in
    captured.record(request)
    return .eventStream("")
  }

  for try await _ in try await service.stream(lastEventID: nil) {}

  #expect(captured.all.first?.value(forHTTPHeaderField: "Last-Event-ID") == nil)
}

@Test("maps 410 on the stream to gone")
private func streamGone() async {
  let service = api { _ in
    .problem("{\"type\":\"about:blank\",\"title\":\"Gone\",\"status\":410}", status: 410)
  }

  await #expect(throws: DesktopError.gone) { try await service.stream(lastEventID: "1") }
}

@Test("knows exactly the event types the contract's StreamEvent declares")
private func knownTypesMatchContract() {
  typealias Schemas = Components.Schemas
  let declared = Set(
    Schemas.ItemUpsertedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.ItemRemovedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.TodayUpdatedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.ViewsUpdatedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.AlertRaisedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.AlertClearedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.AgentUpdatedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.SettingsUpdatedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.ClientDeprecatedEvent._TypePayload.allCases.map(\.rawValue)
      + Schemas.HeartbeatEvent._TypePayload.allCases.map(\.rawValue))

  #expect(StreamMessageDecoder.knownTypes == declared)
}

/// Hands an output stream to the writing thread. Safe because only that thread touches it after
/// the hand-off.
private final class LateWriter: @unchecked Sendable {
  let stream: OutputStream
  let bytes: [UInt8]

  init(stream: OutputStream, bytes: [UInt8]) {
    self.stream = stream
    self.bytes = bytes
  }

  func write(after delay: TimeInterval) {
    Thread.detachNewThread {
      self.stream.open()
      Thread.sleep(forTimeInterval: delay)
      _ = self.bytes.withUnsafeBufferPointer {
        self.stream.write($0.baseAddress!, maxLength: $0.count)
      }
      self.stream.close()
    }
  }
}

@Test("reads a request body that is still arriving when loading starts")
private func readsLateBody() {
  var input: InputStream?
  var output: OutputStream?
  Stream.getBoundStreams(withBufferSize: 4096, inputStream: &input, outputStream: &output)
  var request = URLRequest(url: URL(string: "https://stub.test/body")!)
  request.httpBodyStream = input
  LateWriter(stream: output!, bytes: Array("{\"version\":4}".utf8)).write(after: 0.05)

  #expect(bodyText(of: request) == "{\"version\":4}")
}

// MARK: Agents and settings

private let forbiddenProblem =
  "{\"type\":\"about:blank\",\"title\":\"Outside your scope\",\"status\":403,"
  + "\"detail\":\"Inbox watcher is not yours to pause.\"}"

@Test("reads the agents and today's cost in the server's order")
private func readsAgents() async throws {
  let captured = Captured()
  let service = api { request in
    captured.record(request)
    return .json(
      "{\"agents\":[\(Fixtures.agentJSON(id: "b")),\(Fixtures.agentJSON(id: "a"))],"
        + "\"costToday\":\(Fixtures.costJSON())}")
  }

  let overview = try await service.agents()

  #expect(overview.agents.map(\.id) == ["b", "a"])
  #expect(captured.all.first?.url?.path == "/desktop/v1/agents")
}

@Test("posts a pause and a resume to the agent's own path")
private func postsPauseAndResume() async throws {
  let captured = Captured()
  let service = api { request in
    captured.record(request)
    return .json(Fixtures.agentJSON(id: "agent_1", state: "paused"))
  }

  let paused = try await service.pauseAgent(id: "agent_1")
  _ = try await service.resumeAgent(id: "agent_1")

  #expect(paused.state == .paused)
  #expect(
    captured.all.map { $0.url?.path } == [
      "/desktop/v1/agents/agent_1/pause", "/desktop/v1/agents/agent_1/resume",
    ])
  #expect(captured.all.allSatisfy { $0.httpMethod == "POST" })
}

@Test("maps 403 on a pause to a refusal carrying the server's detail")
private func mapsForbiddenPause() async {
  let service = api { _ in .problem(forbiddenProblem, status: 403) }

  await #expect(
    throws: DesktopError.rejected(status: 403, detail: "Inbox watcher is not yours to pause.")
  ) {
    try await service.pauseAgent(id: "agent_1")
  }
}

@Test("patches only the fields it was given")
private func patchesOnlyGivenFields() async throws {
  let captured = Captured()
  let service = api { request in
    captured.record(request)
    return .json(Fixtures.settingsJSON(pushBudget: 9))
  }

  let settings = try await service.updateSettings(
    .init(quietHours: .init(start: "20:00", end: "06:30"), paused: true, pausedReason: "Leave"))

  #expect(settings.pushBudgetPerHour == 9)
  let request = try #require(captured.all.first)
  #expect(request.httpMethod == "PATCH")
  #expect(request.url?.path == "/desktop/v1/settings")
  let text = try #require(captured.allBodies.first)
  let fields = try #require(
    try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  #expect(Set(fields.keys) == ["quietHours", "paused", "pausedReason"])
  #expect(fields["paused"] as? Bool == true)
}

@Test("maps 422 on a settings change to a refusal carrying the server's detail")
private func mapsRefusedSettings() async {
  let service = api { _ in
    .problem(
      "{\"type\":\"about:blank\",\"title\":\"Not eligible\",\"status\":422,"
        + "\"detail\":\"Going live opens on 23 October.\"}", status: 422)
  }

  await #expect(
    throws: DesktopError.rejected(status: 422, detail: "Going live opens on 23 October.")
  ) {
    try await service.updateSettings(.init(mode: .live))
  }
}
