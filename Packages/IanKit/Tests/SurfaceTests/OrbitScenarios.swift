import Attention
import Client
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

/// Holds the store a test must stop.
@MainActor
struct IanStoreBox {
  let store: IanStore
  init(_ store: IanStore) { self.store = store }
}

/// A camera monitor the test drives. It never touches CoreMediaIO.
@MainActor
final class FakeCamera: CameraMonitoring {
  var isLive = false
  private(set) var started = false
  private(set) var stopped = false

  func start(onChange: @escaping @MainActor () -> Void) { started = true }
  func stop() { stopped = true }
}

/// A store that has loaded `scenario` through a scripted service, with the context flags
/// overridden. The caller stops it.
@MainActor
func loadedStore(
  _ scenario: OrbitScenario, externalMeeting: Bool = false, quietHours: Bool = false
) async -> IanStore {
  var snapshot = Fixtures.snapshot()
  snapshot.today = scenario.today
  snapshot.today.context.inExternalMeeting = externalMeeting
  snapshot.today.context.quietHoursActive = quietHours
  snapshot.items = scenario.items
  let store = IanStore(
    service: ScriptedService(snapshots: [.success(snapshot)]), profile: .mock,
    appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
  store.start()
  for _ in 0..<200 where store.state.today == nil {
    try? await Task.sleep(for: .milliseconds(10))
  }
  return store
}
