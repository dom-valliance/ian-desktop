import Foundation

/// What the `lance-dev` sign-in needs, all read from build settings (AGENTS.md erratum E2).
public struct EntraConfiguration: Equatable, Sendable {
  public var tenantID: String
  public var clientID: String
  /// The delegated Lance api scope, which Lance package DL1 creates.
  public var scope: String

  public init(tenantID: String, clientID: String, scope: String) {
    self.tenantID = tenantID
    self.clientID = clientID
    self.scope = scope
  }

  /// - Throws: `AuthError.notConfigured` naming every empty setting.
  public func validate() throws {
    var missing: [AuthError.Setting] = []
    if tenantID.isEmpty { missing.append(.tenantID) }
    if clientID.isEmpty { missing.append(.clientID) }
    if scope.isEmpty { missing.append(.scope) }
    if !missing.isEmpty { throw AuthError.notConfigured(missing: missing) }
  }

  var authorisationEndpoint: URL { endpoint("authorize") }
  var tokenEndpoint: URL { endpoint("token") }

  /// The scopes sent to Entra. `offline_access` is what makes Entra issue a refresh token.
  var requestedScope: String { "\(scope) offline_access" }

  func authorisationURL(redirectURI: URL, state: String, pkce: PKCE) -> URL {
    let query = formEncoded([
      ("client_id", clientID),
      ("response_type", "code"),
      ("redirect_uri", redirectURI.absoluteString),
      ("response_mode", "query"),
      ("scope", requestedScope),
      ("state", state),
      ("code_challenge", pkce.challenge),
      ("code_challenge_method", "S256"),
    ])
    return URL(string: "\(authorisationEndpoint.absoluteString)?\(query)")!
  }

  private func endpoint(_ name: String) -> URL {
    // Escaped, so a malformed tenant id cannot make the URL invalid.
    let tenant = tenantID.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    return URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/\(name)")!
  }
}

private let unreserved = CharacterSet(
  charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

/// `application/x-www-form-urlencoded` with every reserved character escaped.
func formEncoded(_ pairs: [(String, String)]) -> String {
  pairs.map { name, value in
    let escaped = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    return "\(name)=\(escaped)"
  }
  .joined(separator: "&")
}
