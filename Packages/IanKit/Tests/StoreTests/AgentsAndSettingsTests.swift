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

  @Test("does not start a refetch when the agent is one it holds")
  func noRefetchForAKnownAgent() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }

    feed.yield(agentEvent("agent_1", state: "paused", event: "11"))
    // The refetch starts as the event is applied, so a later event is a barrier after it.
    feed.yield(.event(id: "12", Fixtures.event(Fixtures.settingsUpdatedJSON(pushBudget: 9))))

    #expect(await waitUntil("both events") { store.state.settings?.pushBudgetPerHour == 9 })
    #expect(store.state.agents.first?.state == .paused)
    #expect(store.agentsTouchedDuringRefetch == nil)
    #expect(service.agentsCalls == 0)
  }

  @Test("keeps an agent's newer event over an older refetch response")
  func refetchKeepsNewerEvents() async {
    let (store, service, feed) = await liveStore()
    defer { store.stop() }
    let gate = Gate()
    service.planAgents([
      .success(
        Fixtures.agentsOverview([
          Fixtures.agent(id: "agent_new", name: "Calendar job"), Fixtures.agent(id: "agent_1"),
        ]))
    ])
    service.planAgentsHook { await gate.wait() }

    feed.yield(agentEvent("agent_new", state: "running", event: "11"))
    #expect(await waitUntil("the refetch is out") { service.agentsCalls == 1 })
    feed.yield(agentEvent("agent_1", state: "paused", event: "12"))
    #expect(await waitUntil("the newer event") { store.state.agents.first?.state == .paused })
    await gate.open()

    #expect(
      await waitUntil("the server's order") {
        store.state.agents.map(\.id) == ["agent_new", "agent_1"]
      })
    #expect(store.state.agents.last?.state == .paused)
  }

  @Test("lets a snapshot that arrives during a refetch win, so a dropped agent stays dropped")
  func snapshotBeatsAnOlderRefetch() async {
    let first = Fixtures.snapshot(cursor: "10")
    var second = Fixtures.snapshot(cursor: "20")
    second.agents = Fixtures.agentsOverview([Fixtures.agent(id: "agent_1")])
    let service = ScriptedService(snapshots: [.success(first), .success(second)])
    let feed = service.planStream()
    service.planStream()
    let gate = Gate()
    service.planAgents([
      .success(
        Fixtures.agentsOverview([
          Fixtures.agent(id: "agent_gone"), Fixtures.agent(id: "agent_1"),
        ]))
    ])
    service.planAgentsHook { await gate.wait() }
    let store = makeStore(service)
    store.start()
    defer { store.stop() }
    #expect(await waitUntil("live") { store.connection == .live })

    feed.yield(agentEvent("agent_gone", state: "running", event: "11"))
    #expect(await waitUntil("the refetch is out") { service.agentsCalls == 1 })
    feed.yield(.undecodable)
    #expect(await waitUntil("the second snapshot") { service.snapshotCalls == 2 })
    #expect(await waitUntil("its agents") { store.state.agents.map(\.id) == ["agent_1"] })
    await gate.open()
    try? await Task.sleep(for: .milliseconds(100))

    #expect(store.state.agents.map(\.id) == ["agent_1"])
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
    service.planSettingsPatch(.success(Fixtures.decode(Fixtures.settingsJSON(pushBudget: 7))))

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

  @Test("clears the pending mark when the reply equals what it holds, since no event will come")
  func unchangedReplySettlesAtOnce() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    service.planSettingsPatch(.success(Fixtures.decode(Fixtures.settingsJSON())))

    await store.updateSettings(.init(pushBudgetPerHour: 3))

    #expect(!store.settingsPending)
  }

  @Test("keeps the pending mark when the reply differs, until the event shows it")
  func changedReplyWaitsForTheEvent() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    service.planSettingsPatch(.success(Fixtures.decode(Fixtures.settingsJSON(pushBudget: 9))))

    await store.updateSettings(.init(pushBudgetPerHour: 9))

    #expect(store.settingsPending)
    #expect(store.state.settings?.pushBudgetPerHour == 3)
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

/// A clock the test moves.
private final class TestClock: @unchecked Sendable {
  // Read and written only while holding `lock`.
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) { self.date = date }

  var now: Date { lock.withLock { date } }
  func set(_ date: Date) { lock.withLock { self.date = date } }
}

@Suite("Diagnostics inputs in the store")
@MainActor
struct DiagnosticsInputTests {
  @Test("estimates event lag against the server's clock, offset taken from GET /me")
  func eventLagCorrectsForTheClockOffset() async {
    // `me.serverTime` is 08:00:00 and the local clock reads 07:59:58 for the whole request, so
    // the server is 2 seconds ahead.
    let meTime = Fixtures.decode("\"2026-10-16T08:00:00.000Z\"") as Date
    let clock = TestClock(meTime.addingTimeInterval(-2))
    let service = ScriptedService()
    let feed = service.planStream()
    let store = IanStore(
      service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!,
      clock: ManualClock(), jitter: { 1 }, now: { clock.now })
    store.start()
    defer { store.stop() }
    #expect(await waitUntil("live") { store.connection == .live })
    #expect(store.clockOffset == 2)
    #expect(store.eventLag == nil)

    // The heartbeat says 08:00:25 on the server, which is 08:00:23 here. It arrives at 08:00:24.
    clock.set(meTime.addingTimeInterval(24))
    feed.yield(.event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))

    #expect(await waitUntil("the heartbeat") { store.eventLag == 1 })
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

/// Records a value a scripted call saw.
actor Flag {
  private(set) var value = false
  func set(_ value: Bool) { self.value = value }
}

/// Holds a scripted call open until the test lets it go.
actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}

@Suite("Calls that outlive the state they started in")
@MainActor
struct StaleCallTests {
  @Test("drops a sign-in that finishes after a sign-out")
  func signInAfterSignOutIsDropped() async {
    let service = ScriptedService()
    let gate = Gate()
    service.planSignInHook { await gate.wait() }
    let store = makeStore(service)

    let signIn = Task { await store.signIn() }
    #expect(await waitUntil("the sign-in is open") { service.signIns == 1 })
    await store.signOut()
    await gate.open()
    await signIn.value

    #expect(store.phase == .signInRequired(message: nil))
    #expect(service.streamCalls.isEmpty)
  }

  @Test("drops a sign-in failure that arrives after a profile switch")
  func signInFailureAfterSwitchIsDropped() async {
    let first = ScriptedService()
    let second = ScriptedService()
    second.planStream()
    first.planSignInFailure(DesktopError.failed("The browser was closed."))
    let gate = Gate()
    first.planSignInHook { await gate.wait() }
    let store = IanStore(
      service: first, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
      jitter: { 1 }, now: { serverNow },
      profileSwitcher: ProfileSwitcher(
        choices: [ProfileChoice(id: "lance-dev", displayName: "Lance dev")],
        build: { _ in
          (.lanceDev(entra: .init(tenantID: "t", clientID: "c", scope: "s")), second)
        },
        remember: { _ in }))

    let signIn = Task { await store.signIn() }
    #expect(await waitUntil("the sign-in is open") { first.signIns == 1 })
    await store.switchProfile(to: "lance-dev")
    await gate.open()
    await signIn.value

    #expect(store.phase == .running)
    #expect(store.profileID == "lance-dev")
  }

  @Test("drops an agent command's failure after a sign-out, with no notice and no sign-in")
  func agentFailureAfterSignOutIsDropped() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    let gate = Gate()
    service.planAgentCommand(.failure(.unauthorised))
    service.planAgentCommandHook { await gate.wait() }

    let pause = Task { await store.pause(agent: "agent_1") }
    #expect(await waitUntil("the call is out") { service.agentCommands.count == 1 })
    await store.signOut()
    await gate.open()
    await pause.value

    #expect(service.signIns == 0)
    #expect(store.agentNotices.isEmpty)
    #expect(store.phase == .signInRequired(message: nil))
  }

  @Test("drops an item action's failure after a sign-out, with no notice and no sign-in")
  func actionFailureAfterSignOutIsDropped() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    let gate = Gate()
    service.planAction { _ in
      await gate.wait()
      throw DesktopError.unauthorised
    }

    let run = Task { await store.run(actionID: "done", on: "task_1") }
    #expect(await waitUntil("the call is out") { service.actionCalls.count == 1 })
    await store.signOut()
    await gate.open()
    await run.value

    #expect(service.signIns == 0)
    #expect(store.notices.isEmpty)
    #expect(store.phase == .signInRequired(message: nil))
  }

  @Test("drops a hand-off's upgrade refusal after a profile switch")
  func handoffFailureAfterSwitchIsDropped() async {
    var me = Fixtures.me()
    me.capabilities.handoff = true
    let first = ScriptedService(me: me)
    first.planStream()
    let second = ScriptedService()
    second.planStream()
    let gate = Gate()
    first.planHandoff { _ in
      await gate.wait()
      throw DesktopError.upgradeRequired(minClientVersion: "9.0.0")
    }
    let store = IanStore(
      service: first, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
      jitter: { 1 }, now: { serverNow },
      profileSwitcher: ProfileSwitcher(
        choices: [ProfileChoice(id: "lance-dev", displayName: "Lance dev")],
        build: { _ in
          (.lanceDev(entra: .init(tenantID: "t", clientID: "c", scope: "s")), second)
        },
        remember: { _ in }))
    store.start()
    defer { store.stop() }
    #expect(await waitUntil("live") { store.connection == .live && store.offersHandoff })

    let handOff = Task { await store.handOff(itemID: "task_1") }
    #expect(await waitUntil("the call is out") { first.handoffCalls.count == 1 })
    await store.switchProfile(to: "lance-dev")
    await gate.open()
    await handOff.value

    #expect(store.phase == .running)
    #expect(store.notices.isEmpty)
  }

  @Test("cancels an open sign-in when the principal switches profile or signs out")
  func switchingCancelsTheSignIn() async {
    let first = ScriptedService()
    let second = ScriptedService()
    second.planStream()
    let cancelled = Flag()
    first.planSignInHook {
      try? await Task.sleep(for: .seconds(30))
      await cancelled.set(Task.isCancelled)
    }
    let store = IanStore(
      service: first, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
      jitter: { 1 }, now: { serverNow },
      profileSwitcher: ProfileSwitcher(
        choices: [ProfileChoice(id: "lance-dev", displayName: "Lance dev")],
        build: { _ in
          (.lanceDev(entra: .init(tenantID: "t", clientID: "c", scope: "s")), second)
        },
        remember: { _ in }))

    let signIn = Task { await store.signIn() }
    #expect(await waitUntil("the sign-in is open") { first.signIns == 1 && store.isSigningIn })
    await store.switchProfile(to: "lance-dev")

    #expect(await waitUntil("the sign-in ends") { !store.isSigningIn })
    await signIn.value
    #expect(await cancelled.value)
    #expect(store.profileID == "lance-dev")
    #expect(store.phase == .running)
    store.stop()
  }

  @Test("drops a settings refusal after a sign-out")
  func settingsFailureAfterSignOutIsDropped() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    let gate = Gate()
    service.planSettingsPatch(.failure(.rejected(status: 422, detail: "Not yet.")))
    service.planSettingsPatchHook { await gate.wait() }

    let update = Task { await store.updateSettings(.init(mode: .live)) }
    #expect(await waitUntil("the call is out") { service.settingsPatches.count == 1 })
    await store.signOut()
    await gate.open()
    await update.value

    #expect(store.settingsNotice == nil)
  }
}

@Suite("The profile switcher the app builds")
@MainActor
struct ProfileSwitcherFactoryTests {
  private func switcher(_ defaults: UserDefaults) -> ProfileSwitcher {
    IanStore.makeProfileSwitcher(
      info: [:], bundleIdentifier: "ai.valliance.ian.desktop.tests",
      version: SemanticVersion("0.1.0")!, defaults: defaults, openURL: { _ in })
  }

  @Test("offers each profile, and builds none it does not know")
  func offersTheProfiles() {
    withScratchDefaults { defaults in
      let switcher = switcher(defaults)
      #expect(switcher.choices.map(\.id) == ["mock", "lance-dev"])
      #expect(switcher.build("lance-dev")?.0.name == .lanceDev)
      #expect(switcher.build("production") == nil)
    }
  }

  @Test("saves the choice under IanEnvironment, and a fresh read returns it")
  func choiceSurvivesARelaunch() throws {
    try withScratchDefaults { defaults in
      switcher(defaults).remember("lance-dev")

      #expect(defaults.string(forKey: "IanEnvironment") == "lance-dev")
      let profile = try EnvironmentProfile.resolve(defaults: defaults, info: [:])
      #expect(profile.name == .lanceDev)
    }
  }
}
