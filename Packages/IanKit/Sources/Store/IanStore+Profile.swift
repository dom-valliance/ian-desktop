import Client
import Foundation

/// An environment the principal can switch to in Settings.
public struct ProfileChoice: Identifiable, Equatable, Sendable {
  public let id: String
  public let displayName: String

  public init(id: String, displayName: String) {
    self.id = id
    self.displayName = displayName
  }
}

/// What the store needs to move to another profile: the choices, how to build a profile and its
/// service from a choice's id, and how to remember the choice.
public struct ProfileSwitcher {
  let choices: [ProfileChoice]
  let build: @MainActor (String) -> (EnvironmentProfile, any DesktopService)?
  let remember: @MainActor (String) -> Void

  public init(
    choices: [ProfileChoice],
    build: @escaping @MainActor (String) -> (EnvironmentProfile, any DesktopService)?,
    remember: @escaping @MainActor (String) -> Void
  ) {
    self.choices = choices
    self.build = build
    self.remember = remember
  }
}

extension IanStore {
  public var availableProfiles: [ProfileChoice] { profileSwitcher?.choices ?? [] }

  /// The id of the profile the store runs on.
  public var profileID: String { profile.name.rawValue }

  /// Signs out of the current profile, clears every piece of data, saves the choice and starts
  /// syncing against the new profile (spec 6.4). Returns false when `id` names no profile or is
  /// already the current one.
  @discardableResult
  public func switchProfile(to id: String) async -> Bool {
    guard let switcher = profileSwitcher, id != profileID, let next = switcher.build(id) else {
      return false
    }
    cancelSignIn()
    stop()
    await service.signOut()
    reset()
    signInAttempted = false
    profile = next.0
    service = next.1
    switcher.remember(id)
    start()
    return true
  }
}
