import Client
import Contract
import Foundation

extension IanStore {
  /// Sends a change to the principal's settings. Nothing shown changes until the server's
  /// `settings.updated` event arrives (ADR 0001); a refusal such as `422` is kept for the view.
  public func updateSettings(_ patch: Components.Schemas.SettingsPatch) async {
    guard !settingsPending else { return }
    guard actionsEnabled else {
      settingsNotice = DesktopError.offline.localizedDescription
      return
    }
    settingsNotice = nil
    settingsPending = true
    do {
      _ = try await service.updateSettings(patch)
    } catch {
      settingsPending = false
      guard let failure = error as? DesktopError else {
        settingsNotice = error.localizedDescription
        return
      }
      switch failure {
      case .unauthorised, .upgradeRequired: handle(failure)
      default: settingsNotice = failure.localizedDescription
      }
    }
  }

  public func dismissSettingsNotice() {
    settingsNotice = nil
  }
}
