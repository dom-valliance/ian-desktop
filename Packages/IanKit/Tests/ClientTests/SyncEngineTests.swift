import Contract
import Foundation
import TestSupport
import Testing

@testable import Client

private actor Collector {
  private(set) var updates: [SyncUpdate] = []
  private(set) var finished = false

  func run(_ stream: AsyncStream<SyncUpdate>) async {
    for await update in stream { updates.append(update) }
    finished = true
  }

  func count(where matches: (SyncUpdate) -> Bool) -> Int { updates.filter(matches).count }
}

private struct Rig {
  let service: ScriptedService
  let clock: ManualClock
  let collector: Collector
  let task: Task<Void, Never>

  func stop() { task.cancel() }

  func waitFor(_ description: String, _ matches: @escaping @Sendable (SyncUpdate) -> Bool) async
    -> Bool
  {
    await eventually(description) { await collector.count(where: matches) > 0 }
  }

  func waitForCount(_ count: Int, _ matches: @escaping @Sendable (SyncUpdate) -> Bool) async
    -> Bool
  {
    await eventually("\(count) updates") { await collector.count(where: matches) >= count }
  }
}

private func start(service: ScriptedService, jitter: Double = 1) -> Rig {
  let clock = ManualClock()
  let engine = SyncEngine(
    service: service, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0), clock: clock,
    jitter: { jitter })
  let collector = Collector()
  let stream = engine.updates()
  let task = Task { await collector.run(stream) }
  return Rig(service: service, clock: clock, collector: collector, task: task)
}

private let isConnected: @Sendable (SyncUpdate) -> Bool = { $0 == .connected }
private let isDisconnected: @Sendable (SyncUpdate) -> Bool = { $0 == .disconnected }
private let isSnapshot: @Sendable (SyncUpdate) -> Bool = {
  if case .snapshot = $0 { true } else { false }
}

private func removed(_ id: String, event eventID: String) -> StreamMessage {
  .event(id: eventID, Fixtures.event(Fixtures.removedJSON(id)))
}

@Test("fetches me and the snapshot, then streams from the snapshot cursor")
private func startsWithMeSnapshotThenStream() async throws {
  let service = ScriptedService(snapshots: [.success(Fixtures.snapshot(cursor: "10"))])
  let feed = service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }

  #expect(await rig.waitFor("connected", isConnected))
  feed.yield(removed("task_1", event: "11"))
  #expect(
    await rig.waitFor("the event") {
      $0 == .event(id: "11", Fixtures.event(Fixtures.removedJSON("task_1")))
    })

  let updates = await rig.collector.updates
  #expect(updates[0] == .me(Fixtures.me()))
  #expect(updates[1] == .snapshot(Fixtures.snapshot(cursor: "10")))
  #expect(updates[2] == .connected)
  #expect(updates[3] == .event(id: "11", Fixtures.event(Fixtures.removedJSON("task_1"))))
  #expect(service.streamCalls == ["10"])
}

@Test("reconnects with the last applied event id after the stream drops")
private func resumesFromLastEventID() async throws {
  let service = ScriptedService(snapshots: [.success(Fixtures.snapshot(cursor: "10"))])
  let first = service.planStream()
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))

  first.yield(removed("task_1", event: "11"))
  first.yield(removed("task_2", event: "12"))
  first.yield(.event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))
  first.finish(throwing: DesktopError.offline)

  #expect(await rig.waitFor("disconnected", isDisconnected))
  await rig.clock.advance(by: .seconds(1))
  #expect(await rig.waitForCount(2, isConnected))
  #expect(service.streamCalls == ["10", "12"])
  #expect(service.snapshotCalls == 1)
}

@Test("refetches the snapshot at once when the stream answers 410")
private func refetchesOnGone() async throws {
  let service = ScriptedService(
    snapshots: [
      .success(Fixtures.snapshot(cursor: "10")), .success(Fixtures.snapshot(cursor: "90")),
    ])
  service.planStreamFailure(.gone)
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }

  #expect(await rig.waitFor("connected", isConnected))

  #expect(service.streamCalls == ["10", "90"])
  #expect(service.snapshotCalls == 2)
  #expect(await rig.collector.count(where: isDisconnected) == 0)
  #expect(await rig.clock.requestedSleeps.filter { $0 < .seconds(55) }.isEmpty)
}

@Test("refetches the snapshot when a known event type does not decode")
private func refetchesOnUndecodableEvent() async throws {
  let service = ScriptedService(
    snapshots: [
      .success(Fixtures.snapshot(cursor: "10")), .success(Fixtures.snapshot(cursor: "50")),
    ])
  let first = service.planStream()
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))

  first.yield(.undecodable)

  #expect(await rig.waitForCount(2, isConnected))
  #expect(service.streamCalls == ["10", "50"])
  #expect(service.snapshotCalls == 2)
}

@Test("passes on nothing for an event of an unknown type and keeps the stream open")
private func skipsUnknownTypes() async throws {
  let service = ScriptedService()
  let feed = service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))

  feed.yield(.ignored)
  feed.yield(removed("task_1", event: "11"))
  #expect(
    await rig.waitFor("the event") {
      $0 == .event(id: "11", Fixtures.event(Fixtures.removedJSON("task_1")))
    })

  #expect(await rig.collector.updates.count == 4)
  #expect(service.streamCalls.count == 1)
}

@Test("waits with exponential backoff between failed reconnections")
private func backsOffBetweenFailures() async throws {
  let service = ScriptedService()
  for _ in 0..<4 { service.planStreamFailure(.offline) }
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }

  let backoffSleeps: @Sendable () async -> [Duration] = {
    await rig.clock.requestedSleeps.filter { $0 < .seconds(55) }
  }
  for step in 1...4 {
    #expect(await eventually("sleep \(step)") { await backoffSleeps().count == step })
    await rig.clock.advance(by: await backoffSleeps()[step - 1])
  }

  #expect(await rig.waitFor("connected", isConnected))
  #expect(await backoffSleeps() == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
}

@Test("treats a stream silent for longer than two heartbeats as dead")
private func detectsSilentStream() async throws {
  let service = ScriptedService()
  service.planStream()
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))

  await rig.clock.waitForSleepers(1)
  await rig.clock.advance(by: .seconds(56))

  #expect(await rig.waitFor("disconnected", isDisconnected))
}

@Test("keeps a stream that only sends heartbeats")
private func keepsStreamWithHeartbeats() async throws {
  let service = ScriptedService()
  let feed = service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))
  await rig.clock.waitForSleepers(1)

  for beat in 1...3 {
    await rig.clock.advance(by: .seconds(25))
    feed.yield(.event(id: nil, Fixtures.event(Fixtures.heartbeatJSON)))
    let seen = beat
    #expect(
      await eventually("heartbeat \(seen)") {
        await rig.collector.count(where: {
          $0 == .event(id: nil, Fixtures.event(Fixtures.heartbeatJSON))
        })
          == seen
      })
  }

  #expect(await rig.collector.count(where: isDisconnected) == 0)
  #expect(service.streamCalls.count == 1)
}

@Test("polls the snapshot every minute after a minute without the stream, and stops on return")
private func pollsWhileOffline() async throws {
  let service = ScriptedService(snapshots: [.success(Fixtures.snapshot(cursor: "10"))])
  let first = service.planStream()
  service.planStreamFailure(.offline)
  service.planStreamFailure(.offline)
  let returned = service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))

  first.finish(throwing: DesktopError.offline)
  #expect(await rig.waitFor("disconnected", isDisconnected))
  let sleptSixty: @Sendable (Int) async -> Bool = { count in
    await eventually("\(count) one-minute sleeps") {
      await rig.clock.requestedSleeps.filter { $0 == .seconds(60) }.count == count
    }
  }
  #expect(await sleptSixty(1))
  #expect(service.snapshotCalls == 1)

  await rig.clock.advance(by: .seconds(60))
  #expect(await eventually("first poll") { service.snapshotCalls == 2 })
  #expect(await sleptSixty(2))

  await rig.clock.advance(by: .seconds(60))
  #expect(await eventually("second poll") { service.snapshotCalls == 3 })
  #expect(await sleptSixty(3))

  await rig.clock.advance(by: .seconds(31))
  #expect(await rig.waitForCount(2, isConnected))
  await rig.clock.advance(by: .seconds(50))
  returned.yield(removed("task_1", event: "11"))
  #expect(
    await rig.waitFor("an event after the return") {
      $0 == .event(id: "11", Fixtures.event(Fixtures.removedJSON("task_1")))
    })

  #expect(service.snapshotCalls == 3)
  #expect(await rig.collector.count(where: isSnapshot) == 3)
}

@Test("starts over from the polled snapshot's cursor when the stream returns")
private func resumesFromPolledCursor() async throws {
  let service = ScriptedService(
    snapshots: [
      .success(Fixtures.snapshot(cursor: "10")), .success(Fixtures.snapshot(cursor: "40")),
    ])
  let first = service.planStream()
  service.planStreamFailure(.offline)
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }
  #expect(await rig.waitFor("connected", isConnected))
  first.finish(throwing: DesktopError.offline)
  #expect(await rig.waitFor("disconnected", isDisconnected))

  await rig.clock.advance(by: .seconds(60))
  #expect(await eventually("the poll") { service.snapshotCalls == 2 })
  #expect(await eventually("the next retry") { await rig.clock.requestedSleeps.count >= 4 })
  await rig.clock.advance(by: .seconds(10))

  #expect(await rig.waitForCount(2, isConnected))
  // The retry in the same step as the poll may see either cursor; the one after it must see 40.
  #expect(service.streamCalls.first == "10")
  #expect(service.streamCalls.last == "40")
}

@Test("stops with unauthorised and does not retry")
private func stopsOnUnauthorised() async throws {
  let service = ScriptedService()
  service.planStreamFailure(.unauthorised)
  let rig = start(service: service)
  defer { rig.stop() }

  #expect(await rig.waitFor("failure") { $0 == .failed(.unauthorised) })
  #expect(await eventually("the loop ends") { await rig.collector.finished })
  #expect(service.streamCalls.count == 1)
}

@Test("stops with upgradeRequired when me answers 426")
private func stopsOnUpgradeRequired() async throws {
  let service = ScriptedService()
  service.planMe(.failure(.upgradeRequired(minClientVersion: "9.0.0")))
  let rig = start(service: service)
  defer { rig.stop() }

  #expect(
    await rig.waitFor("failure") { $0 == .failed(.upgradeRequired(minClientVersion: "9.0.0")) })
  #expect(service.snapshotCalls == 0)
}

@Test("keeps retrying from the start while the first snapshot cannot be fetched")
private func retriesFirstSnapshot() async throws {
  let service = ScriptedService(
    snapshots: [.failure(.offline), .success(Fixtures.snapshot(cursor: "10"))])
  service.planStream()
  let rig = start(service: service)
  defer { rig.stop() }

  #expect(await rig.waitFor("disconnected", isDisconnected))
  await rig.clock.advance(by: .seconds(1))

  #expect(await rig.waitFor("connected", isConnected))
  #expect(service.streamCalls == ["10"])
  #expect(await rig.collector.count(where: { if case .me = $0 { true } else { false } }) == 1)
}

@Test("refuses to fetch any data when me reports a minimum version above the app's")
private func refusesBelowMinimumVersion() async throws {
  let service = ScriptedService(me: Fixtures.me(minClientVersion: "0.2.0"))
  let rig = start(service: service)
  defer { rig.stop() }

  #expect(
    await rig.waitFor("failure") { $0 == .failed(.upgradeRequired(minClientVersion: "0.2.0")) })
  #expect(service.snapshotCalls == 0)
  #expect(service.streamCalls.isEmpty)
}
