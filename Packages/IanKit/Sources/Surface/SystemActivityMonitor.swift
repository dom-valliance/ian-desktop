import AppKit
import Attention

/// Reads whether the principal can be at the Mac, from the screen lock, the displays and system
/// sleep, and how long input has been still. Nothing is stored, and no input is read: the idle
/// time is one number from the window server.
@MainActor
public final class SystemActivityMonitor: ActivityMonitoring {
  private let workspaceCenter: NotificationCenter
  private let distributedCenter: NotificationCenter
  private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
  private var onChange: (@MainActor () -> Void)?

  private var isScreenLocked: Bool
  private var areDisplaysAsleep = false
  private var isSystemAsleep = false

  /// - Parameters:
  ///   - workspaceCenter: Where sleep and wake are posted. Tests pass their own centre.
  ///   - distributedCenter: Where the lock and unlock are posted, across processes.
  ///   - screenIsLocked: The lock state at start, which no notification announces.
  public init(
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
    screenIsLocked: Bool = SystemActivityMonitor.sessionIsLocked()
  ) {
    self.workspaceCenter = workspaceCenter
    self.distributedCenter = distributedCenter
    self.isScreenLocked = screenIsLocked
  }

  public var isActive: Bool { !isScreenLocked && !areDisplaysAsleep && !isSystemAsleep }

  /// Any keyboard or pointer input, in the combined session state.
  public var idleSeconds: Int {
    let seconds = CGEventSource.secondsSinceLastEventType(
      .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    return seconds.isFinite ? max(0, Int(seconds)) : 0
  }

  public func start(onChange: @escaping @MainActor () -> Void) {
    guard observers.isEmpty else { return }
    self.onChange = onChange
    watch(distributedCenter, "com.apple.screenIsLocked") { $0.isScreenLocked = true }
    watch(distributedCenter, "com.apple.screenIsUnlocked") { $0.isScreenLocked = false }
    watch(workspaceCenter, NSWorkspace.screensDidSleepNotification.rawValue) {
      $0.areDisplaysAsleep = true
    }
    watch(workspaceCenter, NSWorkspace.screensDidWakeNotification.rawValue) {
      $0.areDisplaysAsleep = false
    }
    watch(workspaceCenter, NSWorkspace.willSleepNotification.rawValue) { $0.isSystemAsleep = true }
    watch(workspaceCenter, NSWorkspace.didWakeNotification.rawValue) { $0.isSystemAsleep = false }
  }

  public func stop() {
    for observer in observers { observer.center.removeObserver(observer.token) }
    observers = []
    onChange = nil
  }

  /// Applies `change`, then reports it when `isActive` moved.
  private func watch(
    _ center: NotificationCenter, _ name: String,
    _ change: @escaping @MainActor (SystemActivityMonitor) -> Void
  ) {
    let token = center.addObserver(
      forName: Notification.Name(name), object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let before = self.isActive
        change(self)
        if self.isActive != before { self.onChange?() }
      }
    }
    observers.append((center, token))
  }

  /// Whether the login session is locked now, from the session dictionary.
  public nonisolated static func sessionIsLocked() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
  }
}
