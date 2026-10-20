import Foundation
import Observation

/// Whether Ian opens at login, as the system reports it.
public enum LaunchAtLoginStatus: Equatable, Sendable {
  case enabled, disabled
  /// Registered, and the principal must allow it in System Settings.
  case requiresApproval
  /// The system does not know this build, as with an unsigned one.
  case unavailable
}

/// The system's login item for the app. The app implements it over `SMAppService.mainApp`, so
/// Features and the tests never touch the real login items.
@MainActor
public protocol LaunchAtLoginControlling {
  var status: LaunchAtLoginStatus { get }
  func register() throws
  func unregister() throws
}

/// Used where the app gives no login item control, such as the previews and the tests.
@MainActor
struct NoLaunchAtLogin: LaunchAtLoginControlling {
  var status: LaunchAtLoginStatus { .unavailable }
  func register() throws {}
  func unregister() throws {}
}

/// Launch at login is best effort in version 0 (spec 6.4): an unsigned build may not register,
/// so the model reports the system's status and says what to do when it fails.
@MainActor
@Observable
final class LaunchAtLoginModel {
  private(set) var status: LaunchAtLoginStatus
  private(set) var failure: String?

  @ObservationIgnored private let service: any LaunchAtLoginControlling

  init(service: any LaunchAtLoginControlling) {
    self.service = service
    status = service.status
  }

  var isOn: Bool { status == .enabled || status == .requiresApproval }

  /// What the principal should read under the toggle.
  var message: String {
    if let failure { return failure }
    switch status {
    case .enabled: return "Ian opens when you log in."
    case .disabled: return "Ian does not open when you log in."
    case .requiresApproval:
      return "Allow Ian in System Settings, General, Login Items, and it opens when you log in."
    case .unavailable:
      return "This build cannot register to open at login. An unsigned build often cannot; "
        + "run a signed build to use this."
    }
  }

  func refresh() {
    status = service.status
  }

  func set(enabled: Bool) {
    failure = nil
    do {
      if enabled { try service.register() } else { try service.unregister() }
    } catch {
      failure =
        "Ian could not change its login item: \(error.localizedDescription) "
        + "An unsigned build may not be allowed to; run a signed build."
    }
    refresh()
  }
}
