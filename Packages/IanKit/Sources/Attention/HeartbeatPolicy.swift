/// What one session heartbeat reports (spec 4, step 7). The client only reports; Lance applies
/// its own idle rule to `idleSeconds`.
public struct HeartbeatReading: Equatable, Sendable {
  public let active: Bool
  public let suppressed: Bool
  public let idleSeconds: Int

  public init(active: Bool, suppressed: Bool, idleSeconds: Int) {
    self.active = active
    self.suppressed = suppressed
    self.idleSeconds = max(0, idleSeconds)
  }
}

public struct HeartbeatTiming: Equatable, Sendable {
  /// The gap between periodic heartbeats, counted from the last one sent for any reason.
  public var interval: Duration
  /// How often the reporter looks for a change when none has announced itself.
  public var checkInterval: Duration
  /// Idle seconds at or above this count as having been away; dropping below it sends at once.
  public var idleReturnSeconds: Int

  public init(
    interval: Duration = .seconds(60), checkInterval: Duration = .seconds(5),
    idleReturnSeconds: Int = 60
  ) {
    self.interval = interval
    self.checkInterval = checkInterval
    self.idleReturnSeconds = idleReturnSeconds
  }
}

/// Decides when a heartbeat goes out. Pure: it reads the clock and the readings it is given and
/// never waits, so tests run it without time passing.
///
/// A heartbeat is due when none has been sent yet, when `interval` has passed since the last one,
/// when `active` or `suppressed` differ from the last one sent, or when the principal returns
/// after being idle for `idleReturnSeconds`.
struct HeartbeatPolicy {
  private let timing: HeartbeatTiming
  private var lastSent: (reading: HeartbeatReading, at: Duration)?
  private var lastIdleSeconds: Int?

  init(timing: HeartbeatTiming) {
    self.timing = timing
  }

  /// Whether to send now. A yes counts as the send: the next periodic one is a full interval on.
  mutating func decide(_ reading: HeartbeatReading, at now: Duration) -> Bool {
    defer { lastIdleSeconds = reading.idleSeconds }
    guard let lastSent else {
      record(reading, at: now)
      return true
    }
    let returned =
      (lastIdleSeconds ?? 0) >= timing.idleReturnSeconds
      && reading.idleSeconds < timing.idleReturnSeconds
    let changed =
      reading.active != lastSent.reading.active
      || reading.suppressed != lastSent.reading.suppressed
    guard returned || changed || now - lastSent.at >= timing.interval else { return false }
    record(reading, at: now)
    return true
  }

  /// How long until the next look: the check interval, or less when a periodic send falls due
  /// first.
  func untilNextLook(at now: Duration) -> Duration {
    guard let lastSent else { return timing.checkInterval }
    return min(timing.checkInterval, max(.zero, timing.interval - (now - lastSent.at)))
  }

  /// Forgets everything sent, so the next reading is sent at once. Used when the session ends.
  mutating func reset() {
    lastSent = nil
    lastIdleSeconds = nil
  }

  private mutating func record(_ reading: HeartbeatReading, at now: Duration) {
    lastSent = (reading, now)
  }
}
