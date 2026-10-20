import AppKit
import Attention
import Client
import Contract
import Foundation
import Store
import Surface
import TestSupport
import Testing

@testable import Features

private let now = Date(timeIntervalSince1970: 1_792_137_600)

@Suite("Sidebar")
struct SidebarTests {
  @Test("lists the seven views in order")
  func sevenViews() {
    #expect(
      ClientSection.allCases.map(\.title)
        == ["Today", "Proposals", "Commitments", "Tasks", "Alerts", "Agents", "Settings"])
  }

  @Test("takes each count from views.counts and shows none for Settings")
  func countsFromViews() {
    let counts = TodayScenario.state.views?.counts

    let shown = ClientSection.allCases.map { $0.count(in: counts) }

    #expect(shown == [8, 2, 2, 3, 1, 4, nil])
  }

  @Test("shows no count before the first snapshot")
  func noCountsBeforeSnapshot() {
    #expect(ClientSection.allCases.allSatisfy { $0.count(in: nil) == nil })
  }
}

@Suite("Header")
struct ClientStatusTests {
  private func status(
    environment: String? = nil, phase: IanStore.Phase = .running,
    connection: IanStore.Connection = .live, updated: Date? = now, isSigningIn: Bool = false,
    at date: Date = now
  ) -> ClientStatus {
    ClientStatus(
      environmentName: environment, phase: phase, connection: connection, lastUpdatedAt: updated,
      isSigningIn: isSigningIn, now: date)
  }

  @Test("names no environment for the mock")
  func mockHasNoEnvironment() {
    #expect(status().environment == nil)
  }

  @Test("names the environment when the profile is not the mock")
  func namesEnvironment() {
    #expect(status(environment: "Lance dev").environment == "Lance dev")
  }

  @Test("shows no age while the connection is live")
  func noAgeWhenLive() {
    #expect(status(at: now.addingTimeInterval(300)).dataAge == nil)
  }

  @Test("shows how old the data is when the connection is not live")
  func ageWhenOffline() {
    let offline = status(connection: .offline, at: now.addingTimeInterval(120))
    #expect(offline.dataAge == "Data from 2 minutes ago")
    #expect(
      status(connection: .offline, at: now.addingTimeInterval(3600)).dataAge
        == "Data from 1 hour ago")
  }

  @Test("shows a moment rather than a number for fresh data")
  func freshData() {
    #expect(
      status(connection: .connecting, at: now.addingTimeInterval(1)).dataAge
        == "Data from a moment ago")
  }

  @Test("shows no age before there is any data")
  func noAgeWithoutData() {
    #expect(status(connection: .connecting, updated: nil).dataAge == nil)
  }

  @Test("raises a banner for offline, sign-in and upgrade states and none while live")
  func banners() {
    #expect(status().banner == nil)
    #expect(status(connection: .offline).banner == .offline)
    #expect(status(connection: .connecting).banner == .connecting)
    #expect(
      status(phase: .signInRequired(message: "No scope."), updated: nil).banner
        == .signInRequired(message: "No scope.", isSigningIn: false))
    #expect(
      status(phase: .upgradeRequired(minimumVersion: "0.2.0"), updated: nil).banner
        == .upgradeRequired(minimumVersion: "0.2.0"))
  }

  @Test("says what each banner means in words")
  func bannerMessages() {
    #expect(ClientStatus.Banner.offline.message.contains("actions are paused"))
    #expect(
      ClientStatus.Banner.signInRequired(message: nil, isSigningIn: true).message == "Signing in.")
    #expect(
      ClientStatus.Banner.signInRequired(message: "No scope.", isSigningIn: false).message
        == "No scope.")
    #expect(
      ClientStatus.Banner.upgradeRequired(minimumVersion: "0.2.0").message
        == "Update Ian to continue. The server needs version 0.2.0 or later.")
  }

  @Test("carries no item text in any line it shows")
  func noItemText() {
    let titles = TodayScenario.items.flatMap { [$0.title, $0.meta] }
    let lines = [
      status(environment: "Lance dev", connection: .offline, at: now.addingTimeInterval(90))
        .dataAge ?? "",
      ClientStatus.Banner.offline.message, ClientStatus.Banner.connecting.message,
    ]
    for line in lines {
      for title in titles { #expect(!line.contains(title)) }
    }
  }
}

@Suite("Navigation")
@MainActor
struct ClientModelTests {
  @Test("opens on Today")
  func opensOnToday() {
    withScratchDefaults { defaults in
      #expect(ClientModel(defaults: defaults).section == .today)
    }
  }

  @Test("shows the view that holds the item a notification named")
  func showsItemDestination() {
    withScratchDefaults { defaults in
      let model = ClientModel(defaults: defaults)
      let expected: [(ItemDestination, ClientSection)] = [
        (.alerts, .alerts), (.proposals, .proposals), (.commitments, .commitments),
        (.tasks, .tasks), (.today, .today),
      ]
      for (destination, section) in expected {
        model.show(destination)
        #expect(model.section == section)
      }
    }
  }

  @Test("keeps the last view and the selection when the panel is hidden and shown again")
  func remembersLastView() async {
    _ = NSApplication.shared
    let (store, _, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let defaults = UserDefaults(suiteName: "ian.tests.\(UUID().uuidString)")!
    let controller = SurfaceController(
      store: store, signals: SuppressionSignals(camera: IdleCamera()), defaults: defaults,
      quit: {})
    let model = ClientModel(defaults: defaults)
    controller.setExpandedContent(
      ExpandedClientView(store: store, controller: controller, model: model))
    let host = controller.windows[2].contentView

    model.section = .tasks
    model.today.select(.item("prop_a1"))
    controller.showExpanded()
    controller.hideExpanded()
    controller.showExpanded()

    #expect(controller.windows[2].contentView === host)
    #expect(model.section == .tasks)
    #expect(model.today.selection == .item("prop_a1"))
    controller.hideExpanded()
  }
}

@MainActor
final class IdleCamera: CameraMonitoring {
  var isLive = false
  func start(onChange: @escaping @MainActor () -> Void) {}
  func stop() {}
}
