import Foundation
import Observation
import Store

/// What the client section of Settings does beyond saving a value: launch at login, the
/// environment switch that asks first, sign out and the diagnostics copy (spec 6.4).
@MainActor
@Observable
final class SettingsModel {
  let launchAtLogin: LaunchAtLoginModel
  /// The profile the principal chose and has not yet confirmed.
  private(set) var pendingProfile: ProfileChoice?
  /// True after the report was copied, until Settings is closed.
  private(set) var didCopyReport = false

  @ObservationIgnored private let copy: (String) -> Void
  /// Built once, so the settings view being rebuilt on every event does not rebuild it.
  @ObservationIgnored private var principalModel: PrincipalSettingsModel?

  init(launchAtLogin: any LaunchAtLoginControlling, copy: @escaping (String) -> Void) {
    self.launchAtLogin = LaunchAtLoginModel(service: launchAtLogin)
    self.copy = copy
  }

  func principal(for store: IanStore) -> PrincipalSettingsModel {
    if let principalModel { return principalModel }
    let model = PrincipalSettingsModel(store: store)
    principalModel = model
    return model
  }

  func requestProfile(_ id: String, in store: IanStore) {
    guard id != store.profileID else { return }
    pendingProfile = store.availableProfiles.first { $0.id == id }
  }

  func cancelProfile() {
    pendingProfile = nil
  }

  /// Signs out, clears the store and syncs against `choice`, the profile the dialog presented.
  /// Taking it as an argument matters: dismissing the dialog clears `pendingProfile` before the
  /// button's action runs.
  func confirmProfile(_ choice: ProfileChoice, in store: IanStore) async {
    pendingProfile = nil
    await store.switchProfile(to: choice.id)
  }

  func clearCopied() {
    didCopyReport = false
  }

  func copyReport(from store: IanStore, now: Date = Date()) {
    copy(DiagnosticsReport.text(for: store, generatedAt: now))
    didCopyReport = true
  }
}
