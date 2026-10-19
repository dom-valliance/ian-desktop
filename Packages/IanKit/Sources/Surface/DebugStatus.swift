import Foundation
import Store
import SwiftUI

/// A temporary readout in the menu bar extra (D3): the environment, the open count, the data's
/// age and the connection state. D5 removes it when the expanded client shows these.
struct DebugStatus: View {
  let store: IanStore

  var body: some View {
    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
      Text(line)
    }
    if case .signInRequired = store.phase, !store.isSigningIn {
      Button("Sign in") {
        Task { await store.signIn() }
      }
    }
  }

  /// Every line of text the readout shows. None of it is item text: the environment, counts, an
  /// age, a connection state and a sign-in message.
  var lines: [String] {
    var lines: [String] = []
    if !store.profile.isMock { lines.append(store.profile.displayName) }
    lines.append(openItemsLine)
    if let line = ageLine { lines.append(line) }
    lines.append(stateLine)
    if case .signInRequired(let message) = store.phase {
      if let message { lines.append(message) }
      if store.isSigningIn { lines.append("Signing in") }
    }
    return lines
  }

  /// The server's own count of open items, from the Orbit block.
  private var openItemsLine: String {
    store.state.today.map { "Open items: \($0.orbit.load)" } ?? "Open items: none loaded"
  }

  private var ageLine: String? {
    store.lastUpdatedAt.map {
      "Data from \($0.formatted(.relative(presentation: .numeric, unitsStyle: .wide)))"
    }
  }

  private var stateLine: String {
    switch store.phase {
    case .stopped:
      return "Stopped"
    case .signInRequired:
      return "Sign-in needed"
    case .upgradeRequired(let minimum):
      return "Update Ian" + (minimum.map { ": Lance needs \($0) or later" } ?? "")
    case .running:
      switch store.connection {
      case .connecting: return "Connecting"
      case .live: return "Live"
      case .offline: return "Offline, actions paused"
      }
    }
  }
}
