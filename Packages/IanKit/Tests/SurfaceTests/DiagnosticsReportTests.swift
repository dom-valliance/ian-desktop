import Contract
import Foundation
import Store
import Testing

@testable import Features

/// The report lives in Features, and the scenario fixtures live here with the Orbit's tests.
@Suite("Diagnostics report")
@MainActor
struct DiagnosticsReportTests {
  /// Every string an item carries, at any depth, except ones too short to be text.
  private func strings(in value: Any) -> [String] {
    switch value {
    case let text as String: text.count >= 8 ? [text] : []
    case let list as [Any]: list.flatMap(strings)
    case let map as [String: Any]: map.values.flatMap(strings)
    default: []
    }
  }

  private func itemStrings(_ item: Components.Schemas.Item) throws -> [String] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(item)
    return strings(in: try JSONSerialization.jsonObject(with: data))
  }

  @Test("holds ids, versions and timings from the normal scenario and no item text")
  func carriesNoItemText() async throws {
    let scenario = OrbitScenario.load("normal")
    let store = await loadedStore(scenario)
    defer { store.stop() }

    let report = DiagnosticsReport.text(
      for: store, generatedAt: Date(timeIntervalSince1970: 1_792_137_600))

    #expect(report.contains("App version: 0.1.0"))
    #expect(report.contains("Contract version: 1.0.0"))
    #expect(report.contains("Open items: \(scenario.items.count)"))
    #expect(!scenario.items.isEmpty)
    for item in scenario.items {
      #expect(!report.contains(item.title))
      #expect(!report.contains(item.meta))
      #expect(!report.contains(item.unit.name))
      for text in try itemStrings(item) {
        #expect(!report.contains(text), "the report repeats \(text)")
      }
    }
    #expect(!report.contains(store.state.me?.displayName ?? "[PERSON]"))
  }
}
