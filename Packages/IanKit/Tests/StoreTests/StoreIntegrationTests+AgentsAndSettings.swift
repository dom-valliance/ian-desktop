import Auth
import Client
import Contract
import Foundation
import Testing

@testable import Store

/// These run only against a live mock server. Start it, then run
/// `IAN_MOCK_URL=http://localhost:4317 swift test --filter Integration`.
private let mockOrigin = ProcessInfo.processInfo.environment["IAN_MOCK_URL"]

private let limit = Duration.seconds(30)

/// Polls with real time, since these tests talk to a real server.
@MainActor
private func settles(_ condition: @MainActor @escaping @Sendable () -> Bool) async -> Bool {
  let end = ContinuousClock.now.advanced(by: limit)
  while ContinuousClock.now < end {
    if await MainActor.run(body: { condition() }) { return true }
    try? await Task.sleep(for: .milliseconds(50))
  }
  return false
}

private func useScenario(_ name: String, at origin: URL) async throws {
  var request = URLRequest(url: origin.appending(path: "__mock/scenario"))
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONSerialization.data(withJSONObject: ["scenario": name])
  let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
  try #require((response as? HTTPURLResponse)?.statusCode == 200)
}

/// Added to the existing integration suite, which is serialised: every test drives the one shared
/// mock, and a second suite running beside it would cut this one's stream.
extension StoreIntegrationTests {
  private var origin: URL { URL(string: mockOrigin ?? "http://localhost:4317")! }

  private func api() -> DesktopAPI {
    DesktopAPI(
      baseURL: origin.appending(path: "desktop/v1"), tokens: DevTokenProvider(),
      clientVersion: "0.1.0")
  }

  private func liveStore(scenario: String = "normal") async throws -> IanStore {
    try await useScenario(scenario, at: origin)
    let store = IanStore(
      service: api(), profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    #expect(await settles { store.connection == .live && store.state.settings != nil })
    return store
  }

  @Test("changes quiet hours and shows them when settings.updated arrives")
  func quietHoursRoundTrip() async throws {
    let store = try await liveStore()
    defer { store.stop() }

    await store.updateSettings(.init(quietHours: .init(start: "20:00", end: "06:30")))

    #expect(
      await settles {
        store.state.settings?.quietHours.start == "20:00"
          && store.state.settings?.quietHours.end == "06:30"
      })
    #expect(await settles { !store.settingsPending })
  }

  @Test("changes the push budget and shows it when settings.updated arrives")
  func pushBudgetRoundTrip() async throws {
    let store = try await liveStore()
    defer { store.stop() }

    await store.updateSettings(.init(pushBudgetPerHour: 11))

    #expect(await settles { store.state.settings?.pushBudgetPerHour == 11 })
  }

  @Test("pauses with a reason and resumes, each shown on the event")
  func ownPauseRoundTrip() async throws {
    let store = try await liveStore()
    defer { store.stop() }

    await store.updateSettings(.init(paused: true, pausedReason: "On leave"))
    #expect(
      await settles {
        store.state.settings?.paused == true && store.state.settings?.pausedReason == "On leave"
      })
    #expect(await settles { !store.settingsPending })

    await store.updateSettings(.init(paused: false))
    #expect(
      await settles {
        store.state.settings?.paused == false && store.state.settings?.pausedReason == nil
      })
  }

  @Test("shows the 422 refusal when going live is not allowed")
  func liveRefusal() async throws {
    let store = try await liveStore()
    defer { store.stop() }
    #expect(store.state.settings?.liveEligible == false)

    await store.updateSettings(.init(mode: .live))

    #expect(store.settingsNotice?.contains("Going live opens") == true)
    #expect(store.state.settings?.mode == .dryRun)
    #expect(!store.settingsPending)
  }

  @Test("goes live when eligible and returns to dry run")
  func modeRoundTrip() async throws {
    let store = try await liveStore(scenario: "quiet")
    defer { store.stop() }
    #expect(store.state.settings?.liveEligible == true)

    await store.updateSettings(.init(mode: .live))
    #expect(await settles { store.state.settings?.mode == .live })
    #expect(await settles { !store.settingsPending })

    await store.updateSettings(.init(mode: .dryRun))
    #expect(await settles { store.state.settings?.mode == .dryRun })
  }

  @Test("pauses and resumes an agent, each shown on the event")
  func agentRoundTrip() async throws {
    let store = try await liveStore()
    defer { store.stop() }
    let id = "agent_triage"
    #expect(store.state.agents.first { $0.id == id }?.state == .idle)

    await store.pause(agent: id)
    #expect(await settles { store.state.agents.first { $0.id == id }?.state == .paused })
    #expect(await settles { store.agentPending.isEmpty })

    await store.resume(agent: id)
    #expect(await settles { store.state.agents.first { $0.id == id }?.state == .idle })
  }

  @Test("answers 403 for an agent outside the principal's scope, with the server's reason")
  func forbiddenAgent() async throws {
    await #expect(
      throws: DesktopError.rejected(
        status: 403,
        detail: "Nightly median job is not yours to pause or resume. Ask an administrator.")
    ) {
      try await api().pauseAgent(id: "job_nightly_median")
    }
  }

  @Test("reads the agents in the server's order from GET /agents")
  func agentsList() async throws {
    try await useScenario("normal", at: origin)

    let overview = try await api().agents()

    #expect(overview.agents.map(\.id).first == "agent_mail_watcher")
    #expect(overview.agents.count == 6)
  }
}
