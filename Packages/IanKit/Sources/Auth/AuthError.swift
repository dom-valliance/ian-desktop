import Foundation

/// A sign-in problem. Every message says what the principal or a developer does next.
public enum AuthError: Error, Equatable, Sendable {
  /// A setting the `ian-dev` sign-in needs is empty.
  case notConfigured(missing: [Setting])
  /// No usable token is stored, or the refresh token was refused.
  case signInRequired
  /// Entra does not offer the configured scope (AGENTS.md erratum E2).
  case scopeRejected(scope: String)
  /// The redirect carried a different `state` than the request, so it is not ours.
  case stateMismatch
  /// Entra refused the sign-in.
  case refused(code: String, detail: String?)
  /// The principal did not finish signing in before the browser wait ended.
  case timedOut
  /// The loopback listener for the redirect could not start.
  case listenerFailed(String)
  /// The token endpoint answered with something that is not a token.
  case unreadableTokenResponse
  /// The Keychain refused a read or write, with the `OSStatus`.
  case keychain(Int32)

  /// A build setting the `ian-dev` profile reads.
  public enum Setting: String, Equatable, Sendable {
    case tenantID = "IAN_DEV_TENANT_ID"
    case clientID = "IAN_DEV_CLIENT_ID"
    case scope = "IAN_DEV_SCOPE"
  }
}

extension AuthError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notConfigured(let missing):
      let names = missing.map(\.rawValue).joined(separator: ", ")
      let scopeNote =
        missing.contains(.scope)
        ? " The dev server's sign-in is not registered yet; server package DL1 adds the api scope "
          + "and registers the Ian Desktop (dev) client (see docs/companion)."
        : ""
      let verb = missing.count == 1 ? "is" : "are"
      return "Sign-in to Ian dev is not set up: \(names) \(verb) empty in App/project.yml."
        + scopeNote + " Use the mock profile with -IanEnvironment mock until then."
    case .signInRequired:
      return "Sign in to continue."
    case .scopeRejected(let scope):
      return "Entra does not offer the scope \"\(scope)\" for Ian Desktop (dev). "
        + "The dev server's sign-in is not registered yet: server package DL1 adds the api scope "
        + "and grants it to the client, and until it lands the ian-dev profile cannot sign in. "
        + "Use the mock profile with -IanEnvironment mock."
    case .stateMismatch:
      return "The sign-in response did not match the request, so it was discarded. "
        + "Start sign-in again from the Ian menu."
    case .refused(let code, let detail):
      return "Entra refused the sign-in (\(code))" + (detail.map { ": \($0)" } ?? ".")
    case .timedOut:
      return "Sign-in was not finished in the browser. Start sign-in again from the Ian menu."
    case .listenerFailed(let reason):
      return "Ian could not listen for the sign-in redirect on localhost (\(reason)). "
        + "Check that nothing blocks local connections, then sign in again."
    case .unreadableTokenResponse:
      return "Entra answered the sign-in with something Ian could not read. Try signing in again."
    case .keychain(let status):
      return "The Keychain refused to store the sign-in (status \(status)). "
        + "Unlock the login keychain, then sign in again."
    }
  }
}
