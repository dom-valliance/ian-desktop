import Client
import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

private let epoch = Date(timeIntervalSince1970: 1_792_137_600)

@MainActor
private func liveStore(
  settings: Fixtures.Schemas.Settings = Fixtures.settings(), service: ScriptedService? = nil
) async -> (
  store: IanStore, service: ScriptedService,
  feed: AsyncThrowingStream<StreamMessage, any Error>.Continuation
) {
  var snapshot = Fixtures.snapshot(cursor: "10")
  snapshot.settings = settings
  let service = service ?? ScriptedService(snapshots: [.success(snapshot)])
  let feed = service.planStream()
  let store = IanStore(
    service: service, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
    jitter: { 1 }, now: { epoch })
  store.start()
  _ = await eventually("live") { await MainActor.run { store.connection == .live } }
  return (store, service, feed)
}

@Suite("Principal settings")
@MainActor
struct PrincipalSettingsTests {
  @Test("starts its drafts from the server's values")
  func draftsStartFromTheServer() async {
    let (store, _, _) = await liveStore()
    defer { store.stop() }

    let model = PrincipalSettingsModel(store: store)

    #expect(model.quietStart == "19:00")
    #expect(model.quietEnd == "07:00")
    #expect(model.pushBudget == 3)
  }

  @Test("sends quiet hours as the one field changed")
  func quietHoursPatch() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)
    model.quietStart = "20:30"
    model.quietEnd = "06:00"

    await model.applyQuietHours()

    #expect(service.settingsPatches == [.init(quietHours: .init(start: "20:30", end: "06:00"))])
    #expect(store.state.settings?.quietHours.start == "19:00")
  }

  @Test("sends the push budget, held to 0 through 50")
  func pushBudgetPatch() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)
    model.pushBudget = 12

    await model.applyPushBudget()

    #expect(service.settingsPatches == [.init(pushBudgetPerHour: 12)])
    #expect(store.state.settings?.pushBudgetPerHour == 3)
  }

  @Test("sends the own pause with its reason, and leaves the reason out when empty")
  func ownPausePatch() async {
    let (store, service, _) = await liveStore()
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)
    model.pauseReason = "  On leave  "

    await model.setOwnPause(true)
    store.dismissSettingsNotice()
    model.pauseReason = ""
    // The first change is still waiting on its event, so a second is held back.
    await model.setOwnPause(true)

    #expect(service.settingsPatches == [.init(paused: true, pausedReason: "On leave")])
  }

  @Test("sends a resume without a reason")
  func resumePatch() async {
    let (store, service, _) = await liveStore(
      settings: Fixtures.settings(paused: true, pausedReason: "On leave"))
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)
    #expect(model.pauseReason == "On leave")

    await model.setOwnPause(false)

    #expect(service.settingsPatches == [.init(paused: false)])
  }

  @Test("disables the switch to live unless the server says it is eligible")
  func liveNeedsEligibility() async {
    let (store, service, _) = await liveStore(
      settings: Fixtures.settings(liveEligible: false, liveOpensAt: "2026-10-23T08:00:00.000Z"))
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)

    #expect(!model.canGoLive)
    model.requestLive()
    #expect(!model.isConfirmingLive)
    await model.confirmLive()
    #expect(service.settingsPatches.isEmpty)
    #expect(model.liveUnavailableReason == "Going live opens on 23 October 2026 at 9:00.")
  }

  @Test("says going live is not allowed yet when the server gives no time")
  func liveWithoutATime() async {
    let (store, _, _) = await liveStore()
    defer { store.stop() }

    #expect(
      PrincipalSettingsModel(store: store).liveUnavailableReason
        == "Going live is not allowed yet.")
  }

  @Test("asks for confirmation before it sends the switch to live")
  func liveAsksFirst() async {
    let (store, service, _) = await liveStore(settings: Fixtures.settings(liveEligible: true))
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)
    #expect(model.canGoLive)

    model.requestLive()
    #expect(model.isConfirmingLive)
    #expect(service.settingsPatches.isEmpty)

    await model.confirmLive()
    #expect(!model.isConfirmingLive)
    #expect(service.settingsPatches == [.init(mode: .live)])
  }

  @Test("sends nothing when the principal cancels the confirmation")
  func cancellingSendsNothing() async {
    let (store, service, _) = await liveStore(settings: Fixtures.settings(liveEligible: true))
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)

    model.requestLive()
    model.cancelLive()
    await model.confirmLive()

    #expect(service.settingsPatches.isEmpty)
  }

  @Test("returns to dry run without asking")
  func returnsToDryRun() async {
    let (store, service, _) = await liveStore(settings: Fixtures.settings(mode: "live"))
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)

    await model.returnToDryRun()

    #expect(service.settingsPatches == [.init(mode: .dryRun)])
  }

  @Test("shows the server's refusal of a change")
  func showsARefusal() async {
    let (store, service, _) = await liveStore(settings: Fixtures.settings(liveEligible: true))
    defer { store.stop() }
    service.planSettingsPatch(
      .failure(.rejected(status: 422, detail: "Going live is closed this week.")))
    let model = PrincipalSettingsModel(store: store)
    model.requestLive()

    await model.confirmLive()

    #expect(model.notice == "Going live is closed this week.")
    #expect(!model.isPending)
  }

  @Test("puts the drafts back to the server's values when settings.updated moves them")
  func drafsFollowTheServer() async {
    let (store, _, feed) = await liveStore()
    defer { store.stop() }
    let model = PrincipalSettingsModel(store: store)
    model.pushBudget = 40

    feed.yield(.event(id: "11", Fixtures.event(Fixtures.settingsUpdatedJSON(pushBudget: 9))))
    _ = await eventually("the event") {
      await MainActor.run { store.state.settings?.pushBudgetPerHour == 9 }
    }
    model.syncFromServer()

    #expect(model.pushBudget == 9)
  }

  @Test("converts a time of day to and from a picker's date")
  func timesRoundTrip() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    let date = PrincipalSettingsModel.date(fromTime: "07:45", calendar: calendar)

    #expect(PrincipalSettingsModel.time(from: date, calendar: calendar) == "07:45")
  }
}

@MainActor
private final class FakeLogin: LaunchAtLoginControlling {
  var status: LaunchAtLoginStatus = .disabled
  var failure: (any Error)?
  private(set) var registered = 0
  private(set) var unregistered = 0

  func register() throws {
    if let failure { throw failure }
    registered += 1
    status = .enabled
  }

  func unregister() throws {
    if let failure { throw failure }
    unregistered += 1
    status = .disabled
  }
}

private struct RefusedError: LocalizedError {
  var errorDescription: String? { "The system refused." }
}

@Suite("Launch at login")
@MainActor
struct LaunchAtLoginTests {
  @Test("registers and unregisters through the service and shows its status")
  func togglesTheService() {
    let login = FakeLogin()
    let model = LaunchAtLoginModel(service: login)
    #expect(!model.isOn)

    model.set(enabled: true)
    #expect(login.registered == 1)
    #expect(model.isOn)
    #expect(model.message == "Ian opens when you log in.")

    model.set(enabled: false)
    #expect(login.unregistered == 1)
    #expect(!model.isOn)
  }

  @Test("explains what to do when an unsigned build cannot register")
  func explainsAFailure() {
    let login = FakeLogin()
    login.failure = RefusedError()
    let model = LaunchAtLoginModel(service: login)

    model.set(enabled: true)

    #expect(!model.isOn)
    #expect(model.message.contains("The system refused."))
    #expect(model.message.contains("run a signed build"))
  }

  @Test("says where to approve it when the system asks for approval")
  func asksForApproval() {
    let login = FakeLogin()
    login.status = .requiresApproval
    let model = LaunchAtLoginModel(service: login)

    #expect(model.message.contains("Login Items"))
  }

  @Test("says an unsigned build cannot register when the system does not know it")
  func unavailable() {
    let model = LaunchAtLoginModel(service: NoLaunchAtLogin())

    #expect(model.message.contains("cannot register"))
  }
}

@Suite("Client settings actions")
@MainActor
struct SettingsModelTests {
  private func model(copy: @escaping (String) -> Void = { _ in }) -> SettingsModel {
    SettingsModel(launchAtLogin: NoLaunchAtLogin(), copy: copy)
  }

  private func switchingStore(
    next: ScriptedService, remembered: Remembered
  ) async -> (IanStore, ScriptedService) {
    let first = ScriptedService()
    first.planStream()
    next.planStream()
    let switcher = ProfileSwitcher(
      choices: [
        ProfileChoice(id: "mock", displayName: "Mock"),
        ProfileChoice(id: "lance-dev", displayName: "Lance dev"),
      ],
      build: { id in
        id == "lance-dev"
          ? (.lanceDev(entra: .init(tenantID: "t", clientID: "c", scope: "s")), next) : nil
      },
      remember: { remembered.value = $0 })
    let store = IanStore(
      service: first, profile: .mock, appVersion: SemanticVersion("0.1.0")!, clock: ManualClock(),
      jitter: { 1 }, now: { epoch }, profileSwitcher: switcher)
    store.start()
    _ = await eventually("live") { await MainActor.run { store.connection == .live } }
    return (store, first)
  }

  @MainActor
  final class Remembered {
    var value: String?
  }

  @Test("asks before it switches profile, and does nothing for the current one")
  func asksBeforeSwitching() async {
    let remembered = Remembered()
    let (store, first) = await switchingStore(next: ScriptedService(), remembered: remembered)
    defer { store.stop() }
    let model = model()

    model.requestProfile("mock", in: store)
    #expect(model.pendingProfile == nil)

    model.requestProfile("lance-dev", in: store)
    #expect(model.pendingProfile?.displayName == "Lance dev")
    #expect(first.signOuts == 0)

    model.cancelProfile()
    await model.confirmProfile(in: store)
    #expect(first.signOuts == 0)
    #expect(store.profileID == "mock")
  }

  @Test("signs out, clears the store and restarts sync once the switch is confirmed")
  func confirmedSwitch() async {
    let remembered = Remembered()
    let next = ScriptedService(
      snapshots: [
        .success(Fixtures.snapshot(cursor: "50", items: [Fixtures.itemJSON(id: "task_9")]))
      ])
    let (store, first) = await switchingStore(next: next, remembered: remembered)
    defer { store.stop() }
    let model = model()
    model.requestProfile("lance-dev", in: store)

    await model.confirmProfile(in: store)

    #expect(first.signOuts == 1)
    #expect(remembered.value == "lance-dev")
    #expect(store.profileID == "lance-dev")
    #expect(
      await eventually("the new profile syncs") {
        await MainActor.run { store.state.items["task_9"] != nil }
      })
    #expect(store.state.items["task_1"] == nil)
    #expect(model.pendingProfile == nil)
  }

  @Test("copies the diagnostics report through the injected pasteboard")
  func copiesTheReport() async {
    let (store, _, _) = await liveStore()
    defer { store.stop() }
    var copied: [String] = []
    let model = model { copied.append($0) }
    #expect(!model.didCopyReport)

    model.copyReport(from: store, now: epoch)

    #expect(copied.count == 1)
    #expect(copied[0].contains("App version: 0.1.0"))
    #expect(copied[0].contains("Contract version: 1.0.0"))
    #expect(model.didCopyReport)
  }

  @Test("reports the last snapshot time and the event lag in the diagnostics")
  func reportsTimings() async {
    let (store, _, _) = await liveStore()
    defer { store.stop() }

    let text = DiagnosticsReport.text(for: store, generatedAt: epoch)

    #expect(text.contains("Event lag: no heartbeat yet"))
    #expect(text.contains("Last snapshot: 2026-10-16T08:00:00.000Z"))
    #expect(text.contains("Environment: mock"))
  }
}
