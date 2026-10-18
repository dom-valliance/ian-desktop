import Contract
import Foundation
import OpenAPIRuntime

/// Turns one server-sent event into a `StreamMessage`.
///
/// `asDecodedServerSentEventsWithJSONData` ends the stream on the first event it cannot decode,
/// and the generated `StreamEvent` rejects a type it does not know, so the decoding is done here
/// (AGENTS.md gotchas): an unknown `event` is skipped, and a known one that fails to decode is
/// reported so the client refetches the snapshot.
struct StreamMessageDecoder: Sendable {
  /// The `type` values of `StreamEvent` in contract v1.
  static let knownTypes: Set<String> = [
    "item.upserted", "item.removed", "today.updated", "views.updated", "alert.raised",
    "alert.cleared", "agent.updated", "settings.updated", "client.deprecated", "heartbeat",
  ]

  func message(for event: ServerSentEvent) -> StreamMessage {
    guard let type = event.event, Self.knownTypes.contains(type) else { return .ignored }
    guard let data = event.data,
      let decoded = try? Self.decoder.decode(
        Components.Schemas.StreamEvent.self, from: Data(data.utf8))
    else { return .undecodable }
    return .event(id: event.id, decoded)
  }

  /// Times are UTC with milliseconds (AGENTS.md gotchas), which the default `.iso8601` rejects.
  private static let decoder: JSONDecoder = {
    let transcoder = ISO8601DateTranscoder.iso8601WithFractionalSeconds
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      try transcoder.decode(try decoder.singleValueContainer().decode(String.self))
    }
    return decoder
  }()
}
