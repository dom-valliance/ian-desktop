import AppKit
import Testing

@testable import Surface

@MainActor
private final class Counter { var count = 0 }

/// The login session as the window server would describe it, which a test changes.
@MainActor
private final class FakeSession {
  var isLocked = false
  var isOnConsole = true
  var dictionary: [String: Any]?

  func read() -> [String: Any]? {
    dictionary ?? ["CGSSessionScreenIsLocked": isLocked, "kCGSSessionOnConsoleKey": isOnConsole]
  }
}

@MainActor
private struct Rig {
  let workspace = NotificationCenter()
  /// Local to this process, so posting a lock notification reaches nothing else.
  let distributed = DistributedNotificationCenter.forType(.localNotificationCenterType)
  let session = FakeSession()
  let monitor: SystemActivityMonitor
  let changes = Counter()

  init() {
    let session = session
    monitor = SystemActivityMonitor(
      workspaceCenter: workspace, distributedCenter: distributed,
      sessionState: { session.read() }, sleep: { _ in })
    let changes = changes
    monitor.start { changes.count += 1 }
  }

  /// Notifications to the workspace centre are delivered on the main queue, so let it run.
  func post(_ centre: NotificationCenter, _ name: String) async {
    centre.post(name: Notification.Name(name), object: nil)
    try? await Task.sleep(for: .milliseconds(20))
  }

  func lock(_ locked: Bool) async {
    session.isLocked = locked
    await post(distributed, locked ? "com.apple.screenIsLocked" : "com.apple.screenIsUnlocked")
  }
}

@Suite("System activity monitor")
@MainActor
struct SystemActivityMonitorTests {
  @Test("is active when the screen is unlocked and nothing sleeps")
  func activeByDefault() {
    #expect(Rig().monitor.isActive)
  }

  @Test("reads the lock from the session each time, with no notification needed")
  func readsTheLockLive() {
    let rig = Rig()

    rig.session.isLocked = true
    #expect(!rig.monitor.isActive)
    rig.session.isLocked = false
    #expect(rig.monitor.isActive)
  }

  @Test("is not active when the session is not on the console")
  func fastUserSwitching() {
    let rig = Rig()

    rig.session.isOnConsole = false

    #expect(!rig.monitor.isActive)
  }

  @Test("counts a session it cannot read as active")
  func unreadableSessionIsActive() {
    let rig = Rig()
    rig.session.dictionary = [:]

    #expect(rig.monitor.isActive)
  }

  @Test("reports a lock and an unlock as they are announced")
  func reportsTheLock() async {
    let rig = Rig()

    await rig.lock(true)
    #expect(!rig.monitor.isActive)
    await rig.lock(false)

    #expect(rig.monitor.isActive)
    #expect(rig.changes.count == 2)
  }

  @Test("looks again after a lock notification, in case the session updated a moment later")
  func looksAgainAfterTheNotification() async {
    let rig = Rig()

    rig.distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
    rig.session.isLocked = true
    try? await Task.sleep(for: .milliseconds(20))

    #expect(!rig.monitor.isActive)
    #expect(rig.changes.count == 1)
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

    await rig.lock(true)
    await rig.post(rig.workspace, NSWorkspace.screensDidSleepNotification.rawValue)
    await rig.lock(false)
    #expect(!rig.monitor.isActive)
    await rig.post(rig.workspace, NSWorkspace.screensDidWakeNotification.rawValue)

    #expect(rig.monitor.isActive)
    #expect(rig.changes.count == 2)
  }

  @Test("stops listening when stopped")
  func stopsListening() async {
    let rig = Rig()
    rig.monitor.stop()

    await rig.lock(true)

    #expect(rig.changes.count == 0)
  }
}
