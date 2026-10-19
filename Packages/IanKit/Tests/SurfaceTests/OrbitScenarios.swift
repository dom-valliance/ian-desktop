import Contract
import Foundation
import Store
import TestSupport

@testable import Surface

/// The `today` and `items` of a mock scenario, exported by `scripts/export-orbit-fixtures.sh`.
struct OrbitScenario: Decodable {
  let today: Components.Schemas.Today
  let items: [Components.Schemas.Item]

  static let names = ["quiet", "normal", "overloaded", "incident"]

  static func load(_ name: String) -> OrbitScenario {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      let json = try? String(contentsOf: url, encoding: .utf8)
    else {
      preconditionFailure(
        "The fixture \(name).json is missing. Run scripts/export-orbit-fixtures.sh.")
    }
    return Fixtures.decode(json)
  }

  var state: StoreState {
    var state = StoreState()
    state.today = today
    state.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    return state
  }

  /// The title of every item, which suppression must keep off the Orbit.
  var titles: [String] { items.map(\.title) }
}

/// Runs `body` with settings held apart from the app's own, and clears them afterwards.
/// `removePersistentDomain` leaves an empty preferences file, so that is deleted too.
@MainActor
func withScratchDefaults<Result>(_ body: (UserDefaults) throws -> Result) rethrows -> Result {
  let name = "ian.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defer {
    defaults.removePersistentDomain(forName: name)
    let file = URL.libraryDirectory.appending(path: "Preferences/\(name).plist")
    try? FileManager.default.removeItem(at: file)
  }
  return try body(defaults)
}
