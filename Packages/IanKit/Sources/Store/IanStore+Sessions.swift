import Client
import Contract
import Foundation
import os

extension IanStore {
  private static let sessionLog = Logger(
    subsystem: "ai.valliance.ian.desktop", category: "sessions")

  /// Identifies the signed-in, syncing session a heartbeat belongs to, or nil while heartbeats
  /// must not be sent: not running, no snapshot yet, or offline. A sign-out or a profile switch
  /// changes it, so a reporter knows to start again.
  public var heartbeatSession: Int? {
    guard phase == .running, connection == .live, lastSnapshotAt != nil else { return nil }
    return generation
  }

  /// Reports this session to Lance once and says whether Lance recorded it. Nothing is queued:
  /// while `heartbeatSession` is nil the call does nothing and answers false, and a failed send
  /// is the caller's to repeat.
  ///
  /// A `401` and a `426` take the store's usual sign-in and upgrade paths. A result that arrives
  /// after a sign-out or a profile switch is dropped and counts as not delivered.
  @discardableResult
  public func sendHeartbeat(
    deviceID: UUID, active: Bool, suppressed: Bool, idleSeconds: Int
  ) async -> Bool {
    guard let session = heartbeatSession else { return false }
    let heartbeat = Components.Schemas.SessionHeartbeat(
      deviceId: deviceID.uuidString.lowercased(), clientVersion: appVersion.description,
      active: active, suppressed: suppressed, idleSeconds: max(0, idleSeconds))
    do {
      try await service.recordSession(heartbeat)
      return generation == session
    } catch {
      guard generation == session else { return false }
      handleHeartbeatFailure(error)
      return false
    }
  }

  private func handleHeartbeatFailure(_ error: any Error) {
    guard let failure = error as? DesktopError else {
      Self.sessionLog.error("heartbeat failed: other")
      return
    }
    switch failure {
    case .unauthorised, .upgradeRequired: handle(failure)
    default: Self.sessionLog.error("heartbeat failed: \(failure.kind, privacy: .public)")
    }
  }
}
