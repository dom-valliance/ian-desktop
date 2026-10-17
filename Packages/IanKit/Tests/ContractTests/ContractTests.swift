import Contract
import Foundation
import OpenAPIRuntime
import Testing

private typealias Schemas = Components.Schemas

private struct ItemExample: CustomTestStringConvertible {
  let name: String
  let kind: Schemas.ItemKind
  let severity: Schemas.Severity?

  var testDescription: String { name }
}

private let itemExamples = [
  ItemExample(name: "ProposalItem", kind: .proposal, severity: nil),
  ItemExample(name: "CommitmentByItem", kind: .commitmentBy, severity: nil),
  ItemExample(name: "CommitmentToItem", kind: .commitmentTo, severity: nil),
  ItemExample(name: "TaskItem", kind: .task, severity: nil),
  ItemExample(name: "AlertItem", kind: .alert, severity: .p1),
]

extension Schemas.ItemDetail {
  fileprivate var kind: Schemas.ItemKind {
    switch self {
    case .proposal: .proposal
    case .commitmentBy: .commitmentBy
    case .commitmentTo: .commitmentTo
    case .task: .task
    case .alert: .alert
    }
  }
}

/// Decodes a fixture the way the client decodes a response: times are UTC with milliseconds.
private func decodeFixture<Value: Decodable>(_ name: String, as type: Value.Type = Value.self)
  throws -> Value
{
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
    "Fixtures/\(name).json is missing. Run scripts/generate-contract.sh."
  )
  let transcoder = ISO8601DateTranscoder.iso8601WithFractionalSeconds
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .custom { decoder in
    try transcoder.decode(try decoder.singleValueContainer().decode(String.self))
  }
  return try decoder.decode(Value.self, from: Data(contentsOf: url))
}

@Test("decodes each item example with the kind and detail of its kind", arguments: itemExamples)
private func decodesItemExample(_ example: ItemExample) throws {
  let item: Schemas.Item = try decodeFixture(example.name)

  #expect(item.kind == example.kind)
  #expect(item.detail.kind == example.kind)
}

@Test("carries a severity on the alert example only", arguments: itemExamples)
private func carriesSeverityOnAlertsOnly(_ example: ItemExample) throws {
  let item: Schemas.Item = try decodeFixture(example.name)

  #expect(item.severity == example.severity)
}

@Test("decodes the Me example, keeping versions as text and times in UTC")
private func decodesMeExample() throws {
  let me: Schemas.Me = try decodeFixture("Me")

  #expect(me.minClientVersion == "0.1.0")
  #expect(me.contractVersion == "1.0.0")
  #expect(me.serverTime == Date(timeIntervalSince1970: 1_792_137_600))
}

@Test("decodes the Settings example, keeping quiet hours as text and null as nil")
private func decodesSettingsExample() throws {
  let settings: Schemas.Settings = try decodeFixture("Settings")

  #expect(settings.quietHours.start == "19:00")
  #expect(settings.pushBudgetPerHour == 3)
  #expect(settings.pausedReason == nil)
}

@Test("decodes the Today example with its field cells")
private func decodesTodayExample() throws {
  let today: Schemas.Today = try decodeFixture("Today")

  #expect(today.field.cells.map(\.pressure) == [0.72, 0.1])
  #expect(today.orbit.median == 12)
}
