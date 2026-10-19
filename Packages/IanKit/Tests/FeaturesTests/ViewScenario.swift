import Contract
import Foundation
import Store
import TestSupport

/// A mock scenario as `scripts/export-scenario-fixtures.sh` exported it: the `views`, the `items`
/// they name and the principal, taken at a fixed mock time.
struct ViewScenario: Decodable {
  let today: Components.Schemas.Today
  let views: Components.Schemas.Views
  let items: [Components.Schemas.Item]
  let me: Components.Schemas.Me

  static let names = ScenarioFixtures.names

  static func load(_ name: String) -> ViewScenario {
    Fixtures.decode(ScenarioFixtures.json(name))
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
