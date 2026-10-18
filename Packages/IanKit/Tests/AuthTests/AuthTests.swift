import Foundation
import TestSupport
import Testing

@testable import Auth

private let configuration = EntraConfiguration(
  tenantID: "tenant-1", clientID: "client-1", scope: "api://lance/Desktop.Access")

private actor OpenedURL {
  private(set) var url: URL?
  func set(_ url: URL) { self.url = url }
}

/// Stands in for the browser and the loopback listener: reads the authorisation URL the provider
/// opened and answers with a redirect built by `respond`.
private struct FakeReceiver: RedirectReceiver {
  let opened: OpenedURL
  let respond: @Sendable (URL) -> URL

  func receive(whenListening: @Sendable (URL) async -> Void) async throws -> RedirectResult {
    let redirectURI = URL(string: "http://localhost:49152")!
    await whenListening(redirectURI)
    let authorisation = try #require(await opened.url)
    return RedirectResult(redirectURI: redirectURI, callback: respond(authorisation))
  }
}

private func query(_ url: URL, _ name: String) -> String? {
  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
    .first { $0.name == name }?.value
}

private func callback(code: String? = nil, error: String? = nil, state: String?) -> URL {
  var items = [URLQueryItem]()
  if let code { items.append(URLQueryItem(name: "code", value: code)) }
  if let error { items.append(URLQueryItem(name: "error", value: error)) }
  if let state { items.append(URLQueryItem(name: "state", value: state)) }
  var components = URLComponents(string: "http://localhost:49152/")!
  components.queryItems = items
  return components.url!
}

private struct Harness {
  let provider: EntraTokenProvider
  let store: InMemoryTokenStore
  let opened: OpenedURL
}

private enum Redirect {
  case valid
  case forgedState
  case noState
  case error(String)

  func url(answering authorisation: URL) -> URL {
    switch self {
    case .valid: callback(code: "code-1", state: query(authorisation, "state"))
    case .forgedState: callback(code: "code-1", state: "forged")
    case .noState: callback(code: "code-1", state: nil)
    case .error(let code): callback(error: code, state: query(authorisation, "state"))
    }
  }
}

private func harness(
  store: InMemoryTokenStore = InMemoryTokenStore(),
  configuration: EntraConfiguration = configuration,
  at time: Date = Date(),
  redirect: Redirect = .valid,
  tokenEndpoint: @escaping StubURLProtocol.Handler
) -> Harness {
  let opened = OpenedURL()
  let stub = StubURLProtocol.session(handler: tokenEndpoint)
  let provider = EntraTokenProvider(
    configuration: configuration, store: store, session: stub.session,
    receiver: FakeReceiver(opened: opened, respond: { redirect.url(answering: $0) }),
    openURL: { await opened.set($0) }, now: { time })
  return Harness(provider: provider, store: store, opened: opened)
}

private let grant = """
  {"access_token":"access-1","refresh_token":"refresh-1","expires_in":3600,"token_type":"Bearer"}
  """

@Test("matches the RFC 7636 example for the S256 challenge")
private func pkceMatchesRFCExample() {
  let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

  #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test("generates a different 43 character base64url verifier each time")
private func pkceGeneratesFreshVerifiers() {
  let first = PKCE.generate()
  let second = PKCE.generate()

  #expect(first.verifier.count == 43)
  #expect(first.verifier != second.verifier)
  #expect(first.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
}

@Test("builds an authorisation URL for the tenant with PKCE, state and the offline scope")
private func buildsAuthorisationURL() throws {
  let pkce = PKCE(verifier: "verifier")
  let url = configuration.authorisationURL(
    redirectURI: URL(string: "http://localhost:5000")!, state: "state-1", pkce: pkce)

  #expect(url.host == "login.microsoftonline.com")
  #expect(url.path == "/tenant-1/oauth2/v2.0/authorize")
  #expect(query(url, "client_id") == "client-1")
  #expect(query(url, "response_type") == "code")
  #expect(query(url, "redirect_uri") == "http://localhost:5000")
  #expect(query(url, "scope") == "api://lance/Desktop.Access offline_access")
  #expect(query(url, "state") == "state-1")
  #expect(query(url, "code_challenge") == pkce.challenge)
  #expect(query(url, "code_challenge_method") == "S256")
}

@Test("sends the dev-local bearer for the mock")
private func devProviderSendsDevLocal() async throws {
  #expect(try await DevTokenProvider().token() == "dev-local")
}

@Test("names the empty scope and Lance DL1 when the scope is not configured")
private func namesMissingScope() {
  let unconfigured = EntraConfiguration(tenantID: "tenant-1", clientID: "", scope: "")

  let error = #expect(throws: AuthError.self) { try unconfigured.validate() }

  #expect(error == .notConfigured(missing: [.clientID, .scope]))
  let message = error?.errorDescription ?? ""
  #expect(message.contains("IAN_LANCE_SCOPE"))
  #expect(message.contains("IAN_LANCE_CLIENT_ID"))
  #expect(message.contains("DL1"))
}

@Test("fails before opening the browser when the scope is not configured")
private func doesNotOpenBrowserWithoutScope() async {
  let unconfigured = EntraConfiguration(tenantID: "tenant-1", clientID: "client-1", scope: "")
  let harness = harness(configuration: unconfigured) { _ in StubResponse(status: 500) }

  await #expect(throws: AuthError.notConfigured(missing: [.scope])) {
    try await harness.provider.signIn()
  }
  #expect(await harness.opened.url == nil)
}

@Test("stores the tokens after the code is exchanged with the verifier and redirect URI")
private func signInStoresTokens() async throws {
  let requests = RequestLog()
  let harness = harness(at: Date(timeIntervalSince1970: 1_000)) { request in
    requests.append(bodyText(of: request))
    return .json(grant)
  }

  try await harness.provider.signIn()

  let stored = try #require(try harness.store.load())
  #expect(stored.accessToken == "access-1")
  #expect(stored.refreshToken == "refresh-1")
  #expect(stored.expiresAt == Date(timeIntervalSince1970: 4_600))
  let body = try #require(requests.all.first)
  let authorisation = try #require(await harness.opened.url)
  #expect(body.contains("grant_type=authorization_code"))
  #expect(body.contains("code=code-1"))
  #expect(body.contains("redirect_uri=http%3A%2F%2Flocalhost%3A49152"))
  let verifier = try #require(
    body.split(separator: "&").first { $0.hasPrefix("code_verifier=") }
      .map { String($0.dropFirst("code_verifier=".count)) })
  #expect(PKCE.challenge(for: verifier) == query(authorisation, "code_challenge"))
}

@Test("rejects a redirect whose state is not the one sent and stores nothing")
private func rejectsStateMismatch() async throws {
  let harness = harness(redirect: .forgedState) { _ in
    .json(grant)
  }

  await #expect(throws: AuthError.stateMismatch) { try await harness.provider.signIn() }
  #expect(try harness.store.load() == nil)
}

@Test("rejects a redirect that carries no state")
private func rejectsMissingState() async throws {
  let harness = harness(redirect: .noState) { _ in
    .json(grant)
  }

  await #expect(throws: AuthError.stateMismatch) { try await harness.provider.signIn() }
}

@Test("reports the rejected scope when Entra refuses it on the redirect")
private func reportsScopeRejectedOnRedirect() async {
  let harness = harness(redirect: .error("invalid_scope")) { _ in .json(grant) }

  await #expect(throws: AuthError.scopeRejected(scope: "api://lance/Desktop.Access")) {
    try await harness.provider.signIn()
  }
}

@Test("reports the rejected scope when the token endpoint answers invalid_scope")
private func reportsScopeRejectedOnExchange() async throws {
  let harness = harness { _ in
    .json(
      #"{"error":"invalid_scope","error_description":"AADSTS70011: no such scope"}"#, status: 400)
  }

  let error = await #expect(throws: AuthError.self) { try await harness.provider.signIn() }

  #expect(error == .scopeRejected(scope: "api://lance/Desktop.Access"))
  let message = error?.errorDescription ?? ""
  #expect(message.contains("api://lance/Desktop.Access"))
  #expect(message.contains("DL1"))
}

@Test("keeps other Entra refusals with their code and description")
private func keepsOtherRefusals() async {
  let harness = harness { _ in
    .json(#"{"error":"access_denied","error_description":"The principal declined"}"#, status: 400)
  }

  await #expect(throws: AuthError.refused(code: "access_denied", detail: "The principal declined"))
  {
    try await harness.provider.signIn()
  }
}

@Test("asks for sign-in when no token is stored")
private func asksForSignInWithoutToken() async {
  let harness = harness { _ in StubResponse(status: 500) }

  await #expect(throws: AuthError.signInRequired) { try await harness.provider.token() }
}

@Test("returns the stored token while it is more than a minute from expiry")
private func returnsFreshToken() async throws {
  let store = InMemoryTokenStore(
    tokens: StoredTokens(
      accessToken: "access-1", refreshToken: "refresh-1",
      expiresAt: Date(timeIntervalSince1970: 1_000 + 120)))
  let harness = harness(store: store, at: Date(timeIntervalSince1970: 1_000)) { _ in
    StubResponse(status: 500)
  }

  #expect(try await harness.provider.token() == "access-1")
}

@Test("refreshes a token close to expiry and keeps the refresh token Entra does not rotate")
private func refreshesExpiringToken() async throws {
  let store = InMemoryTokenStore(
    tokens: StoredTokens(
      accessToken: "old", refreshToken: "refresh-1",
      expiresAt: Date(timeIntervalSince1970: 1_030)))
  let requests = RequestLog()
  let harness = harness(store: store, at: Date(timeIntervalSince1970: 1_000)) { request in
    requests.append(bodyText(of: request))
    return .json(#"{"access_token":"new","expires_in":3600}"#)
  }

  let token = try await harness.provider.token()

  #expect(token == "new")
  #expect(requests.all.first?.contains("grant_type=refresh_token") == true)
  #expect(requests.all.first?.contains("refresh_token=refresh-1") == true)
  #expect(try store.load()?.refreshToken == "refresh-1")
  #expect(try store.load()?.accessToken == "new")
}

@Test("clears the tokens and asks for sign-in when the refresh token is refused")
private func clearsTokensWhenRefreshRefused() async throws {
  let store = InMemoryTokenStore(
    tokens: StoredTokens(
      accessToken: "old", refreshToken: "refresh-1", expiresAt: Date(timeIntervalSince1970: 0)))
  let harness = harness(store: store, at: Date(timeIntervalSince1970: 1_000)) { _ in
    .json(#"{"error":"invalid_grant"}"#, status: 400)
  }

  await #expect(throws: AuthError.signInRequired) { try await harness.provider.token() }
  #expect(try store.load() == nil)
}

@Test("keeps the tokens when a refresh fails because the network is down")
private func keepsTokensWhenOffline() async throws {
  let store = InMemoryTokenStore(
    tokens: StoredTokens(
      accessToken: "old", refreshToken: "refresh-1", expiresAt: Date(timeIntervalSince1970: 0)))
  let harness = harness(store: store, at: Date(timeIntervalSince1970: 1_000)) { _ in
    StubResponse(failure: URLError(.notConnectedToInternet))
  }

  await #expect(throws: URLError.self) { try await harness.provider.token() }
  #expect(try store.load()?.refreshToken == "refresh-1")
}

@Test("clears the stored tokens on sign-out")
private func signOutClearsTokens() async throws {
  let store = InMemoryTokenStore(
    tokens: StoredTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture))
  let harness = harness(store: store) { _ in StubResponse(status: 500) }

  await harness.provider.signOut()

  #expect(try store.load() == nil)
  await #expect(throws: AuthError.signInRequired) { try await harness.provider.token() }
}

@Test("delivers the redirect from the browser through the loopback listener")
private func loopbackReceivesRedirect() async throws {
  let receiver = LoopbackRedirectReceiver(timeout: .seconds(20))
  let session = URLSession(configuration: .ephemeral)

  let result = try await receiver.receive { redirectURI in
    Task {
      var components = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)!
      components.path = "/"
      components.queryItems = [
        URLQueryItem(name: "code", value: "abc"), URLQueryItem(name: "state", value: "xyz"),
      ]
      _ = try? await session.data(from: components.url!)
    }
  }

  #expect(query(result.callback, "code") == "abc")
  #expect(query(result.callback, "state") == "xyz")
  #expect(result.redirectURI.host == "localhost")
}

@Test("reads the target from a request line and ignores other methods")
private func parsesRequestTarget() {
  #expect(
    LoopbackRedirectReceiver.requestTarget("GET /?code=a&state=b HTTP/1.1\r\nHost: x\r\n\r\n")
      == "/?code=a&state=b")
  #expect(LoopbackRedirectReceiver.requestTarget("POST / HTTP/1.1\r\n\r\n") == nil)
}

private final class RequestLog: @unchecked Sendable {
  // `items` is read and written only while holding `lock`.
  private let lock = NSLock()
  private var items: [String] = []
  func append(_ item: String) { lock.withLock { items.append(item) } }
  var all: [String] { lock.withLock { items } }
}
