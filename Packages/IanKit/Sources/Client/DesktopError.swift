import Contract
import Foundation

/// A failed call, in the terms spec section 6.7 handles. Messages say what to do next.
public enum DesktopError: Error, Equatable, Sendable {
  /// `401`, or no usable token. The principal signs in again.
  case unauthorised
  /// `426`. The client is below the minimum version.
  case upgradeRequired(minClientVersion: String?)
  /// `409`. The item changed; `item` is its current state.
  case conflict(item: Components.Schemas.Item)
  /// `410` on the stream. The replay window no longer holds the client's cursor.
  case gone
  /// The server could not be reached.
  case offline
  /// The server refused the request, such as `400`, `403`, `404` or `422`.
  case rejected(status: Int, detail: String?)
  /// A status the contract does not describe.
  case unexpectedStatus(Int)
  /// A response the contract types could not read.
  case unreadableResponse
  /// Any other failure, with its own explanation, such as a Keychain refusal.
  case failed(String)
}

extension DesktopError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unauthorised:
      return "Your sign-in is no longer accepted. Sign in again from the Ian menu."
    case .upgradeRequired(let minimum):
      return "This version of Ian is too old for Lance"
        + (minimum.map { " (version \($0) or later is needed)" } ?? "")
        + ". Update Ian to continue."
    case .conflict:
      return "This item changed before your action reached Lance. Review it and try again."
    case .gone:
      return "Ian missed too many updates and is reloading."
    case .offline:
      return "Ian cannot reach Lance. Actions work again when the connection returns."
    case .rejected(let status, let detail):
      return detail ?? "Lance refused the request (status \(status))."
    case .unexpectedStatus(let status):
      return "Lance answered with an unexpected status (\(status)). Check that Ian and Lance "
        + "run the same contract version."
    case .failed(let reason):
      return reason
    case .unreadableResponse:
      return "Lance answered with something Ian could not read. Check that Ian and Lance "
        + "run the same contract version."
    }
  }
}
