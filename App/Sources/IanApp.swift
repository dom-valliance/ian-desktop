import AppKit
import Client
import Foundation
import Store
import Surface
import SwiftUI
import os

@main
struct IanApp: App {
  @State private var store: IanStore

  init() {
    let store = Self.makeStore()
    _store = State(initialValue: store)
    store.start()
  }

  var body: some Scene {
    MenuBarExtra("Ian") {
      MenuBarMenu(store: store)
    }
  }

  /// Wires the profile, the token provider, the HTTP client and the store.
  private static func makeStore() -> IanStore {
    let log = Logger(subsystem: "ai.valliance.ian.desktop", category: "launch")
    let profile: EnvironmentProfile
    do {
      profile = try EnvironmentProfile.resolve()
    } catch {
      log.error("\(error.localizedDescription, privacy: .public) Starting on the mock profile.")
      profile = .mock
    }
    let bundle = Bundle.main
    let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let version =
      versionText.flatMap(SemanticVersion.init) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    let tokens = profile.makeTokenProvider(
      bundleIdentifier: bundle.bundleIdentifier ?? "ai.valliance.ian.desktop",
      openURL: { url in
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
      })
    let service = DesktopAPI(profile: profile, tokens: tokens, clientVersion: version.description)
    return IanStore(service: service, profile: profile, appVersion: version)
  }
}
