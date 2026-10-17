import Foundation
import Yams

/// A YAML value written as JSON. JSONEncoder prints the shortest form of a Double, where
/// JSONSerialization would turn 0.72 into 0.71999999999999997.
struct JSONValue: Encodable {
  let yaml: Any

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch yaml {
    case is NSNull: try container.encodeNil()
    case let value as Bool: try container.encode(value)
    case let value as Int: try container.encode(value)
    case let value as Double: try container.encode(value)
    case let value as String: try container.encode(value)
    case let value as [Any]: try container.encode(value.map(JSONValue.init))
    case let value as [String: Any]: try container.encode(value.mapValues(JSONValue.init))
    default:
      throw EncodingError.invalidValue(
        yaml,
        .init(
          codingPath: container.codingPath,
          debugDescription: "\(type(of: yaml)) is not JSON; quote any timestamp"))
    }
  }
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("extract-examples: \(message)\n".utf8))
  exit(1)
}

guard CommandLine.arguments.count == 3 else {
  fail("usage: extract-examples <contract.yaml> <output-directory>")
}
let contractPath = CommandLine.arguments[1]
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

let examples: [String: Any]
do {
  let text = try String(contentsOfFile: contractPath, encoding: .utf8)
  let document = try Yams.load(yaml: text) as? [String: Any]
  let components = document?["components"] as? [String: Any]
  guard let found = components?["examples"] as? [String: Any] else {
    fail("\(contractPath) has no components.examples mapping")
  }
  examples = found
} catch {
  fail("cannot read \(contractPath): \(error)")
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let manager = FileManager.default
do {
  try manager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
  for (name, example) in examples {
    guard let value = (example as? [String: Any])?["value"] else {
      fail("\(contractPath): components.examples.\(name) has no value key")
    }
    var data: Data
    do {
      data = try encoder.encode(JSONValue(yaml: value))
    } catch {
      fail("\(contractPath): components.examples.\(name).value: \(error)")
    }
    data.append(Data("\n".utf8))
    try data.write(to: outputDirectory.appendingPathComponent("\(name).json"))
  }
  for file in try manager.contentsOfDirectory(atPath: outputDirectory.path)
  where file.hasSuffix(".json") && examples[String(file.dropLast(".json".count))] == nil {
    try manager.removeItem(at: outputDirectory.appendingPathComponent(file))
  }
} catch {
  fail("cannot write to \(outputDirectory.path): \(error)")
}
