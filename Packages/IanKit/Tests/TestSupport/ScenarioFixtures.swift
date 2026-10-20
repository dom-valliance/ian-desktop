import Foundation

/// The mock's scenarios as `scripts/export-scenario-fixtures.sh` exported them: one JSON file per
/// scenario holding `today`, `views`, `items` and `me`, taken at a fixed mock time. Each test
/// target decodes the parts it needs.
public enum ScenarioFixtures {
  public static let names = ["quiet", "normal", "overloaded", "incident"]

  public static func json(_ name: String) -> String {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      let json = try? String(contentsOf: url, encoding: .utf8)
    else {
      preconditionFailure(
        "The fixture \(name).json is missing. Run scripts/export-scenario-fixtures.sh.")
    }
    return json
  }
}
