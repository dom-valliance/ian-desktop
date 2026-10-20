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
    let mine = generation
    let service = service
    do {
      let reply = try await service.updateSettings(patch)
      guard generation == mine else { return }
      // A change that alters nothing sends no event, so the reply that matches what is held
      // settles it. Anything else waits for `settings.updated`.
      if reply == state.settings { settingsPending = false }
    } catch {
      // A sign-out or a profile switch while the call was out has cleared this state already.
      guard generation == mine else { return }
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
