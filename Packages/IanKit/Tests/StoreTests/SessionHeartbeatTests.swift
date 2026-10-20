import Client
import Contract
import Foundation
import TestSupport
import Testing

@testable import Store

private let launch = Date(timeIntervalSince1970: 1_792_137_600)
private let device = UUID(uuidString: "0F6B1C2E-3A4D-4E5F-8A9B-0C1D2E3F4A5B")!

@MainActor
private func makeStore(_ service: ScriptedService, version: String = "0.1.0") -> IanStore {
  IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion(version)!, clock: ManualClock(),
    jitter: { 1 }, now: { launch })
}

@MainActor
private func waitUntil(
  _ description: String, _ condition: @MainActor @escaping @Sendable () -> Bool
) async -> Bool {
  await eventually(description) { await MainActor.run { condition() } }
}

@MainActor
private func liveStore(version: String = "0.1.0") async -> (IanStore, ScriptedService) {
  let service = ScriptedService()
  service.planStream()
  let store = makeStore(service, version: version)
  store.start()
  _ = await waitUntil("live") { store.heartbeatSession != nil }
  return (store, service)
}

@Suite("Session heartbeat in the store")
@MainActor
struct SessionHeartbeatStoreTests {
  @Test("sends the device id, app version, flags and idle seconds as the contract names them")
  func sendsTheContractFields() async {
    let (store, service) = await liveStore(version: "0.4.2")
    defer { store.stop() }

    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 42)

    let sent = service.heartbeats
    #expect(sent.count == 1)
    #expect(sent.first?.deviceId == "0f6b1c2e-3a4d-4e5f-8a9b-0c1d2e3f4a5b")
    #expect(sent.first?.clientVersion == "0.4.2")
    #expect(sent.first?.active == true)
    #expect(sent.first?.suppressed == false)
    #expect(sent.first?.idleSeconds == 42)
  }

  @Test("never reports negative idle seconds")
  func clampsIdleSeconds() async {
    let (store, service) = await liveStore()
    defer { store.stop() }

    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: -3)

    #expect(service.heartbeats.first?.idleSeconds == 0)
  }

  @Test("sends nothing before the store is started")
  func silentBeforeStart() async {
    let service = ScriptedService()
    let store = makeStore(service)

    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)

    #expect(store.heartbeatSession == nil)
    #expect(service.heartbeats.isEmpty)
  }

  @Test("sends nothing while offline")
  func silentOffline() async {
    let service = ScriptedService()
    let feed = service.planStream()
    let store = makeStore(service)
    store.start()
    #expect(await waitUntil("live") { store.heartbeatSession != nil })
    defer { store.stop() }

    feed.finish(throwing: DesktopError.offline)
    #expect(await waitUntil("offline") { store.connection == .offline })
    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)

    #expect(store.heartbeatSession == nil)
    #expect(service.heartbeats.isEmpty)
  }

  @Test("sends nothing after sign-out")
  func silentSignedOut() async {
    let (store, service) = await liveStore()

    await store.signOut()
    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)

    #expect(store.heartbeatSession == nil)
    #expect(service.heartbeats.isEmpty)
  }

  @Test("a 401 sends the principal back to sign-in")
  func unauthorisedRequiresSignIn() async {
    let (store, service) = await liveStore()
    service.planHeartbeatResult(.failure(.unauthorised))

    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)

    #expect(store.phase == .signInRequired(message: nil))
    #expect(store.heartbeatSession == nil)
  }

  @Test("a 426 puts the store in the upgrade state with the minimum version")
  func upgradeRequired() async {
    let (store, service) = await liveStore()
    service.planHeartbeatResult(.failure(.upgradeRequired(minClientVersion: "9.0.0")))

    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)

    #expect(store.phase == .upgradeRequired(minimumVersion: "9.0.0"))
  }

  @Test("any other failure leaves the store running for the next heartbeat")
  func otherFailuresAreLogged() async {
    let (store, service) = await liveStore()
    defer { store.stop() }
    service.planHeartbeatResult(.failure(.offline))

    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)
    service.planHeartbeatResult(.success(()))
    await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)

    #expect(store.phase == .running)
    #expect(service.heartbeats.count == 2)
  }

  @Test("drops a failure that arrives after a sign-out")
  func staleFailureAfterSignOutIsDropped() async {
    let (store, service) = await liveStore()
    let gate = Gate()
    service.planHeartbeatHook { await gate.wait() }
    service.planHeartbeatResult(.failure(.upgradeRequired(minClientVersion: "9.0.0")))

    let send = Task {
      await store.sendHeartbeat(deviceID: device, active: true, suppressed: false, idleSeconds: 0)
    }
    #expect(await waitUntil("the heartbeat is out") { service.heartbeats.count == 1 })
    await store.signOut()
    await gate.open()
    await send.value

    #expect(store.phase == .signInRequired(message: nil))
    #expect(service.signIns == 0)
  }
}
