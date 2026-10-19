import Contract
import Foundation
import Store
import TestSupport

/// A mock scenario as `scripts/export-orbit-fixtures.sh` exported it: the `views`, the `items`
/// they name and the principal, taken at a fixed mock time.
struct ViewScenario: Decodable {
  let today: Components.Schemas.Today
  let views: Components.Schemas.Views
  let items: [Components.Schemas.Item]
  let me: Components.Schemas.Me

  static let names = ["quiet", "normal", "overloaded", "incident"]

  static func load(_ name: String) -> ViewScenario {
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
    state.me = me
    state.today = today
    state.views = views
    state.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    return state
  }
}
