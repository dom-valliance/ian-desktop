import Contract
import Foundation
import Observation
import Store

/// The principal's settings that go through `PATCH /settings`: quiet hours, push budget, own
/// pause and mode (spec 6.4). The drafts are what the controls edit. A change is sent when the
/// principal applies it, and the values shown as the server's move only on `settings.updated`.
@MainActor
@Observable
final class PrincipalSettingsModel {
  static let maximumReasonLength = 500

  var quietStart = "19:00"
  var quietEnd = "07:00"
  var pushBudget = 3
  var pauseReason = ""
  /// The principal asked to go live and has not yet confirmed.
  private(set) var isConfirmingLive = false

  @ObservationIgnored private let store: IanStore

  init(store: IanStore) {
    self.store = store
    syncFromServer()
  }

  var settings: Components.Schemas.Settings? { store.state.settings }

  /// Whether a change is waiting on the server's event.
  var isPending: Bool { store.settingsPending }
  var notice: String? { store.settingsNotice }

  /// Whether a change can be sent now: the data is live and no earlier change is waiting.
  var canSend: Bool { store.actionsEnabled && !store.settingsPending }

  /// The switch to live is offered only when the server says it is allowed now.
  var canGoLive: Bool {
    guard let settings else { return false }
    return canSend && settings.mode == .dryRun && settings.liveEligible
  }

  /// Why the switch is off, with the time the server gave when it knows one.
  var liveUnavailableReason: String? {
    guard let settings, settings.mode == .dryRun, !settings.liveEligible else { return nil }
    guard let opens = settings.liveOpensAt else {
      return "Going live is not allowed yet."
    }
    let text = opens.formatted(
      Date.FormatStyle(
        date: .long, time: .shortened, locale: Locale(identifier: "en_GB"),
        timeZone: TimeZone(identifier: settings.timeZone) ?? .current))
    return "Going live opens on \(text)."
  }

  /// Puts the drafts back to what the server holds. The view calls it when `settings` changes.
  func syncFromServer() {
    guard let settings else { return }
    quietStart = settings.quietHours.start
    quietEnd = settings.quietHours.end
    pushBudget = settings.pushBudgetPerHour
    pauseReason = settings.pausedReason ?? ""
  }

  func applyQuietHours() async {
    await send(.init(quietHours: .init(start: quietStart, end: quietEnd)))
  }

  func applyPushBudget() async {
    await send(.init(pushBudgetPerHour: min(50, max(0, pushBudget))))
  }

  func setOwnPause(_ paused: Bool) async {
    let reason = String(
      pauseReason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumReasonLength))
    await send(
      .init(paused: paused, pausedReason: paused && !reason.isEmpty ? reason : nil))
  }

  func requestLive() {
    guard canGoLive else { return }
    isConfirmingLive = true
  }

  func cancelLive() {
    isConfirmingLive = false
  }

  func confirmLive() async {
    guard isConfirmingLive else { return }
    isConfirmingLive = false
    guard canGoLive else { return }
    await send(.init(mode: .live))
  }

  func returnToDryRun() async {
    await send(.init(mode: .dryRun))
  }

  private func send(_ patch: Components.Schemas.SettingsPatch) async {
    await store.updateSettings(patch)
  }
}

extension PrincipalSettingsModel {
  /// A `HH:mm` time as today's date at that time, for a time picker. Only the hour and minute
  /// matter: the server reads them in the principal's time zone.
  static func date(fromTime text: String, calendar: Calendar = .current) -> Date {
    let parts = text.split(separator: ":").compactMap { Int($0) }
    let hour = parts.first ?? 0
    let minute = parts.count > 1 ? parts[1] : 0
    return calendar.date(
      bySettingHour: hour, minute: minute, second: 0, of: Date(timeIntervalSince1970: 0))
      ?? Date(timeIntervalSince1970: 0)
  }

  static func time(from date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }
}
