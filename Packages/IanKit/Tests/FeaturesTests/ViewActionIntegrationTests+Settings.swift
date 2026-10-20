import Auth
import Client
import Contract
import Foundation
import Store
import Testing

@testable import Features

private let mockOrigin = ProcessInfo.processInfo.environment["IAN_MOCK_URL"]

/// Added to the serialised suite, since two suites would load scenarios on the one mock at once.
extension ViewActionIntegrationTests {
  @Test("goes live through the settings model, after the dialog's dismissal has cancelled")
  func goingLiveThroughTheModel() async throws {
    let origin = URL(string: mockOrigin ?? "http://localhost:4317")!
    var request = URLRequest(url: origin.appending(path: "__mock/scenario"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(#"{"scenario":"quiet"}"#.utf8)
    _ = try await URLSession(configuration: .ephemeral).data(for: request)
    let store = IanStore(
      service: DesktopAPI(
        baseURL: origin.appending(path: "desktop/v1"), tokens: DevTokenProvider(),
        clientVersion: "0.1.0"),
      profile: .mock, appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    defer { store.stop() }
    let end = ContinuousClock.now.advanced(by: .seconds(30))
    while ContinuousClock.now < end, store.state.settings == nil || store.connection != .live {
      try await Task.sleep(for: .milliseconds(25))
    }
    let model = PrincipalSettingsModel(store: store)
    #expect(model.canGoLive)

    model.requestLive()
    model.cancelLive()
    await model.confirmLive()

    while ContinuousClock.now < end, store.state.settings?.mode != .live {
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(store.state.settings?.mode == .live)
  }
}
