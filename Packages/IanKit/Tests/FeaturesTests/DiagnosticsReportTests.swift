import Client
import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

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

  private static let labels = [
    "App version", "Contract version", "Environment", "Event lag", "Last snapshot",
    "Principal id", "State", "Connection", "Last event id", "Open items", "Agents", "Generated",
  ]

  /// A store holding the normal scenario with free text in every place the snapshot allows it.
  private func store(_ scenario: ViewScenario) async -> IanStore {
    var snapshot = Fixtures.snapshot()
    snapshot.today = scenario.today
    snapshot.views = scenario.views
    snapshot.items = scenario.items
    snapshot.settings = Fixtures.settings(
      paused: true, pausedReason: "Private pause reason text", globalPaused: true,
      globalReason: "Private kill switch reason")
    snapshot.agents = Fixtures.agentsOverview([
      Fixtures.agent(id: "agent_1", name: "Private agent name"),
      Fixtures.agent(id: "agent_2", name: "Another private agent"),
    ])
    let store = IanStore(
      service: ScriptedService(me: scenario.me, snapshots: [.success(snapshot)]), profile: .mock,
      appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    store.start()
    for _ in 0..<200 where store.state.today == nil {
      try? await Task.sleep(for: .milliseconds(10))
    }
    return store
  }

  @Test("holds ids, versions and timings from the normal scenario and no free text")
  func carriesNoItemText() async throws {
    let scenario = ViewScenario.load("normal")
    let store = await store(scenario)
    defer { store.stop() }

    let report = DiagnosticsReport.text(
      for: store, generatedAt: Date(timeIntervalSince1970: 1_792_137_600))

    #expect(report.contains("App version: 0.1.0"))
    #expect(report.contains("Contract version: \(scenario.me.contractVersion)"))
    #expect(report.contains("Open items: \(scenario.items.count)"))
    #expect(report.contains("Agents: 2"))
    #expect(!scenario.items.isEmpty)
    for item in scenario.items {
      #expect(!report.contains(item.title))
      #expect(!report.contains(item.meta))
      #expect(!report.contains(item.unit.name))
      for text in try itemStrings(item) {
        #expect(!report.contains(text), "the report repeats \(text)")
      }
    }
    for text in ["Private pause reason text", "Private kill switch reason", "Private agent name"] {
      #expect(!report.contains(text))
    }
    #expect(!report.contains("Another private agent"))
    #expect(!report.contains(store.state.me?.displayName ?? "[PERSON]"))
  }

  @Test("starts every line with a label from a fixed list")
  func linesStartWithKnownLabels() async {
    let store = await store(ViewScenario.load("normal"))
    defer { store.stop() }

    let lines = DiagnosticsReport.text(for: store, generatedAt: Date()).split(separator: "\n")

    #expect(lines.first == "Ian diagnostics")
    for line in lines.dropFirst() {
      #expect(Self.labels.contains { line.hasPrefix($0 + ": ") }, "unexpected line \(line)")
    }
  }
}
