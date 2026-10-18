import Foundation
import Store
import SwiftUI

/// A temporary readout in the menu bar extra (D3): the environment, the open count, the data's
/// age and the connection state. D5 removes it when the expanded client shows these.
struct DebugStatus: View {
  let store: IanStore

  var body: some View {
    if !store.profile.isMock {
      Text(store.profile.displayName)
    }
    Text(openItemsLine)
    if let line = ageLine {
      Text(line)
    }
    Text(stateLine)
    if case .signInRequired(let message) = store.phase {
      if let message {
        Text(message)
      }
      if store.isSigningIn {
        Text("Signing in")
      } else {
        Button("Sign in") {
          Task { await store.signIn() }
        }
      }
    }
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
