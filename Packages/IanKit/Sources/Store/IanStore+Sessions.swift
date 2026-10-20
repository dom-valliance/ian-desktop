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

  /// Reports this session to Lance once. Nothing is queued: while `heartbeatSession` is nil the
  /// call does nothing, and a failed send waits for the next heartbeat.
  ///
  /// A `401` and a `426` take the store's usual sign-in and upgrade paths. A result that arrives
  /// after a sign-out or a profile switch is dropped.
  public func sendHeartbeat(deviceID: UUID, active: Bool, suppressed: Bool, idleSeconds: Int) async
  {
    guard let session = heartbeatSession else { return }
    let heartbeat = Components.Schemas.SessionHeartbeat(
      deviceId: deviceID.uuidString.lowercased(), clientVersion: appVersion.description,
      active: active, suppressed: suppressed, idleSeconds: max(0, idleSeconds))
    do {
      try await service.recordSession(heartbeat)
    } catch {
      guard generation == session else { return }
      handleHeartbeatFailure(error)
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
