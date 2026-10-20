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
  /// The server counts UTF-16 code units, so the client does too and never sends what it refuses.
  static let maximumReasonLength = 500

  var quietStart = "19:00"
  var quietEnd = "07:00"
  var pushBudget = 3
  var pauseReason = ""
  /// The principal asked to go live and has not yet confirmed.
  private(set) var isConfirmingLive = false

  @ObservationIgnored private let store: IanStore
  /// The settings the drafts last followed, so a change can be told field by field.
  @ObservationIgnored private var followed: Components.Schemas.Settings?

  init(store: IanStore) {
    self.store = store
    syncFromServer()
    observeServer()
  }

  /// Follows the store's settings: when `settings.updated` moves them, the drafts of the fields
  /// that changed follow, and a draft being edited for another field is kept.
  private func observeServer() {
    withObservationTracking {
      _ = store.settingsRevision
    } onChange: { [weak self] in
      // `onChange` runs before the value changes, so read it on the next turn.
      Task { @MainActor in
        self?.settingsDidChange()
        self?.observeServer()
      }
    }
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

  /// Whether each draft differs from what the server holds, which is when Apply means something.
  var quietHoursChanged: Bool {
    guard let settings else { return false }
    return quietStart != settings.quietHours.start || quietEnd != settings.quietHours.end
  }

  var pushBudgetChanged: Bool {
    guard let settings else { return false }
    return pushBudget != settings.pushBudgetPerHour
  }

  /// Puts every draft back to what the server holds.
  func syncFromServer() {
    followed = settings
    guard let settings else { return }
    quietStart = settings.quietHours.start
    quietEnd = settings.quietHours.end
    pushBudget = settings.pushBudgetPerHour
    pauseReason = settings.pausedReason ?? ""
  }

  /// Moves only the drafts whose server value changed since the last one.
  func settingsDidChange() {
    guard let settings else {
      // The settings went away with a sign-out or a profile switch; drafts must not outlive them.
      followed = nil
      return
    }
    guard let old = followed else {
      syncFromServer()
      return
    }
    if settings.quietHours.start != old.quietHours.start { quietStart = settings.quietHours.start }
    if settings.quietHours.end != old.quietHours.end { quietEnd = settings.quietHours.end }
    if settings.pushBudgetPerHour != old.pushBudgetPerHour {
      pushBudget = settings.pushBudgetPerHour
    }
    if settings.pausedReason != old.pausedReason { pauseReason = settings.pausedReason ?? "" }
    followed = settings
  }

  func applyQuietHours() async {
    guard quietHoursChanged else { return }
    await send(.init(quietHours: .init(start: quietStart, end: quietEnd)))
  }

  func applyPushBudget() async {
    guard pushBudgetChanged else { return }
    await send(.init(pushBudgetPerHour: min(50, max(0, pushBudget))))
  }

  func setOwnPause(_ paused: Bool) async {
    let reason = Self.truncated(
      pauseReason.trimmingCharacters(in: .whitespacesAndNewlines),
      utf16Limit: Self.maximumReasonLength)
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

  /// A refused or failed change leaves its controls showing a value the server did not take, so
  /// those go back to the server's. Drafts for other settings are kept.
  private func send(_ patch: Components.Schemas.SettingsPatch) async {
    await store.updateSettings(patch)
    guard store.settingsNotice != nil, let settings else { return }
    if patch.quietHours != nil {
      quietStart = settings.quietHours.start
      quietEnd = settings.quietHours.end
    }
    if patch.pushBudgetPerHour != nil { pushBudget = settings.pushBudgetPerHour }
    if patch.paused != nil || patch.pausedReason != nil {
      pauseReason = settings.pausedReason ?? ""
    }
    followed = settings
  }

  /// The longest prefix of `text` within `limit` UTF-16 code units, cut on a character boundary.
  static func truncated(_ text: String, utf16Limit limit: Int) -> String {
    var result = ""
    var count = 0
    for character in text {
      count += character.utf16.count
      if count > limit { break }
      result.append(character)
    }
    return result
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
