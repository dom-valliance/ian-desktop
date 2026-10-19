import AppKit
import Attention
import Client
import Contract
import SnapshotTesting
import Store
import Surface
import SwiftUI
import TestSupport
import Testing

@testable import Features

/// The login item stands in for the system's, so no test touches the real login items.
@MainActor
private final class StubLogin: LaunchAtLoginControlling {
  var status: LaunchAtLoginStatus = .disabled
  func register() throws {}
  func unregister() throws {}
}

/// Agents and Settings drawn from the scenario fixtures at 640 by 720 points, hosted as the view
/// snapshots are: in an `NSHostingView` that never enters a window.
@Suite("Agents and Settings snapshots")
@MainActor
struct AgentsSettingsSnapshotTests {
  private static let size = CGSize(width: 640, height: 720)
  /// A fixed clock, so the diagnostics lines do not move between runs.
  private nonisolated static let fixedNow = Date(timeIntervalSince1970: 1_792_137_600)

  /// A store that has loaded the scenario's snapshot, with a profile switcher so the environment
  /// picker has its choices. Times follow the fixture's `me.timeZone`. The caller stops it.
  private func store(
    _ name: String, settings: Components.Schemas.Settings? = nil
  ) async -> IanStore {
    let scenario = ViewScenario.load(name)
    var snapshot = Fixtures.snapshot()
    snapshot.today = scenario.today
    snapshot.views = scenario.views
    snapshot.items = scenario.items
    snapshot.agents = scenario.agents
    snapshot.settings = settings ?? scenario.settings
    let store = IanStore(
      service: ScriptedService(me: scenario.me, snapshots: [.success(snapshot)]), profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0), now: { Self.fixedNow },
      profileSwitcher: ProfileSwitcher(
        choices: EnvironmentProfile.Name.allCases.map {
          ProfileChoice(id: $0.rawValue, displayName: $0.displayName)
        },
        build: { _ in nil }, remember: { _ in }))
    store.start()
    _ = await eventually("live") {
      await MainActor.run { store.connection == .live && store.state.settings != nil }
    }
    return store
  }

  private func image(of view: some View, size: CGSize = Self.size) -> NSImage {
    let hosting = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height)
        .background(ClientPalette.ground).foregroundStyle(ClientPalette.text)
        .environment(\.colorScheme, .dark))
    hosting.appearance = NSAppearance(named: .darkAqua)
    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
      preconditionFailure("The view did not produce a bitmap.")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }

  private func check(_ image: NSImage, named name: String) {
    assertSnapshot(
      of: image, as: .image(precision: 0.998, perceptualPrecision: 0.98), named: name,
      testName: "agents-settings")
  }

  /// Settings with a controller that never shows a window, scratch defaults and stubs for the
  /// login item and the pasteboard.
  /// The view holds its controller weakly, so the caller keeps the controller alive.
  private func controller(_ store: IanStore, defaults: UserDefaults) -> SurfaceController {
    _ = NSApplication.shared
    return SurfaceController(
      store: store, signals: SuppressionSignals(camera: IdleCamera()), defaults: defaults,
      quit: {})
  }

  private func settingsView(_ store: IanStore, controller: SurfaceController) -> SettingsView {
    SettingsView(
      store: store, controller: controller,
      model: SettingsModel(launchAtLogin: StubLogin(), copy: { _ in }))
  }

  @Test("draws Agents in normal, at the panel's width and wide enough to show every column")
  func agentsNormal() async {
    let store = await store("normal")
    defer { store.stop() }
    check(image(of: AgentsView(store: store)), named: "agents-normal")
    check(
      image(of: AgentsView(store: store), size: CGSize(width: 1000, height: 720)),
      named: "agents-normal-wide")
  }

  @Test("draws Agents in incident with the kill switch banner")
  func agentsIncident() async {
    let store = await store("incident")
    defer { store.stop() }
    #expect(store.state.settings?.global.paused == true)
    check(image(of: AgentsView(store: store)), named: "agents-incident")
  }

  @Test("draws Settings in normal, at the top and in full")
  func settingsNormal() async {
    let store = await store("normal")
    defer { store.stop() }
    await withScratchDefaultsAsync { defaults in
      let controller = controller(store, defaults: defaults)
      let view = settingsView(store, controller: controller)
      check(image(of: view), named: "settings-normal")
      check(image(of: view, size: CGSize(width: 640, height: 1400)), named: "settings-normal-full")
    }
  }

  @Test("draws Settings with the switch to live enabled")
  func settingsLiveEligible() async {
    let eligible = ViewScenario.load("normal").settings
    var settings = eligible
    settings.liveEligible = true
    settings.liveOpensAt = nil
    let store = await store("normal", settings: settings)
    defer { store.stop() }
    await withScratchDefaultsAsync { defaults in
      let controller = controller(store, defaults: defaults)
      check(
        image(
          of: settingsView(store, controller: controller), size: CGSize(width: 640, height: 1400)),
        named: "settings-live-eligible")
    }
  }
}
