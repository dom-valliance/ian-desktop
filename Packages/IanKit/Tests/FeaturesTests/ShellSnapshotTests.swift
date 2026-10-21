import AppKit
import Contract
import Foundation
import Store
import SwiftUI
import Testing

@testable import Features

/// The expanded client's header with each banner, and the sidebar with its counts. The header is
/// drawn from a status built at a fixed time, so the data's age never depends on the clock.
@Suite("Shell snapshots")
@MainActor
struct ShellSnapshotTests {
  private static let now = Date(timeIntervalSince1970: 1_792_137_600)
  private static let headerSize = CGSize(width: 640, height: 100)
  private static let sidebarSize = CGSize(width: 220, height: 340)

  private func header(
    environment: String? = nil, phase: IanStore.Phase = .running,
    connection: IanStore.Connection = .live, updatedSecondsAgo: TimeInterval? = nil,
    isSigningIn: Bool = false
  ) -> some View {
    VStack(spacing: 0) {
      ClientHeaderBar(
        status: ClientStatus(
          environmentName: environment, phase: phase, connection: connection,
          lastUpdatedAt: updatedSecondsAgo.map { Self.now.addingTimeInterval(-$0) },
          isSigningIn: isSigningIn, now: Self.now),
        signIn: {}, close: {})
      Spacer(minLength: 0)
    }
  }

  private func checkHeader(_ view: some View, named name: String) {
    SnapshotHarness.check(
      SnapshotHarness.image(of: view, size: Self.headerSize), named: name, testName: "shell")
  }

  @Test("draws the header live with no banner, and with the environment named")
  func headerLive() {
    checkHeader(header(), named: "header-live")
    checkHeader(header(environment: "Lance dev"), named: "header-live-environment")
  }

  @Test("draws the header while connecting")
  func headerConnecting() {
    checkHeader(header(connection: .connecting), named: "header-connecting")
  }

  @Test("draws the offline banner with the age of the data on show")
  func headerStale() {
    checkHeader(
      header(connection: .offline, updatedSecondsAgo: 120), named: "header-offline-stale")
    checkHeader(
      header(environment: "Lance dev", connection: .offline, updatedSecondsAgo: 7_500),
      named: "header-offline-stale-hours")
  }

  @Test("draws the sign-in banner, while signing in and after a failure")
  func headerSignIn() {
    checkHeader(header(phase: .signInRequired(message: nil)), named: "header-sign-in")
    checkHeader(
      header(phase: .signInRequired(message: nil), isSigningIn: true),
      named: "header-signing-in")
    checkHeader(
      header(phase: .signInRequired(message: "The sign-in window was closed. Try again.")),
      named: "header-sign-in-failed")
  }

  @Test("draws the upgrade banner with and without the server's minimum version")
  func headerUpgrade() {
    checkHeader(
      header(phase: .upgradeRequired(minimumVersion: "0.2.0")), named: "header-upgrade")
    checkHeader(
      header(phase: .upgradeRequired(minimumVersion: nil)), named: "header-upgrade-unversioned")
  }

  private func checkSidebar(
    counts: Components.Schemas.ViewCounts?, selection: ClientSection, named name: String
  ) {
    SnapshotHarness.check(
      SnapshotHarness.image(
        of: SidebarView(counts: counts, width: 220, selection: .constant(selection)),
        size: Self.sidebarSize, inWindow: true),
      named: name, testName: "shell")
  }

  @Test("draws the sidebar with the server's counts for each scenario")
  func sidebarCounts() {
    checkSidebar(
      counts: ViewScenario.load("normal").views.counts, selection: .today,
      named: "sidebar-normal")
    checkSidebar(
      counts: ViewScenario.load("incident").views.counts, selection: .alerts,
      named: "sidebar-incident-alerts")
    checkSidebar(
      counts: ViewScenario.load("quiet").views.counts, selection: .proposals,
      named: "sidebar-quiet")
  }

  @Test("draws the sidebar without counts before the first snapshot")
  func sidebarBeforeSnapshot() {
    checkSidebar(counts: nil, selection: .today, named: "sidebar-no-counts")
  }
}
