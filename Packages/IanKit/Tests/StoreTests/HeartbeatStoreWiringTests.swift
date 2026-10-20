import Attention
import Client
import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

/// An activity monitor that never changes: active, and at the keyboard.
@MainActor
final class StillActivity: ActivityMonitoring {
  var isActive = true
  var idleSeconds = 0
  func start(onChange: @escaping @MainActor () -> Void) {}
  func stop() {}
}

func manualTime(_ clock: ManualClock) -> HeartbeatTime {
  HeartbeatTime(now: { await clock.now() }, sleep: { try await clock.sleep(for: $0) })
}

@MainActor
private func makeStore(
  _ service: ScriptedService, switchingTo next: ScriptedService? = nil
) -> IanStore {
  let switcher = ProfileSwitcher(
    choices: [ProfileChoice(id: "lance-dev", displayName: "Lance dev")],
    build: { _ in
      next.map { (.lanceDev(entra: .init(tenantID: "t", clientID: "c", scope: "s")), $0) }
    },
    remember: { _ in })
  return IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
    jitter: { 1 }, profileSwitcher: switcher)
}

@Suite("Heartbeat reporter on the store")
@MainActor
struct HeartbeatStoreWiringTests {
  @Test("sends the first heartbeat after the first snapshot, and none before it")
  func firstHeartbeatFollowsTheSnapshot() async {
    let service = ScriptedService()
    service.planStream()
    let store = makeStore(service)
    let reporter = HeartbeatReporter(
      store: store, time: manualTime(ManualClock()), activity: StillActivity(),
      suppressed: { false })
    reporter.start()
    defer {
      reporter.stop()
      store.stop()
    }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(service.heartbeats.isEmpty)

    store.start()

    #expect(await eventually("the first heartbeat") { service.heartbeats.count == 1 })
    #expect(service.heartbeats.first?.clientVersion == "0.1.0")
    #expect(service.heartbeats.first?.deviceId == reporter.deviceID.uuidString.lowercased())
  }

  @Test("stops on sign-out and sends from the new profile with the same device id")
  func profileSwitchKeepsTheDevice() async {
    let first = ScriptedService()
    first.planStream()
    let second = ScriptedService()
    second.planStream()
    let store = makeStore(first, switchingTo: second)
    let reporter = HeartbeatReporter(
      store: store, time: manualTime(ManualClock()), activity: StillActivity(),
      suppressed: { false })
    reporter.start()
    defer {
      reporter.stop()
      store.stop()
    }
    store.start()
    #expect(await eventually("the first profile's heartbeat") { first.heartbeats.count == 1 })

    await store.signOut()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(first.heartbeats.count == 1)

    await store.switchProfile(to: "lance-dev")

    #expect(await eventually("the second profile's heartbeat") { second.heartbeats.count == 1 })
    #expect(second.heartbeats.first?.deviceId == first.heartbeats.first?.deviceId)
  }
}
