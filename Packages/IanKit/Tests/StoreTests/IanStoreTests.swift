import Auth
import Client
import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

private let launchTime = Date(timeIntervalSince1970: 1_792_137_600)

@MainActor
private func makeStore(
  _ service: ScriptedService, appVersion: String = "0.1.0", now: Date = launchTime
) -> IanStore {
  IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion(appVersion)!,
    clock: ManualClock(), jitter: { 1 }, now: { now })
}

@MainActor
private func waitUntil(
  _ description: String, _ condition: @MainActor @escaping @Sendable () -> Bool
) async -> Bool {
  await eventually(description) { await MainActor.run { condition() } }
}

private func removed(_ id: String, event eventID: String, correlationId: String? = nil)
  -> StreamMessage
{
  .event(
    id: eventID, Fixtures.event(Fixtures.removedJSON(id, correlationId: correlationId)))
}

/// A started store with `task_1` on screen and a live stream.
@MainActor
private func liveStore(
  items: [String] = [Fixtures.itemJSON(id: "task_1", version: 3)]
) async -> (
  store: IanStore, service: ScriptedService,
  feed: AsyncThrowingStream<StreamMessage, any Error>.Continuation
) {
  let service = ScriptedService(snapshots: [.success(Fixtures.snapshot(cursor: "10", items: items))]
  )
  let feed = service.planStream()
  let store = makeStore(service)
  store.start()
  _ = await waitUntil("live") { store.connection == .live }
  return (store, service, feed)
}

@MainActor
@Test("shows the snapshot with the stream live and the data's age from the server's last word")
private func showsSnapshotWhenLive() async {
  let (store, _, _) = await liveStore()
  defer { store.stop() }

  #expect(store.phase == .running)
  #expect(store.state.items["task_1"] != nil)
  #expect(store.state.me?.principalId == "prin_1")
  #expect(store.actionsEnabled)
  #expect(store.lastUpdatedAt == launchTime)
  #expect(store.dataAge(at: launchTime.addingTimeInterval(90)) == 90)
}

@MainActor
@Test("applies a stream event to the store")
private func appliesStreamEvent() async {
  let (store, _, feed) = await liveStore()
  defer { store.stop() }

  feed.yield(removed("task_1", event: "11"))

  #expect(await waitUntil("removal") { store.state.items["task_1"] == nil })
  #expect(store.state.lastEventID == 11)
}

@MainActor
@Test("marks the item pending with the correlation id, and does not move it")
private func marksItemPending() async {
  let (store, service, _) = await liveStore()
  defer { store.stop() }

  await store.run(actionID: "done", on: "task_1")

  #expect(
    store.pending["task_1"] == .init(actionID: "done", correlationID: "corr_1", sentVersion: 3))
  #expect(store.state.items["task_1"]?.version == 3)
  #expect(service.actionCalls.map(\.version) == [3])
  #expect(service.actionCalls.map(\.actionID) == ["done"])
}

@MainActor
@Test("clears the pending mark when an event carrying its correlation id arrives")
private func clearsPendingOnCorrelatedEvent() async {
  let (store, _, feed) = await liveStore()
  defer { store.stop() }
  await store.run(actionID: "done", on: "task_1")

  feed.yield(removed("task_1", event: "11", correlationId: "corr_1"))

  #expect(await waitUntil("cleared") { store.pending.isEmpty })
}

@MainActor
@Test("clears the mark of the action that raised a proposal, by correlation id and not item id")
private func clearsPendingByCorrelationAcrossItems() async {
  let (store, _, feed) = await liveStore()
  defer { store.stop() }
  await store.run(actionID: "done", on: "task_1")

  feed.yield(
    .event(
      id: "11",
      Fixtures.event(
        Fixtures.upsertedJSON(Fixtures.itemJSON(id: "prop_1"), correlationId: "corr_1"))))

  #expect(await waitUntil("cleared") { store.pending.isEmpty })
  #expect(store.state.items["task_1"] != nil)
}

@MainActor
@Test("keeps the mark when an event carries another correlation id")
private func keepsPendingForOtherCorrelation() async {
  let (store, _, feed) = await liveStore()
  defer { store.stop() }
  await store.run(actionID: "done", on: "task_1")

  feed.yield(removed("task_2", event: "11", correlationId: "corr_other"))
  feed.yield(removed("task_3", event: "12"))
  #expect(await waitUntil("both events") { store.state.lastEventID == 12 })

  #expect(store.pending["task_1"]?.correlationID == "corr_1")
}

@MainActor
@Test("clears the mark when the event arrives before the action's answer")
private func clearsPendingWhenEventBeatsAnswer() async {
  let (store, service, feed) = await liveStore()
  defer { store.stop() }
  let (gate, release) = AsyncStream<Void>.makeStream()
  service.planAction { _ in
    feed.yield(removed("task_1", event: "11", correlationId: "corr_early"))
    for await _ in gate { break }
    return "corr_early"
  }

  let running = Task { await store.run(actionID: "done", on: "task_1") }
  #expect(await waitUntil("the event") { store.state.items["task_1"] == nil })
  release.yield()
  await running.value

  #expect(store.pending.isEmpty)
}

@MainActor
@Test("clears the mark and records the error when the action fails")
private func recordsActionError() async {
  let (store, service, _) = await liveStore()
  defer { store.stop() }
  service.planAction { _ in throw DesktopError.rejected(status: 400, detail: "Choose a later time.")
  }

  await store.run(actionID: "done", on: "task_1")

  #expect(store.pending.isEmpty)
  #expect(store.notices["task_1"] == .failed("Choose a later time."))
}

@MainActor
@Test("replaces the item from a 409 problem body and notes that it changed")
private func replacesItemOnConflict() async {
  let (store, service, _) = await liveStore()
  defer { store.stop() }
  let current = Fixtures.item(id: "task_1", version: 9, title: "Changed elsewhere")
  service.planAction { _ in throw DesktopError.conflict(item: current) }

  await store.run(actionID: "done", on: "task_1")

  #expect(store.pending.isEmpty)
  #expect(store.state.items["task_1"]?.version == 9)
  #expect(store.state.items["task_1"]?.title == "Changed elsewhere")
  #expect(store.notices["task_1"] == .changed)
}

@MainActor
@Test("sends the time or the note only when the action's input asks for it")
private func sendsInputOnlyWhenAsked() async {
  let items = [
    Fixtures.itemJSON(id: "task_1", actions: [.init("snooze", input: "until")]),
    Fixtures.itemJSON(id: "task_2", actions: [.init("chase", input: "note")]),
  ]
  let (store, service, _) = await liveStore(items: items)
  defer { store.stop() }
  let until = launchTime.addingTimeInterval(3_600)

  await store.run(actionID: "snooze", on: "task_1", until: until, note: "ignored")
  await store.run(actionID: "chase", on: "task_2", until: until, note: "Ask again.")

  #expect(service.actionCalls.map(\.until) == [until, nil])
  #expect(service.actionCalls.map(\.note) == [nil, "Ask again."])
}

@MainActor
@Test("does not send an action that needs a time or a note it was not given")
private func refusesMissingInput() async {
  let items = [Fixtures.itemJSON(id: "task_1", actions: [.init("snooze", input: "until")])]
  let (store, service, _) = await liveStore(items: items)
  defer { store.stop() }

  await store.run(actionID: "snooze", on: "task_1")

  #expect(service.actionCalls.isEmpty)
  #expect(store.pending.isEmpty)
  #expect(store.notices["task_1"] != nil)
}

@MainActor
@Test("ignores an action id the item does not offer")
private func ignoresUnknownAction() async {
  let (store, service, _) = await liveStore()
  defer { store.stop() }

  await store.run(actionID: "delete", on: "task_1")

  #expect(service.actionCalls.isEmpty)
  #expect(store.pending.isEmpty)
}

@MainActor
@Test("keeps the data with its age and disables actions while offline")
private func offlineKeepsDataAndDisablesActions() async {
  let (store, service, feed) = await liveStore()
  defer { store.stop() }

  feed.finish(throwing: DesktopError.offline)
  #expect(await waitUntil("offline") { store.connection == .offline })
  await store.run(actionID: "done", on: "task_1")

  #expect(store.state.items["task_1"] != nil)
  #expect(!store.actionsEnabled)
  #expect(store.dataAge(at: launchTime.addingTimeInterval(120)) == 120)
  #expect(service.actionCalls.isEmpty)
  #expect(store.pending.isEmpty)
  #expect(store.notices["task_1"] != nil)
}

@MainActor
@Test("replaces the data when a snapshot arrives while the stream is down")
private func polledSnapshotReplacesData() async {
  let service = ScriptedService(
    snapshots: [
      .success(Fixtures.snapshot(cursor: "10", items: [Fixtures.itemJSON(id: "task_1")])),
      .success(Fixtures.snapshot(cursor: "50", items: [Fixtures.itemJSON(id: "task_2")])),
    ])
  let first = service.planStream()
  // Reconnection keeps failing, so the poll is what brings the new data.
  service.planStreamFailure(.offline)
  service.planStreamFailure(.offline)
  let clock = ManualClock()
  let store = IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: clock,
    jitter: { 1 }, now: { launchTime })
  store.start()
  defer { store.stop() }
  #expect(await waitUntil("live") { store.connection == .live })

  first.finish(throwing: DesktopError.offline)
  #expect(await waitUntil("offline") { store.connection == .offline })
  #expect(await eventually("the poll timer") { await clock.requestedSleeps.contains(.seconds(60)) })
  await clock.advance(by: .seconds(60))

  #expect(await waitUntil("polled data") { store.state.items["task_2"] != nil })
  #expect(store.state.items["task_1"] == nil)
}

@MainActor
@Test("drops the pending mark of an item a fresh snapshot no longer holds")
private func snapshotDropsOrphanedMarks() async {
  let service = ScriptedService(
    snapshots: [
      .success(Fixtures.snapshot(cursor: "10", items: [Fixtures.itemJSON(id: "task_1")])),
      .success(Fixtures.snapshot(cursor: "50", items: [])),
    ])
  let feed = service.planStream()
  service.planStream()
  let store = makeStore(service)
  store.start()
  defer { store.stop() }
  #expect(await waitUntil("live") { store.connection == .live })
  await store.run(actionID: "done", on: "task_1")
  #expect(store.pending["task_1"] != nil)

  feed.finish(throwing: DesktopError.gone)

  #expect(await waitUntil("snapshot") { store.state.lastEventID == 50 })
  #expect(store.pending.isEmpty)
}

@MainActor
@Test("clears a pending mark when a snapshot holds a newer version of the item")
private func snapshotClearsMarkOfMovedItem() async {
  let service = ScriptedService(
    snapshots: [
      .success(
        Fixtures.snapshot(cursor: "10", items: [Fixtures.itemJSON(id: "task_1", version: 3)])),
      .success(
        Fixtures.snapshot(cursor: "50", items: [Fixtures.itemJSON(id: "task_1", version: 4)])),
    ])
  let feed = service.planStream()
  service.planStream()
  let store = makeStore(service)
  store.start()
  defer { store.stop() }
  #expect(await waitUntil("live") { store.connection == .live })
  await store.run(actionID: "done", on: "task_1")

  feed.yield(.undecodable)

  #expect(await waitUntil("snapshot") { store.state.lastEventID == 50 })
  #expect(store.pending.isEmpty)
  #expect(store.state.items["task_1"]?.version == 4)
}

@MainActor
@Test("keeps a pending mark when the snapshot holds the version the action was sent with")
private func snapshotKeepsMarkAtSentVersion() async {
  let service = ScriptedService(
    snapshots: [
      .success(
        Fixtures.snapshot(cursor: "10", items: [Fixtures.itemJSON(id: "task_1", version: 3)])),
      .success(
        Fixtures.snapshot(cursor: "50", items: [Fixtures.itemJSON(id: "task_1", version: 3)])),
    ])
  let feed = service.planStream()
  service.planStream()
  let store = makeStore(service)
  store.start()
  defer { store.stop() }
  #expect(await waitUntil("live") { store.connection == .live })
  await store.run(actionID: "done", on: "task_1")

  feed.yield(.undecodable)

  #expect(await waitUntil("snapshot") { store.state.lastEventID == 50 })
  #expect(store.pending["task_1"] != nil)
}

@MainActor
@Test("applies nothing buffered behind client.deprecated, leaving no data in the store")
private func deprecationMidBurstLeavesNoData() async {
  let (store, _, feed) = await liveStore()
  defer { store.stop() }

  feed.yield(
    .event(id: "11", Fixtures.event(Fixtures.clientDeprecatedJSON(minClientVersion: "0.2.0"))))
  for id in 12..<40 {
    feed.yield(
      .event(
        id: "\(id)", Fixtures.event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_\(id)")))))
  }

  #expect(await waitUntil("upgrade") { store.phase == .upgradeRequired(minimumVersion: "0.2.0") })
  try? await Task.sleep(for: .milliseconds(50))
  #expect(store.state == StoreState())
}

@MainActor
@Test("keeps a newer item when a 409 problem body carries an older one")
private func conflictDoesNotOverwriteNewerItem() async {
  let (store, service, feed) = await liveStore(items: [Fixtures.itemJSON(id: "task_1", version: 3)])
  defer { store.stop() }
  service.planAction { _ in
    feed.yield(
      .event(
        id: "11", Fixtures.event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "task_1", version: 8)))
      ))
    _ = await eventually("the event") {
      await MainActor.run { store.state.items["task_1"]?.version == 8 }
    }
    throw DesktopError.conflict(item: Fixtures.item(id: "task_1", version: 5))
  }

  await store.run(actionID: "done", on: "task_1")

  #expect(store.state.items["task_1"]?.version == 8)
  #expect(store.notices["task_1"] == .changed)
}

@MainActor
@Test("does not bring back an item an event removed when a 409 body names it")
private func conflictDoesNotResurrectRemovedItem() async {
  let (store, service, feed) = await liveStore()
  defer { store.stop() }
  service.planAction { _ in
    feed.yield(removed("task_1", event: "11"))
    _ = await eventually("the removal") {
      await MainActor.run { store.state.items["task_1"] == nil }
    }
    throw DesktopError.conflict(item: Fixtures.item(id: "task_1", version: 9))
  }

  await store.run(actionID: "done", on: "task_1")

  #expect(store.state.items["task_1"] == nil)
}

@MainActor
@Test("starts one sign-in when two are requested at once")
private func signInsDoNotOverlap() async {
  let service = ScriptedService()
  let (gate, release) = AsyncStream<Void>.makeStream()
  service.planSignInHook { for await _ in gate { break } }
  let store = makeStore(service)
  defer { store.stop() }

  let first = Task { await store.signIn() }
  #expect(await waitUntil("the first sign-in") { store.isSigningIn })
  await store.signIn()
  release.yield()
  await first.value

  #expect(service.signIns == 1)
  #expect(!store.isSigningIn)
}

@MainActor
@Test("shows a failure retrying cannot fix, with its own message, instead of going offline")
private func terminalFailureShowsMessage() async {
  let service = ScriptedService()
  service.planMe(.failure(.failed("The Keychain refused to store the sign-in.")))
  let store = makeStore(service)
  store.start()
  defer { store.stop() }

  #expect(
    await waitUntil("message") {
      store.phase == .signInRequired(message: "The Keychain refused to store the sign-in.")
    })
}

@MainActor
@Test("builds the mock store when no profile is named, reading the version from the bundle")
private func makesMockStoreByDefault() {
  let store = IanStore.make(
    profileName: nil, info: [:], bundleIdentifier: "ai.valliance.ian.desktop.dev",
    shortVersion: "0.3.1", openURL: { _ in })

  #expect(store.profile == .mock)
  #expect(store.appVersion == SemanticVersion(major: 0, minor: 3, patch: 1))
}

@MainActor
@Test("builds the lance-dev store from the Info.plist settings")
private func makesLanceDevStore() {
  let store = IanStore.make(
    profileName: "lance-dev", info: ["IanLanceTenantID": "tenant-1"],
    bundleIdentifier: "ai.valliance.ian.desktop.dev", shortVersion: "0.1.0", openURL: { _ in })

  #expect(store.profile.name == .lanceDev)
}

@MainActor
@Test("falls back to the mock profile and version 0.0.0 when the name and version are unusable")
private func makesMockStoreFromBadInput() {
  let store = IanStore.make(
    profileName: "production", info: [:], bundleIdentifier: "ai.valliance.ian.desktop",
    shortVersion: nil, openURL: { _ in })

  #expect(store.profile == .mock)
  #expect(store.appVersion == SemanticVersion(major: 0, minor: 0, patch: 0))
}

@MainActor
@Test("requires sign-in on 401, clears the token and the data, then opens sign-in once")
private func unauthorisedRequiresSignIn() async {
  let service = ScriptedService()
  service.planSignInFailure(AuthError.signInRequired)
  service.planStreamFailure(.unauthorised)
  let store = makeStore(service)
  store.start()
  defer { store.stop() }

  #expect(
    await waitUntil("sign-in failed") {
      store.phase == .signInRequired(message: AuthError.signInRequired.localizedDescription)
    })

  #expect(service.signOuts == 1)
  #expect(service.signIns == 1)
  #expect(store.state == StoreState())
}

@MainActor
@Test("does not open sign-in a second time in the same session")
private func opensSignInOnce() async {
  let service = ScriptedService()
  service.planStreamFailure(.unauthorised)
  service.planStreamFailure(.unauthorised)
  let store = makeStore(service)
  store.start()
  defer { store.stop() }
  #expect(await waitUntil("first sign-in") { service.signIns == 1 })
  #expect(await waitUntil("second 401") { service.streamCalls.count == 2 })
  #expect(await waitUntil("signed out again") { store.phase == .signInRequired(message: nil) })
  // The store shows the phase first and signs out in a task after it, so wait for that call.
  #expect(await waitUntil("second sign-out") { service.signOuts == 2 })

  #expect(service.signIns == 1)
}

@MainActor
@Test("shows why sign-in failed, naming the missing scope")
private func showsSignInFailure() async {
  let service = ScriptedService()
  service.planSignInFailure(AuthError.notConfigured(missing: [.scope]))
  let store = makeStore(service)

  await store.signIn()

  guard case .signInRequired(let message) = store.phase else {
    Issue.record("expected signInRequired, got \(store.phase)")
    return
  }
  #expect(message?.contains("IAN_LANCE_SCOPE") == true)
  #expect(message?.contains("DL1") == true)
}

@MainActor
@Test("signs out by clearing credentials and every piece of data")
private func signOutClearsEverything() async {
  let (store, service, _) = await liveStore()
  await store.run(actionID: "done", on: "task_1")

  await store.signOut()

  #expect(service.signOuts == 1)
  #expect(store.state == StoreState())
  #expect(store.pending.isEmpty)
  #expect(store.lastUpdatedAt == nil)
  #expect(store.phase == .signInRequired(message: nil))
}

@MainActor
@Test("shows the upgrade state with no data when an action answers 426")
private func upgradeRequiredOnAction() async {
  let (store, service, _) = await liveStore()
  service.planAction { _ in throw DesktopError.upgradeRequired(minClientVersion: "0.5.0") }

  await store.run(actionID: "done", on: "task_1")

  #expect(store.phase == .upgradeRequired(minimumVersion: "0.5.0"))
  #expect(store.state == StoreState())
}

@MainActor
@Test("shows the upgrade state with no data on client.deprecated above the app's version")
private func upgradeRequiredOnDeprecation() async {
  let (store, _, feed) = await liveStore()

  feed.yield(
    .event(id: "11", Fixtures.event(Fixtures.clientDeprecatedJSON(minClientVersion: "0.2.0"))))

  #expect(await waitUntil("upgrade") { store.phase == .upgradeRequired(minimumVersion: "0.2.0") })
  #expect(store.state == StoreState())
}

@MainActor
@Test("ignores client.deprecated when the app already meets the minimum")
private func ignoresDeprecationBelowAppVersion() async {
  let (store, _, feed) = await liveStore()
  defer { store.stop() }

  feed.yield(
    .event(id: "11", Fixtures.event(Fixtures.clientDeprecatedJSON(minClientVersion: "0.1.0"))))
  #expect(await waitUntil("event applied") { store.state.lastEventID == 11 })

  #expect(store.phase == .running)
  #expect(store.state.items["task_1"] != nil)
}

@MainActor
@Test("refuses to start when me reports a minimum version above the app's, fetching no data")
private func refusesToStartBelowMinimum() async {
  let service = ScriptedService(me: Fixtures.me(minClientVersion: "0.2.0"))
  let store = makeStore(service)
  store.start()
  defer { store.stop() }

  #expect(await waitUntil("upgrade") { store.phase == .upgradeRequired(minimumVersion: "0.2.0") })

  #expect(service.snapshotCalls == 0)
  #expect(store.state == StoreState())
  #expect(!store.actionsEnabled)
}

@MainActor
@Test("counts a heartbeat as the server's word, so the data stays young")
private func heartbeatRefreshesAge() async {
  let service = ScriptedService()
  let feed = service.planStream()
  let clockTime = TimeBox(launchTime)
  let store = IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
    jitter: { 1 }, now: { clockTime.value })
  store.start()
  defer { store.stop() }
  #expect(await waitUntil("live") { store.connection == .live })

  clockTime.value = launchTime.addingTimeInterval(25)
  feed.yield(.event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))

  #expect(
    await waitUntil("heartbeat") { store.lastUpdatedAt == launchTime.addingTimeInterval(25) })
}

private final class TimeBox: @unchecked Sendable {
  // `stored` is read and written only while holding `lock`.
  private let lock = NSLock()
  private var stored: Date
  init(_ date: Date) { stored = date }
  var value: Date {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
