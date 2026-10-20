import Attention
import Auth
import Client
import Foundation
import Observation
import Testing

@testable import Store

/// These run only against a live mock server. Start it, then run
/// `IAN_MOCK_URL=http://localhost:4317 swift test --filter Integration`.
private let mockOrigin = ProcessInfo.processInfo.environment["IAN_MOCK_URL"]

@MainActor
private final class Still: ActivityMonitoring {
  var isActive = true
  var idleSeconds = 0
  func start(onChange: @escaping @MainActor () -> Void) {}
  func stop() {}
}

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
  @Test("sends periodic heartbeats to the mock and an extra one when suppression changes")
  func heartbeatsReachTheMock() async throws {
    let origin = try #require(mockOrigin.flatMap { URL(string: $0) })
    _ = try await post("__mock/scenario", ["scenario": "normal"], to: origin)
    let store = IanStore(
      service: DesktopAPI(
        baseURL: origin.appending(path: "desktop/v1"), tokens: DevTokenProvider(),
        clientVersion: "0.1.0"),
      profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    let suppressed = Suppressed()
    let reporter = HeartbeatReporter(
      store: store,
      timing: HeartbeatTiming(interval: .seconds(2), checkInterval: .seconds(1)),
      activity: Still(), suppressed: { suppressed.value })
    reporter.start()
    defer {
      reporter.stop()
      store.stop()
    }

    // The first goes once the snapshot is in, and the periodic one follows two seconds later.
    #expect(await settlesOnReceipt(origin, reporter.deviceID) { $0.count >= 2 })
    suppressed.value = true
    // The change goes at once, well before the next periodic heartbeat is due.
    #expect(
      await settlesOnReceipt(origin, reporter.deviceID, timeout: .seconds(1)) {
        $0.last?.suppressed == true
      })

    let all = try await received(from: origin, device: reporter.deviceID)
    #expect(all.dropLast().allSatisfy { !$0.suppressed })
    #expect(all.last?.suppressed == true)
    #expect(all.count >= 3)
    #expect(
      all.allSatisfy { $0.clientVersion == "0.1.0" && $0.active && $0.idleSeconds == 0 })
  }

  private func settlesOnReceipt(
    _ origin: URL, _ device: UUID, timeout: Duration = .seconds(30),
    _ condition: ([Received]) -> Bool
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

  private func post(_ path: String, _ body: [String: String], to origin: URL) async throws
    -> Data
  {
    var request = URLRequest(url: origin.appending(path: path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    try #require((response as? HTTPURLResponse)?.statusCode == 200)
    return data
  }
}
