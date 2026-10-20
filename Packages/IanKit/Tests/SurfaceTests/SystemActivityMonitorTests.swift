import AppKit
import Testing

@testable import Surface

@MainActor
private struct Rig {
  let workspace = NotificationCenter()
  let distributed = NotificationCenter()
  let monitor: SystemActivityMonitor
  let changes = Counter()

  init(locked: Bool = false) {
    monitor = SystemActivityMonitor(
      workspaceCenter: workspace, distributedCenter: distributed, screenIsLocked: locked)
    let changes = changes
    monitor.start { changes.count += 1 }
  }

  /// Notifications are delivered on the main queue, so let it run.
  func post(_ centre: NotificationCenter, _ name: String) async {
    centre.post(name: Notification.Name(name), object: nil)
    try? await Task.sleep(for: .milliseconds(20))
  }
}

@MainActor
private final class Counter { var count = 0 }

@Suite("System activity monitor")
@MainActor
struct SystemActivityMonitorTests {
  @Test("is active when the screen is unlocked and nothing sleeps")
  func activeByDefault() {
    #expect(Rig().monitor.isActive)
  }

  @Test("is not active when the session starts locked")
  func startsLocked() {
    #expect(!Rig(locked: true).monitor.isActive)
  }

  @Test("follows the screen lock and unlock, reporting each change")
  func followsTheLock() async {
    let rig = Rig()

    await rig.post(rig.distributed, "com.apple.screenIsLocked")
    #expect(!rig.monitor.isActive)
    await rig.post(rig.distributed, "com.apple.screenIsUnlocked")
    #expect(rig.monitor.isActive)
    #expect(rig.changes.count == 2)
  }

  @Test("follows display sleep and wake")
  func followsDisplaySleep() async {
    let rig = Rig()

    await rig.post(rig.workspace, NSWorkspace.screensDidSleepNotification.rawValue)
    #expect(!rig.monitor.isActive)
    await rig.post(rig.workspace, NSWorkspace.screensDidWakeNotification.rawValue)
    #expect(rig.monitor.isActive)
  }

  @Test("follows system sleep and wake")
  func followsSystemSleep() async {
    let rig = Rig()

    await rig.post(rig.workspace, NSWorkspace.willSleepNotification.rawValue)
    #expect(!rig.monitor.isActive)
    await rig.post(rig.workspace, NSWorkspace.didWakeNotification.rawValue)
    #expect(rig.monitor.isActive)
  }

  @Test("stays inactive until every reason has cleared, and reports only real changes")
  func needsEveryReasonCleared() async {
    let rig = Rig()

    await rig.post(rig.distributed, "com.apple.screenIsLocked")
    await rig.post(rig.workspace, NSWorkspace.screensDidSleepNotification.rawValue)
    await rig.post(rig.distributed, "com.apple.screenIsUnlocked")
    #expect(!rig.monitor.isActive)
    await rig.post(rig.workspace, NSWorkspace.screensDidWakeNotification.rawValue)

    #expect(rig.monitor.isActive)
    #expect(rig.changes.count == 2)
  }

  @Test("stops listening when stopped")
  func stopsListening() async {
    let rig = Rig()
    rig.monitor.stop()

    await rig.post(rig.distributed, "com.apple.screenIsLocked")

    #expect(rig.monitor.isActive)
    #expect(rig.changes.count == 0)
  }

  @Test("reads whole idle seconds that are never negative")
  func idleSecondsAreWhole() {
    #expect(Rig().monitor.idleSeconds >= 0)
  }
}
