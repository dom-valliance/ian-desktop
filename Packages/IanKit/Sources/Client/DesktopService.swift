import Contract
import Foundation

/// One message from the event stream, after decoding.
public enum StreamMessage: Sendable, Equatable {
  /// A known event. `id` is nil for `heartbeat`, which the server never stores.
  case event(id: String?, Components.Schemas.StreamEvent)
  /// An event of a type this client does not know. It counts as activity and nothing else.
  case ignored
  /// A known type whose data did not decode. The store may have missed a change, so the client
  /// refetches the snapshot.
  case undecodable
}

/// What the store and the sync loop need from Lance, behind one seam so tests can script it.
public protocol DesktopService: Sendable {
  func me() async throws -> Components.Schemas.Me
  func snapshot() async throws -> Components.Schemas.Snapshot

  /// Runs one of an item's actions and returns the correlation id its events carry.
  func runAction(
    itemID: String, actionID: String, version: Int, until: Date?, note: String?
  ) async throws -> String

  /// Opens the event stream, resuming after `lastEventID` when it is given.
  func stream(lastEventID: String?) async throws -> AsyncThrowingStream<StreamMessage, any Error>

  func signIn() async throws
  func signOut() async
}
