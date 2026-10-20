import Attention
import Foundation
import Observation
import Testing

@testable import Store

@MainActor
@Observable
private final class Suppressed {
  var value = false
}

/// What `GET /__mock/sessions` holds for one device, oldest first. The mock stamps `receivedAt`
/// from its own clock, which stands still unless a test moves it, so the tests below read count,
/// order and fields and never the stamp.
private struct Received: Equatable {
  let clientVersion: String
  let active: Bool
  let suppressed: Bool
  let idleSeconds: Int
}

private func received(from origin: URL, device: UUID) async throws -> [Received] {
  let (data, _) = try await URLSession(configuration: .ephemeral).data(
    from: origin.appending(path: "__mock/sessions"))
  let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  let sessions = try #require(body["sessions"] as? [[String: Any]])
  return sessions.compactMap { entry in
    guard entry["deviceId"] as? String == device.uuidString.lowercased(),
      let version = entry["clientVersion"] as? String, let active = entry["active"] as? Bool,
      let suppressed = entry["suppressed"] as? Bool, let idle = entry["idleSeconds"] as? Int
    else { return nil }
    return Received(
      clientVersion: version, active: active, suppressed: suppressed, idleSeconds: idle)
  }
}

/// Added to the existing integration suite, which is serialised: every test drives the one shared
/// mock.
extension StoreIntegrationTests {
  @Test("sends heartbeats to the mock at the interval, and an extra one when suppression changes")
  func heartbeatsReachTheMock() async throws {
    let origin = mock.origin
    try await mock.use(scenario: "normal")
    let store = mock.startStore()
    let suppressed = Suppressed()
    let reporter = HeartbeatReporter(
      store: store, timing: HeartbeatTiming(interval: .seconds(2), checkInterval: .seconds(1)),
      activity: StillActivity(), suppressed: { suppressed.value })
    reporter.start()
    defer {
      reporter.stop()
      store.stop()
    }
    let device = reporter.deviceID

    // The first goes once the snapshot is in, and the second two seconds after it.
    #expect(await receives(origin, device, timeout: .seconds(30)) { $0.count == 2 })
    // Nothing extra arrives inside the interval, then the third arrives on schedule.
    try await Task.sleep(for: .milliseconds(1200))
    #expect(try await received(from: origin, device: device).count == 2)
    #expect(await receives(origin, device, timeout: .seconds(2)) { $0.count == 3 })

    suppressed.value = true
    // The change goes at once, well before the next periodic heartbeat is due.
    #expect(await receives(origin, device, timeout: .seconds(1)) { $0.count == 4 })

    let all = try await received(from: origin, device: device)
    #expect(all.map(\.suppressed) == [false, false, false, true])
    #expect(all.allSatisfy { $0.clientVersion == "0.1.0" && $0.active && $0.idleSeconds == 0 })
  }

  private func receives(
    _ origin: URL, _ device: UUID, timeout: Duration, _ condition: ([Received]) -> Bool
  ) async -> Bool {
    let end = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < end {
      if let all = try? await received(from: origin, device: device), condition(all) {
        return true
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return false
  }
}
