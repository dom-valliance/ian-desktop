import Testing

@testable import Attention

@MainActor
final class FakeCamera: CameraMonitoring {
  var isLive = false
  private var onChange: (@MainActor () -> Void)?
  private(set) var stopped = false

  func start(onChange: @escaping @MainActor () -> Void) {
    self.onChange = onChange
  }

  func stop() {
    stopped = true
  }

  func setLive(_ live: Bool) {
    isLive = live
    onChange?()
  }
}

@Suite("Suppression")
struct SuppressionTests {
  @Test("is inactive when no trigger holds")
  func inactiveWithoutTriggers() {
    #expect(!Suppression.none.isActive)
    #expect(Suppression.none.triggers.isEmpty)
  }

  @Test(
    "is active for each trigger alone",
    arguments: [
      (
        Suppression.Trigger.cameraLive,
        Suppression(cameraLive: true, externalMeeting: false, quietHours: false, userPaused: false)
      ),
      (
        .externalMeeting,
        Suppression(cameraLive: false, externalMeeting: true, quietHours: false, userPaused: false)
      ),
      (
        .quietHours,
        Suppression(cameraLive: false, externalMeeting: false, quietHours: true, userPaused: false)
      ),
      (
        .userPaused,
        Suppression(cameraLive: false, externalMeeting: false, quietHours: false, userPaused: true)
      ),
    ])
  func activeForEachTrigger(trigger: Suppression.Trigger, suppression: Suppression) {
    #expect(suppression.isActive)
    #expect(suppression.triggers == [trigger])
  }

  @Test("lists every trigger that holds, in a fixed order")
  func listsAllTriggers() {
    let suppression = Suppression(
      cameraLive: true, externalMeeting: true, quietHours: false, userPaused: true)
    #expect(suppression.triggers == [.cameraLive, .externalMeeting, .userPaused])
  }
}

@Suite("Suppression signals")
@MainActor
struct SuppressionSignalsTests {
  @Test("follows the camera monitor once started")
  func followsCamera() {
    let camera = FakeCamera()
    let signals = SuppressionSignals(camera: camera)
    signals.start()
    #expect(signals.suppression(externalMeeting: false, quietHours: false) == .none)

    camera.setLive(true)
    #expect(signals.cameraLive)
    #expect(
      signals.suppression(externalMeeting: false, quietHours: false).triggers == [.cameraLive])

    camera.setLive(false)
    #expect(!signals.cameraLive)
  }

  @Test("starts with the camera state it finds")
  func readsInitialCameraState() {
    let camera = FakeCamera()
    camera.isLive = true
    let signals = SuppressionSignals(camera: camera)
    signals.start()
    #expect(signals.cameraLive)
  }

  @Test("holds the user's pause in memory and reports it as a trigger")
  func pauseIsATrigger() {
    let signals = SuppressionSignals(camera: FakeCamera())
    signals.isPaused = true
    #expect(
      signals.suppression(externalMeeting: false, quietHours: false).triggers == [.userPaused])
  }

  @Test("combines the server's context with the local signals")
  func combinesServerContext() {
    let signals = SuppressionSignals(camera: FakeCamera())
    let suppression = signals.suppression(externalMeeting: true, quietHours: true)
    #expect(suppression.triggers == [.externalMeeting, .quietHours])
  }

  @Test("stops the camera monitor and clears its state")
  func stopsCamera() {
    let camera = FakeCamera()
    let signals = SuppressionSignals(camera: camera)
    signals.start()
    camera.setLive(true)
    signals.stop()
    #expect(camera.stopped)
    #expect(!signals.cameraLive)
  }
}

@Suite("Core Media camera monitor")
@MainActor
struct CoreMediaCameraMonitorTests {
  @Test("starts and stops against the real devices without failing")
  func startsAndStops() {
    let monitor = CoreMediaCameraMonitor()
    monitor.start {}
    monitor.start {}
    monitor.stop()
    monitor.stop()
    #expect(!monitor.isLive)
  }
}
