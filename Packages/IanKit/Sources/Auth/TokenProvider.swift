import Foundation

/// Supplies the bearer token for every request, and owns signing in and out for one profile.
public protocol TokenProvider: Sendable {
  /// The access token to send now, refreshed when it is close to expiry.
  /// - Throws: `AuthError.signInRequired` when the principal has to sign in.
  func token() async throws -> String

  /// Signs the principal in. Opens the system browser when the profile needs one.
  func signIn() async throws

  /// Clears every stored credential.
  func signOut() async
}

/// The token the mock accepts (spec section 8). There is nothing to sign in to.
public struct DevTokenProvider: TokenProvider {
  public static let bearerToken = "dev-local"

  public init() {}

  public func token() async throws -> String { Self.bearerToken }

  public func signIn() async throws {}

  public func signOut() async {}
}
