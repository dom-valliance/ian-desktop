import Foundation
import Store

/// What the header and the banner under it say about the environment and the connection
/// (spec 6.2 and 6.7). Nothing here is item text: an environment name, an age, a state and a
/// sign-in message.
struct ClientStatus: Equatable {
  enum Banner: Equatable {
    case connecting
    /// The stream is down. The data stays visible and actions are paused.
    case offline
    /// No usable token. `message` says why when sign-in has already failed.
    case signInRequired(message: String?, isSigningIn: Bool)
    case upgradeRequired(minimumVersion: String?)
  }

  /// The environment's name, when it is not `mock`.
  var environment: String?
  /// "Data from 2 minutes ago", when the connection is not live and there is data.
  var dataAge: String?
  var banner: Banner?

  /// - Parameter environmentName: The profile's display name, or nil for `mock`.
  init(
    environmentName: String?, phase: IanStore.Phase, connection: IanStore.Connection,
    lastUpdatedAt: Date?, isSigningIn: Bool, now: Date
  ) {
    environment = environmentName
    switch phase {
    case .stopped:
      banner = nil
    case .signInRequired(let message):
      banner = .signInRequired(message: message, isSigningIn: isSigningIn)
    case .upgradeRequired(let minimum):
      banner = .upgradeRequired(minimumVersion: minimum)
    case .running:
      switch connection {
      case .connecting: banner = .connecting
      case .live: banner = nil
      case .offline: banner = .offline
      }
    }
    if connection != .live, let lastUpdatedAt {
      dataAge = Self.ageText(from: lastUpdatedAt, to: now)
    }
  }

  /// "Data from 2 minutes ago", in British English. A moment under five seconds is "a moment".
  static func ageText(from date: Date, to now: Date) -> String {
    guard now.timeIntervalSince(date) >= 5 else { return "Data from a moment ago" }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .numeric
    return "Data from \(formatter.localizedString(for: date, relativeTo: now))"
  }
}

extension ClientStatus.Banner {
  /// The sentence the banner shows.
  var message: String {
    switch self {
    case .connecting:
      "Connecting."
    case .offline:
      "Offline. Showing the last data, and actions are paused."
    case .signInRequired(let message, let isSigningIn):
      isSigningIn ? "Signing in." : (message ?? "Sign in to see your day.")
    case .upgradeRequired(let minimum):
      "Update Ian to continue."
        + (minimum.map { " The server needs version \($0) or later." } ?? "")
    }
  }
}
