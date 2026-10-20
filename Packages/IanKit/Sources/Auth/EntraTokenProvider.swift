import Foundation

/// Entra authorisation code with PKCE for the `lance-dev` profile (spec section 8). The system
/// browser shows the sign-in page, a loopback listener receives the code, and the tokens are kept
/// in the `TokenStore`.
public actor EntraTokenProvider: TokenProvider {
  /// A token this close to expiry is refreshed before use.
  private static let refreshMargin: TimeInterval = 60

  private let configuration: EntraConfiguration
  private let store: any TokenStore
  private let session: URLSession
  private let receiver: any RedirectReceiver
  private let openURL: @Sendable (URL) async -> Void
  private let now: @Sendable () -> Date
  private var refreshing: Task<String, any Error>?
  /// Raised by `signOut`, so a refresh or a sign-in already in flight does not save tokens after it.
  private var epoch = 0

  /// - Parameters:
  ///   - session: Must come from `URLSessionConfiguration.ephemeral` (AGENTS.md non-negotiable 5).
  ///   - openURL: Opens the authorisation URL in the system browser. AppKit lives in the app.
  public init(
    configuration: EntraConfiguration,
    store: any TokenStore,
    session: URLSession = URLSession(configuration: .ephemeral),
    receiver: any RedirectReceiver = LoopbackRedirectReceiver(),
    openURL: @escaping @Sendable (URL) async -> Void,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.configuration = configuration
    self.store = store
    self.session = session
    self.receiver = receiver
    self.openURL = openURL
    self.now = now
  }

  public func token() async throws -> String {
    guard let tokens = try store.load() else { throw AuthError.signInRequired }
    if tokens.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
      return tokens.accessToken
    }
    if let refreshing { return try await refreshing.value }
    let task = Task { try await refresh(tokens) }
    refreshing = task
    defer { if refreshing == task { refreshing = nil } }
    return try await task.value
  }

  public func signIn() async throws {
    try configuration.validate()
    let startedIn = epoch
    let pkce = PKCE.generate()
    let state = randomToken(byteCount: 16)
    let configuration = configuration
    let openURL = openURL

    let result = try await receiver.receive { redirectURI in
      await openURL(
        configuration.authorisationURL(redirectURI: redirectURI, state: state, pkce: pkce))
    }
    let code = try Self.authorisationCode(
      from: result.callback, expectedState: state, scope: configuration.scope)
    let tokens = try await requestTokens([
      ("grant_type", "authorization_code"),
      ("code", code),
      ("redirect_uri", result.redirectURI.absoluteString),
      ("code_verifier", pkce.verifier),
    ])
    // A sign-out while the browser or the exchange was open means the principal moved on.
    guard startedIn == epoch else { throw AuthError.signInRequired }
    try store.save(tokens)
  }

  public func signOut() async {
    epoch += 1
    refreshing?.cancel()
    refreshing = nil
    try? store.clear()
  }

  /// Reads the code from the redirect, after checking that `state` is the one this request sent.
  static func authorisationCode(
    from callback: URL, expectedState: String, scope: String
  ) throws -> String {
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

    guard value("state") == expectedState else { throw AuthError.stateMismatch }
    if let code = value("error") {
      throw AuthError.fromEntra(code: code, detail: value("error_description"), scope: scope)
    }
    guard let code = value("code"), !code.isEmpty else { throw AuthError.stateMismatch }
    return code
  }

  private func refresh(_ tokens: StoredTokens) async throws -> String {
    guard let refreshToken = tokens.refreshToken else {
      try? store.clear()
      throw AuthError.signInRequired
    }
    let startedIn = epoch
    do {
      var refreshed = try await requestTokens([
        ("grant_type", "refresh_token"),
        ("refresh_token", refreshToken),
      ])
      refreshed.refreshToken = refreshed.refreshToken ?? refreshToken
      guard startedIn == epoch else { throw AuthError.signInRequired }
      try store.save(refreshed)
      return refreshed.accessToken
    } catch AuthError.refused(let code, _) where code == "invalid_grant" {
      try? store.clear()
      throw AuthError.signInRequired
    } catch AuthError.signInRequired {
      if startedIn == epoch { try? store.clear() }
      throw AuthError.signInRequired
    }
  }

  private func requestTokens(_ fields: [(String, String)]) async throws -> StoredTokens {
    var request = URLRequest(url: configuration.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(
      formEncoded(
        [("client_id", configuration.clientID), ("scope", configuration.requestedScope)] + fields
      ).utf8)

    let (data, response) = try await session.data(for: request)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let status = (response as? HTTPURLResponse)?.statusCode else {
      throw AuthError.unreadableTokenResponse
    }
    guard (200..<300).contains(status) else {
      let failure = try? decoder.decode(TokenFailure.self, from: data)
      throw AuthError.fromEntra(
        code: failure?.error ?? "http_\(status)", detail: failure?.errorDescription,
        scope: configuration.scope)
    }
    guard let granted = try? decoder.decode(TokenGrant.self, from: data) else {
      throw AuthError.unreadableTokenResponse
    }
    return StoredTokens(
      accessToken: granted.accessToken,
      refreshToken: granted.refreshToken,
      expiresAt: now().addingTimeInterval(TimeInterval(granted.expiresIn)))
  }
}

private struct TokenGrant: Decodable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: Int
}

private struct TokenFailure: Decodable {
  let error: String
  let errorDescription: String?
}

extension AuthError {
  /// Maps an Entra error to the message the principal needs. Entra signals a scope the api does
  /// not expose as `invalid_scope`, or as an AADSTS code in the description.
  static func fromEntra(code: String, detail: String?, scope: String) -> AuthError {
    let reauthenticate = ["interaction_required", "login_required", "consent_required"]
    if reauthenticate.contains(code) { return .signInRequired }
    let scopeCodes = ["AADSTS70011", "AADSTS500011", "AADSTS650053", "AADSTS65005"]
    if code == "invalid_scope" || code == "invalid_resource"
      || scopeCodes.contains(where: { detail?.contains($0) == true })
    {
      return .scopeRejected(scope: scope)
    }
    return .refused(code: code, detail: detail)
  }
}
