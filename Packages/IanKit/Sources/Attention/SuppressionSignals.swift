import Observation

/// The local inputs to suppression: the camera and the principal's own pause. The server's two
/// inputs, `inExternalMeeting` and `quietHoursActive`, are passed in by the caller.
///
/// The pause is held in memory only. Nothing about it is written to disk (AGENTS.md rule 5), so
/// a relaunch starts unpaused.
@MainActor
@Observable
public final class SuppressionSignals {
  public private(set) var cameraLive = false
  public var isPaused = false

  private let camera: any CameraMonitoring

  public init(camera: any CameraMonitoring) {
    self.camera = camera
  }

  /// Starts watching the camera.
  public func start() {
    camera.start { [weak self] in
      guard let self else { return }
      self.cameraLive = self.camera.isLive
    }
    cameraLive = camera.isLive
  }

  public func stop() {
    camera.stop()
    cameraLive = false
  }

  public func suppression(externalMeeting: Bool, quietHours: Bool) -> Suppression {
    Suppression(
      cameraLive: cameraLive, externalMeeting: externalMeeting, quietHours: quietHours,
      userPaused: isPaused)
  }
}
