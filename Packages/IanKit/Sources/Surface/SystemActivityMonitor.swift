import AppKit
import Attention

/// Reads whether the principal can be at the Mac, from the login session, the displays and system
/// sleep, and how long input has been still. Nothing is stored, and no input is read: the idle
/// time is one number from the window server.
///
/// The lock is read from the session each time `isActive` is asked, because the system's lock
/// notification is held back while an app is not active, and Ian almost never is. The
/// notifications still make a change reach `onChange` at once when they do arrive.
@MainActor
public final class SystemActivityMonitor: ActivityMonitoring {
  private let workspaceCenter: NotificationCenter
  private let distributedCenter: DistributedNotificationCenter
  private let sessionState: @MainActor () -> [String: Any]?
  private let sleep: @Sendable (Duration) async throws -> Void
  private var followUp: Task<Void, Never>?
  private var workspaceTokens: [any NSObjectProtocol] = []
  private var distributedTarget: DistributedTarget?
  private var onChange: (@MainActor () -> Void)?
  private var lastReportedActive: Bool?

  private var areDisplaysAsleep = false
  private var isSystemAsleep = false

  /// - Parameters:
  ///   - workspaceCenter: Where sleep and wake are posted. Tests pass their own centre.
  ///   - distributedCenter: Where the lock and unlock are posted, across processes.
  ///   - sessionState: The login session's dictionary. Tests pass their own.
  ///   - sleep: Waits before the second look after a lock or unlock. Tests pass their own.
  public init(
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    distributedCenter: DistributedNotificationCenter = .default(),
    sessionState: @escaping @MainActor () -> [String: Any]? = {
      CGSessionCopyCurrentDictionary() as? [String: Any]
    },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.workspaceCenter = workspaceCenter
    self.distributedCenter = distributedCenter
    self.sessionState = sessionState
    self.sleep = sleep
  }

  /// The screen is unlocked, the session is on the console (not switched away from), the
  /// displays are awake and the system is not going to sleep.
  public var isActive: Bool {
    let session = sessionState()
    let isLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    let isOnConsole = session?[kCGSessionOnConsoleKey as String] as? Bool ?? true
    return !isLocked && isOnConsole && !areDisplaysAsleep && !isSystemAsleep
  }

  /// Any keyboard or pointer input, in the combined session state.
  public var idleSeconds: Int {
    let seconds = CGEventSource.secondsSinceLastEventType(
      .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    return seconds.isFinite ? max(0, Int(seconds)) : 0
  }

  public func start(onChange: @escaping @MainActor () -> Void) {
    guard distributedTarget == nil else { return }
    self.onChange = onChange
    lastReportedActive = isActive
    let target = DistributedTarget { [weak self] in self?.lockChanged() }
    // Delivered at once even while Ian is in the background, which is nearly always.
    for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
      distributedCenter.addObserver(
        target, selector: #selector(DistributedTarget.received), name: Notification.Name(name),
        object: nil, suspensionBehavior: .deliverImmediately)
    }
    distributedTarget = target
    watch(NSWorkspace.screensDidSleepNotification) { $0.areDisplaysAsleep = true }
    watch(NSWorkspace.screensDidWakeNotification) { $0.areDisplaysAsleep = false }
    watch(NSWorkspace.willSleepNotification) { $0.isSystemAsleep = true }
    watch(NSWorkspace.didWakeNotification) { $0.isSystemAsleep = false }
  }

  public func stop() {
    if let target = distributedTarget { distributedCenter.removeObserver(target) }
    distributedTarget = nil
    for token in workspaceTokens { workspaceCenter.removeObserver(token) }
    workspaceTokens = []
    followUp?.cancel()
    followUp = nil
    onChange = nil
    lastReportedActive = nil
  }

  /// The session dictionary may update a moment after the notification arrives, so look once
  /// now and once again after a second.
  private func lockChanged() {
    report()
    followUp?.cancel()
    followUp = Task { [weak self, sleep] in
      guard (try? await sleep(.seconds(1))) != nil, !Task.isCancelled else { return }
      self?.report()
    }
  }

  private func watch(
    _ name: Notification.Name, _ change: @escaping @MainActor (SystemActivityMonitor) -> Void
  ) {
    workspaceTokens.append(
      workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          change(self)
          self.report()
        }
      })
  }

  /// Tells the owner when `isActive` has moved since it was last reported.
  private func report() {
    let active = isActive
    guard active != lastReportedActive else { return }
    lastReportedActive = active
    onChange?()
  }
}

/// Receives the distributed notifications, which the selector-based API needs an object for.
@MainActor
private final class DistributedTarget: NSObject {
  private let handler: @MainActor () -> Void

  init(handler: @escaping @MainActor () -> Void) {
    self.handler = handler
  }

  @objc func received(_ notification: Notification) {
    handler()
  }
}
