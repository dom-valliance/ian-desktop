import Foundation
import Testing

@testable import Store

/// Added to the existing integration suite, which is serialised: every test drives the one shared
/// mock.
extension StoreIntegrationTests {
  /// An item the mock's world does not hold, copied from one it does. Sent as an event it lives
  /// only in the mock's event log, so a snapshot can never contain it: finding it in the store
  /// shows it arrived by replay, and missing it after a refetch shows the snapshot replaced it.
  private func logOnlyItem(copying item: [String: Any], suffix: String) -> [String: Any] {
    var copy = item
    copy["id"] = "task_missed_\(suffix)"
    copy["title"] = "Logged only \(suffix)"
    return copy
  }

  private func emit(_ event: [String: Any]) async throws {
    _ = try await mock.post("__mock/emit", ["event": event])
  }

  /// The first item of the mock's snapshot, as the mock sent it, so the copy carries valid dates.
  private func snapshotItem() async throws -> [String: Any] {
    let snapshot = try await mock.get("desktop/v1/snapshot")
    let items = try #require(snapshot["items"] as? [[String: Any]])
    return try #require(items.first)
  }

  /// Takes the stream down, logs an event the client has not seen, moves the mock's clock past the
  /// replay window so that event ages out, and brings the stream back. The client's id is then
  /// below the window, so the stream answers 410.
  private func outlastReplayWindow(store: IanStore, template: [String: Any]) async throws {
    try await mock.use(scenario: "offline")
    #expect(await settles("offline") { store.connection == .offline })
    try await emit([
      "type": "item.upserted", "item": logOnlyItem(copying: template, suffix: "d"),
    ])
    _ = try await mock.post("__mock/clock", ["advanceSeconds": 25 * 3600])
    try await mock.use(scenario: "normal")
    #expect(await settles("live again") { store.connection == .live })
  }

  /// The mock is shared, so a test that moves its clock puts it back, or later tests that mix the
  /// mock's time with the Mac's would find the world in the future.
  private func restoreClock(to time: String) async {
    _ = try? await mock.post("__mock/clock", ["set": time])
  }

  @Test("resumes from the last event id after an outage and applies the missed events in order")
  func resumesFromLastEventID() async throws {
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    defer { store.stop() }
    #expect(await settles("live") { store.connection == .live })
    let template = try await snapshotItem()

    try await mock.use(scenario: "offline")
    #expect(await settles("offline") { store.connection == .offline })
    let seen = try #require(store.state.lastEventID)

    // Three events the client cannot receive: A and B arrive, then A is removed. Applied in this
    // order A leaves a removal record and B stays; applied in any other order A would stay.
    try await emit(["type": "item.upserted", "item": logOnlyItem(copying: template, suffix: "a")])
    try await emit(["type": "item.upserted", "item": logOnlyItem(copying: template, suffix: "b")])
    try await emit([
      "type": "item.removed", "itemId": "task_missed_a", "outcome": "Settled while offline.",
    ])
    let latest = try #require(try await mock.get("__mock/state")["latestEventId"] as? Int)
    #expect(UInt64(latest) > seen)

    try await mock.use(scenario: "normal")
    #expect(await settles("live again") { store.connection == .live })
    let latestAfter = try #require(try await mock.get("__mock/state")["latestEventId"] as? Int)
    #expect(
      await settles("every missed event applied") { store.state.lastEventID == UInt64(latestAfter) }
    )

    #expect(store.state.items["task_missed_b"] != nil)
    #expect(store.state.items["task_missed_a"] == nil)
    #expect(store.removals["task_missed_a"]?.outcome == "Settled while offline.")
  }

  @Test("fetches the snapshot again when the outage outlasts the replay window")
  func refetchesAfterTheReplayWindow() async throws {
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    defer { store.stop() }
    #expect(await settles("live") { store.connection == .live })

    let template = try await snapshotItem()

    // Delivered live now, so the store holds it; the mock's world does not, so any snapshot
    // replaces it.
    try await emit([
      "type": "item.upserted", "item": logOnlyItem(copying: template, suffix: "c"),
    ])
    #expect(await settles("the logged item") { store.state.items["task_missed_c"] != nil })

    let before = try #require(try await mock.get("__mock/state")["now"] as? String)
    do {
      try await outlastReplayWindow(store: store, template: template)
    } catch {
      await restoreClock(to: before)
      throw error
    }
    await restoreClock(to: before)

    #expect(
      await settles("the snapshot replaced the held data") {
        store.state.items["task_missed_c"] == nil
      })
    #expect(store.state.items["task_missed_d"] == nil)
    let latest = try #require(try await mock.get("__mock/state")["latestEventId"] as? Int)
    #expect(
      await settles("resumed from the snapshot's cursor") {
        (store.state.lastEventID ?? 0) >= UInt64(latest)
      })
  }

  @Test("keeps the data and reports its age while the stream is down")
  func reportsTheAgeWhileDisconnected() async throws {
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    defer { store.stop() }
    #expect(await settles("live") { store.connection == .live && !store.state.items.isEmpty })

    try await mock.use(scenario: "offline")
    #expect(await settles("offline") { store.connection == .offline })
    let confirmed = try #require(store.lastUpdatedAt)
    try await Task.sleep(for: .milliseconds(1_500))

    #expect(store.lastUpdatedAt == confirmed)
    #expect(!store.state.items.isEmpty)
    let age = try #require(store.dataAge(at: confirmed.addingTimeInterval(120)))
    #expect(age == 120)
    #expect(!store.actionsEnabled)
  }
}
