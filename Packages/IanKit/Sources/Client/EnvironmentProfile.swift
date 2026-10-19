import Auth
import Foundation

/// An environment the app can talk to (spec section 8, ADR 0003). Version 0 has two, and no
/// production profile exists.
public struct EnvironmentProfile: Equatable, Sendable {
  public enum Name: String, CaseIterable, Sendable {
    case mock
    case lanceDev = "lance-dev"

    /// What the header and the Settings picker call the profile.
    public var displayName: String {
      switch self {
      case .mock: "Mock"
      case .lanceDev: "Lance dev"
      }
    }
  }

  public enum SignIn: Equatable, Sendable {
    /// The mock accepts `Bearer dev-local`.
    case devToken
    /// Entra authorisation code with PKCE.
    case entra(EntraConfiguration)
  }

  public let name: Name
  /// What the header shows when the profile is not `mock` (spec 6.2).
  public let displayName: String
  public let baseURL: URL
  public let signIn: SignIn

  public var isMock: Bool { name == .mock }

  public static let mock = EnvironmentProfile(
    name: .mock, displayName: Name.mock.displayName,
    baseURL: URL(string: "http://localhost:4317/desktop/v1")!, signIn: .devToken)

  /// The dev api host is erratum E3. The Entra settings come from build settings.
  public static func lanceDev(entra: EntraConfiguration) -> EnvironmentProfile {
    EnvironmentProfile(
      name: .lanceDev, displayName: Name.lanceDev.displayName,
      baseURL: URL(
        string:
          "https://ca-lance-api-dev.graygrass-c682ce2c.uksouth.azurecontainerapps.io/desktop/v1")!,
      signIn: .entra(entra))
  }

  /// The service name for this profile's Keychain item, one per profile.
  public func keychainService(bundleIdentifier: String) -> String {
    "\(bundleIdentifier).\(name.rawValue)"
  }

  /// A token provider for the profile. `openURL` opens the sign-in page in the system browser;
  /// AppKit is the app's to import.
  public func makeTokenProvider(
    bundleIdentifier: String,
    openURL: @escaping @Sendable (URL) async -> Void
  ) -> any TokenProvider {
    switch signIn {
    case .devToken:
      return DevTokenProvider()
    case .entra(let configuration):
      return EntraTokenProvider(
        configuration: configuration,
        store: KeychainTokenStore(service: keychainService(bundleIdentifier: bundleIdentifier)),
        openURL: openURL)
    }
  }
}

extension EnvironmentProfile {
  /// The `UserDefaults` key for the environment profile. The launch argument
  /// `-IanEnvironment <name>` lands in the argument domain under the same key, which `UserDefaults`
  /// reads before the saved setting, so one lookup gives the argument, else the saved setting.
  public static let defaultsKey = "IanEnvironment"

  public enum ResolutionError: Error, Equatable, LocalizedError {
    case unknownProfile(String)

    public var errorDescription: String? {
      switch self {
      case .unknownProfile(let name):
        let known = Name.allCases.map(\.rawValue).joined(separator: ", ")
        return "There is no environment profile named \"\(name)\". Use one of: \(known)."
      }
    }
  }

  /// Chooses the profile: the launch argument, else the saved setting, else `mock`.
  /// - Parameter info: The app's Info.plist, which carries the `lance-dev` sign-in settings.
  public static func resolve(
    defaults: UserDefaults = .standard,
    info: [String: Any] = Bundle.main.infoDictionary ?? [:]
  ) throws -> EnvironmentProfile {
    try resolve(requested: defaults.string(forKey: defaultsKey), info: info)
  }

  /// - Parameter requested: The profile name, or nil or empty for `mock`.
  public static func resolve(
    requested: String?, info: [String: Any]
  ) throws -> EnvironmentProfile {
    guard let requested, !requested.isEmpty else { return .mock }
    guard let name = Name(rawValue: requested) else {
      throw ResolutionError.unknownProfile(requested)
    }
    switch name {
    case .mock:
      return .mock
    case .lanceDev:
      return .lanceDev(entra: entraConfiguration(from: info))
    }
  }

  static func entraConfiguration(from info: [String: Any]) -> EntraConfiguration {
    func value(_ key: String) -> String {
      (info[key] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
    return EntraConfiguration(
      tenantID: value("IanLanceTenantID"), clientID: value("IanLanceClientID"),
      scope: value("IanLanceScope"))
  }
}
