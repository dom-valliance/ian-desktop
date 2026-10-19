import Client
import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

@MainActor
private func handoffStore(offered: Bool = true) async -> (
  store: IanStore, service: ScriptedService,
  feed: AsyncThrowingStream<StreamMessage, any Error>.Continuation
) {
  var me = Fixtures.me()
  me.capabilities.handoff = offered
  let service = ScriptedService(
    me: me,
    snapshots: [
      .success(
        Fixtures.snapshot(cursor: "10", items: [Fixtures.itemJSON(id: "task_1", version: 3)]))
    ])
  let feed = service.planStream()
  let store = IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
    jitter: { 1 })
  store.start()
  _ = await eventually("live") { await MainActor.run { store.connection == .live } }
  return (store, service, feed)
}

@Suite("Hand to Ian in the store")
@MainActor
struct HandoffTests {
  @Test("offers the hand-off only when the server's capabilities say so")
  func offeredByCapability() async {
    let on = await handoffStore(offered: true)
    defer { on.store.stop() }
    let off = await handoffStore(offered: false)
    defer { off.store.stop() }

    #expect(on.store.offersHandoff)
    #expect(!off.store.offersHandoff)
  }

  @Test("sends the instruction, trimmed, and marks the item pending without moving it")
  func sendsInstructionAndMarksPending() async {
    let (store, service, _) = await handoffStore()
    defer { store.stop() }

    await store.handOff(itemID: "task_1", instruction: "  Draft the reply first.\n")

    #expect(
      service.handoffCalls == [.init(itemID: "task_1", instruction: "Draft the reply first.")])
    #expect(
      store.pending["task_1"] == .init(actionID: "handoff", correlationID: "corr_h", sentVersion: 3)
    )
    #expect(store.state.items["task_1"]?.version == 3)
  }

  @Test("sends no instruction when none is given or the field is blank")
  func sendsNoInstruction() async {
    let (store, service, feed) = await handoffStore()
    defer { store.stop() }

    await store.handOff(itemID: "task_1", instruction: " \n ")
    feed.yield(
      .event(
        id: "11",
        Fixtures.event(Fixtures.removedJSON("task_1", correlationId: "corr_h"))))
    #expect(await eventually("cleared") { await MainActor.run { store.pending.isEmpty } })

    #expect(service.handoffCalls == [.init(itemID: "task_1", instruction: nil)])
  }

  @Test("clears the mark when the event carrying its correlation id arrives")
  func clearsOnCorrelatedEvent() async {
    let (store, _, feed) = await handoffStore()
    defer { store.stop() }
    await store.handOff(itemID: "task_1")

    feed.yield(
      .event(
        id: "11",
        Fixtures.event(
          Fixtures.upsertedJSON(Fixtures.itemJSON(id: "prop_9"), correlationId: "corr_h"))))

    #expect(await eventually("cleared") { await MainActor.run { store.pending.isEmpty } })
  }

  @Test("keeps the mark when the event carries another correlation id")
  func keepsMarkForOtherEvents() async {
    let (store, _, feed) = await handoffStore()
    defer { store.stop() }
    await store.handOff(itemID: "task_1")

    feed.yield(
      .event(
        id: "11",
        Fixtures.event(Fixtures.upsertedJSON(Fixtures.itemJSON(id: "prop_9"), correlationId: "x"))))
    _ = await eventually("event applied") {
      await MainActor.run { store.state.items["prop_9"] != nil }
    }

    #expect(store.pending["task_1"]?.correlationID == "corr_h")
  }

  @Test("does nothing when the server does not offer the hand-off")
  func refusedWhenNotOffered() async {
    let (store, service, _) = await handoffStore(offered: false)
    defer { store.stop() }

    await store.handOff(itemID: "task_1", instruction: "Go.")

    #expect(service.handoffCalls.isEmpty)
    #expect(store.pending.isEmpty)
  }

  @Test("does not send a second hand-off while the first is pending")
  func oneAtATime() async {
    let (store, service, _) = await handoffStore()
    defer { store.stop() }

    await store.handOff(itemID: "task_1")
    await store.handOff(itemID: "task_1", instruction: "Again")

    #expect(service.handoffCalls.count == 1)
  }

  @Test("refuses an instruction over 2000 characters and says why")
  func refusesLongInstruction() async {
    let (store, service, _) = await handoffStore()
    defer { store.stop() }

    await store.handOff(itemID: "task_1", instruction: String(repeating: "a", count: 2001))

    #expect(service.handoffCalls.isEmpty)
    #expect(store.pending.isEmpty)
    #expect(
      store.notices["task_1"] == .failed("Shorten the instruction to 2000 characters or fewer."))
  }

  @Test("counts the limit in Unicode scalars of the trimmed text, as the contract does")
  func limitCountsScalars() async {
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    let (store, service, _) = await handoffStore()
    defer { store.stop() }

    // 401 of these are 401 characters but 2005 scalars.
    await store.handOff(itemID: "task_1", instruction: " " + String(repeating: family, count: 401))
    #expect(service.handoffCalls.isEmpty)

    await store.handOff(itemID: "task_1", instruction: String(repeating: family, count: 400))
    #expect(service.handoffCalls.count == 1)
  }

  @Test("clears the mark and shows the reason when the call fails")
  func failureLeavesNotice() async {
    let (store, service, _) = await handoffStore()
    defer { store.stop() }
    service.planHandoff { _ in throw DesktopError.rejected(status: 404, detail: "Not offered.") }

    await store.handOff(itemID: "task_1")

    #expect(store.pending.isEmpty)
    guard case .failed? = store.notices["task_1"] else {
      Issue.record("expected a failure notice")
      return
    }
  }

  @Test("refuses while offline, with a notice, and sends nothing")
  func refusedWhileOffline() async {
    let (store, service, feed) = await handoffStore()
    defer { store.stop() }
    feed.finish(throwing: DesktopError.offline)
    _ = await eventually("offline") { await MainActor.run { store.connection == .offline } }

    await store.handOff(itemID: "task_1")

    #expect(service.handoffCalls.isEmpty)
    #expect(store.notices["task_1"] != nil)
  }
}
