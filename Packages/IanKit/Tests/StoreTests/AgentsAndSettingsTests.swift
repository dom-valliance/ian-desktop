import Client
import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

private let serverNow = Date(timeIntervalSince1970: 1_792_137_600)

@MainActor
private func makeStore(_ service: ScriptedService, now: Date = serverNow) -> IanStore {
  IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
    jitter: { 1 }, now: { now })
}

@MainActor
private func waitUntil(
  _ description: String, _ condition: @MainActor @escaping @Sendable () -> Bool
) async -> Bool {
  await eventually(description) { await MainActor.run { condition() } }
}

private typealias Feed = AsyncThrowingStream<StreamMessage, any Error>.Continuation

@MainActor
private func liveStore(
  agents: [Fixtures.Schemas.Agent] = [Fixtures.agent(id: "agent_1")],
  settings: String = Fixtures.settingsJSON(),
  now: Date = serverNow
) async -> (store: IanStore, service: ScriptedService, feed: Feed) {
  var snapshot = Fixtures.snapshot(cursor: "10")
  snapshot.agents = Fixtures.agentsOverview(agents)
  snapshot.settings = Fixtures.decode(settings)
  let service = ScriptedService(snapshots: [.success(snapshot)])
  let feed = service.planStream()
  let store = makeStore(service, now: now)
  store.start()
  _ = await waitUntil("live") { store.connection == .live }
  return (store, service, feed)
}

private func agentEvent(_ id: String, state: String, event: String) -> StreamMessage {
  .event(id: event, Fixtures.event(Fixtures.agentUpdatedJSON(id: id, state: state)))
}

@Suite("Agents in the store")
@MainActor
struct AgentStoreTests {
  @Test("refetches GET /agents when agent.updated names an agent it has not seen")
  func refetchesForAnUnseenAgent() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }
    service.planAgents([
      .success(
        Fixtures.agentsOverview([
          Fixtures.agent(id: "agent_new", name: "Calendar job"), Fixtures.agent(id: "agent_1"),
        ]))
    ])

    feed.yield(agentEvent("agent_new", state: "running", event: "11"))

    #expect(
      await waitUntil("the server's order") {
        store.state.agents.map(\.id) == ["agent_new", "agent_1"]
      })
    #expect(service.agentsCalls == 1)
    #expect(store.state.agents.first?.name == "Calendar job")
  }

  @Test("does not refetch when the agent is one it holds")
  func noRefetchForAKnownAgent() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }

    feed.yield(agentEvent("agent_1", state: "paused", event: "11"))

    #expect(await waitUntil("the update") { store.state.agents.first?.state == .paused })
    #expect(service.agentsCalls == 0)
  }

  @Test("keeps the agent the event carried when the refetch fails")
  func keepsTheEventsAgentWhenRefetchFails() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }
    service.planAgents([.failure(.offline)])

    feed.yield(agentEvent("agent_new", state: "running", event: "11"))

    #expect(await waitUntil("the refetch") { service.agentsCalls == 1 })
    #expect(await waitUntil("the appended agent") { store.state.agents.count == 2 })
    #expect(store.state.agents.last?.id == "agent_new")
  }

  @Test("sends the pause, marks the agent pending, and moves it only on the event")
  func pauseSettlesOnTheEvent() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }

    await store.pause(agent: "agent_1")

    #expect(service.agentCommands == [.init(id: "agent_1", pause: true)])
    #expect(store.agentPending == ["agent_1"])
    #expect(store.state.agents.first?.state == .idle)

    feed.yield(agentEvent("agent_1", state: "paused", event: "11"))
    #expect(await waitUntil("the event") { store.state.agents.first?.state == .paused })
    #expect(store.agentPending.isEmpty)
  }

  @Test("sends the resume for a paused agent")
  func resumeIsSent() async {
    let (store, service, _) = await liveStore(agents: [Fixtures.agent(state: "paused")])
    defer { store.stop() }

    await store.resume(agent: "agent_1")

    #expect(service.agentCommands == [.init(id: "agent_1", pause: false)])
  }

  @Test("shows the server's reason on the row when it answers 403, and clears the pending mark")
  func forbiddenIsShownOnTheRow() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    service.planAgentCommand(
      .failure(.rejected(status: 403, detail: "Inbox watcher is not yours to pause.")))

    await store.pause(agent: "agent_1")

    #expect(store.agentNotices["agent_1"] == "Inbox watcher is not yours to pause.")
    #expect(store.agentPending.isEmpty)
  }

  @Test("does not send for an agent that is not pausable")
  func notPausableIsNotSent() async {
    let (store, service, _) = await liveStore(agents: [Fixtures.agent(pausable: false)])
    defer { store.stop() }

    await store.pause(agent: "agent_1")

    #expect(service.agentCommands.isEmpty)
  }

  @Test("does not send while offline, and says why")
  func offlineIsRefused() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }
    feed.finish(throwing: DesktopError.offline)
    #expect(await waitUntil("offline") { store.connection == .offline })

    await store.pause(agent: "agent_1")

    #expect(service.agentCommands.isEmpty)
    #expect(store.agentNotices["agent_1"] == DesktopError.offline.localizedDescription)
  }
}

@Suite("Principal settings in the store")
@MainActor
struct SettingsStoreTests {
  @Test("sends the patch and shows the new value only after settings.updated")
  func showsTheValueAfterTheEvent() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }

    await store.updateSettings(.init(pushBudgetPerHour: 7))

    #expect(service.settingsPatches == [.init(pushBudgetPerHour: 7)])
    #expect(store.state.settings?.pushBudgetPerHour == 3)
    #expect(store.settingsPending)

    feed.yield(.event(id: "11", Fixtures.event(Fixtures.settingsUpdatedJSON(pushBudget: 7))))
    #expect(await waitUntil("the event") { store.state.settings?.pushBudgetPerHour == 7 })
    #expect(!store.settingsPending)
  }

  @Test("keeps the server's refusal for the view and clears the pending mark on 422")
  func refusalIsKept() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    service.planSettingsPatch(
      .failure(.rejected(status: 422, detail: "Going live opens on 23 October.")))

    await store.updateSettings(.init(mode: .live))

    #expect(store.settingsNotice == "Going live opens on 23 October.")
    #expect(!store.settingsPending)
    #expect(store.state.settings?.mode == .dryRun)
  }

  @Test("sends nothing while offline")
  func offlineIsRefused() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }
    feed.finish(throwing: DesktopError.offline)
    #expect(await waitUntil("offline") { store.connection == .offline })

    await store.updateSettings(.init(paused: true))

    #expect(service.settingsPatches.isEmpty)
    #expect(store.settingsNotice == DesktopError.offline.localizedDescription)
  }
}

@Suite("Diagnostics inputs in the store")
@MainActor
struct DiagnosticsInputTests {
  @Test("measures event lag from a heartbeat's server time to its arrival")
  func eventLagFromAHeartbeat() async {
    let serverTime = Fixtures.decode("\"2026-10-16T08:00:25.000Z\"") as Date
    let (store, _, feed) = await liveStore(now: serverTime.addingTimeInterval(1.5))
    defer { store.stop() }
    #expect(store.eventLag == nil)

    feed.yield(.event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))

    #expect(await waitUntil("the heartbeat") { store.eventLag == 1.5 })
  }

  @Test("records when the last snapshot arrived")
  func lastSnapshotTime() async {
    let (store, _, _) = await liveStore()
    defer { store.stop() }
    #expect(store.lastSnapshotAt == serverNow)
  }
}

@Suite("Switching the environment profile")
@MainActor
struct ProfileSwitchTests {
  private func switcher(
    next: ScriptedService, remembered: Box<String?>
  ) -> ProfileSwitcher {
    ProfileSwitcher(
      choices: [
        ProfileChoice(id: "mock", displayName: "Mock"),
        ProfileChoice(id: "lance-dev", displayName: "Lance dev"),
      ],
      build: { id in
        id == "lance-dev"
          ? (.lanceDev(entra: .init(tenantID: "t", clientID: "c", scope: "s")), next) : nil
      },
      remember: { remembered.value = $0 })
  }

  @Test("signs out, clears the store, saves the choice and syncs against the new profile")
  func switchesProfile() async {
    let first = ScriptedService()
    first.planStream()
    let second = ScriptedService(
      snapshots: [
        .success(Fixtures.snapshot(cursor: "50", items: [Fixtures.itemJSON(id: "task_9")]))
      ])
    second.planStream()
    let remembered = Box<String?>(nil)
    let store = IanStore(
      service: first, profile: .mock, appVersion: SemanticVersion("0.1.0")!,
      clock: ManualClock(), jitter: { 1 }, now: { serverNow },
      profileSwitcher: switcher(next: second, remembered: remembered))
    store.start()
    #expect(await waitUntil("first profile live") { store.connection == .live })
    #expect(store.state.items["task_1"] != nil)

    let switched = await store.switchProfile(to: "lance-dev")

    #expect(switched)
    #expect(first.signOuts == 1)
    #expect(store.profileID == "lance-dev")
    #expect(remembered.value == "lance-dev")
    #expect(await waitUntil("second profile live") { store.connection == .live })
    #expect(store.state.items["task_1"] == nil)
    #expect(store.state.items["task_9"] != nil)
    #expect(second.snapshotCalls == 1)
    store.stop()
  }

  @Test("does nothing for the profile already in use or an unknown one")
  func ignoresNoOpSwitches() async {
    let service = ScriptedService()
    let remembered = Box<String?>(nil)
    let store = IanStore(
      service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!,
      clock: ManualClock(), jitter: { 1 }, now: { serverNow },
      profileSwitcher: switcher(next: ScriptedService(), remembered: remembered))

    #expect(await !store.switchProfile(to: "mock"))
    #expect(await !store.switchProfile(to: "production"))
    #expect(service.signOuts == 0)
    #expect(remembered.value == nil)
  }
}

@MainActor
private final class Box<Value> {
  var value: Value
  init(_ value: Value) { self.value = value }
}
