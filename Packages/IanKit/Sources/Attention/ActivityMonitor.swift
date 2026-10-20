/// What the session heartbeat reads about the Mac: whether the principal can be at it, and how
/// long the keyboard and pointer have been still. A protocol so tests inject a fake.
@MainActor
public protocol ActivityMonitoring: AnyObject {
  /// The screen is unlocked, the displays are awake and the system is not going to sleep.
  var isActive: Bool { get }
  /// Whole seconds since the last keyboard or pointer input, never below 0.
  var idleSeconds: Int { get }
  /// Starts observing. `onChange` runs on the main actor each time `isActive` changes.
  func start(onChange: @escaping @MainActor () -> Void)
  func stop()
}
