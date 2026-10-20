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

  /// How long to wait before looking again, or nil to stop looking until something changes.
  ///
  /// It sleeps until the periodic send is due, or until idle seconds could reach
  /// `idleReturnSeconds`, whichever is sooner. Only while the principal is at the Mac and has been
  /// idle that long does it look every `checkInterval`, to catch the return. While the Mac is
  /// locked or asleep it waits for the periodic send, since an unlock or a wake announces itself.
  /// A failed send moves the periodic send to its retry time (`sendFailed`), so retries and their
  /// backoff come through here too.
  func untilNextLook(at now: Duration, reading: HeartbeatReading) -> Duration {
    guard let lastSent else { return timing.checkInterval }
    let untilDue = max(.zero, timing.interval - (now - lastSent.at))
    guard reading.active else { return untilDue }
    if reading.idleSeconds >= timing.idleReturnSeconds {
      return min(timing.checkInterval, untilDue)
    }
    let untilIdle = Duration.seconds(max(1, timing.idleReturnSeconds - reading.idleSeconds))
    return min(untilIdle, untilDue)
  }

  /// Puts the reading actually sent in place of the one recorded when the send was decided,
  /// because a send that waited behind another reads the inputs again when its turn comes.
  mutating func amendSent(_ reading: HeartbeatReading) {
    guard let lastSent else { return }
    self.lastSent = (reading, lastSent.at)
  }

  /// Moves the next periodic send to `retryIn` from now, because the last one was not
  /// delivered. A change still sends at once.
  mutating func sendFailed(at now: Duration, retryIn: Duration) {
    guard let lastSent else { return }
    self.lastSent = (lastSent.reading, now + retryIn - timing.interval)
  }

  /// Forgets everything, for a new session.
  mutating func reset() {
    lastSent = nil
    lastIdleSeconds = nil
  }

  private mutating func record(_ reading: HeartbeatReading, at now: Duration) {
    lastSent = (reading, now)
  }
}
