import Testing

@testable import Attention

private func reading(active: Bool = true, suppressed: Bool = false, idle: Int = 0)
  -> HeartbeatReading
{
  HeartbeatReading(active: active, suppressed: suppressed, idleSeconds: idle)
}

/// Holds the policy by reference, so `#expect` can call its mutating methods.
private final class Probe {
  private var policy = HeartbeatPolicy(timing: HeartbeatTiming())

  func decide(_ reading: HeartbeatReading, at now: Duration) -> Bool {
    policy.decide(reading, at: now)
  }

  func untilNextLook(at now: Duration, _ reading: HeartbeatReading) -> Duration {
    policy.untilNextLook(at: now, reading: reading)
  }

  func sendFailed(at now: Duration, retryIn: Duration) {
    policy.sendFailed(at: now, retryIn: retryIn)
  }

  func amend(_ reading: HeartbeatReading) { policy.amendSent(reading) }
  func reset() { policy.reset() }
}

@Suite("Heartbeat policy")
struct HeartbeatPolicyTests {
  private let policy = Probe()

  @Test("sends the first reading at once")
  func sendsFirst() {
    #expect(policy.decide(reading(), at: .zero))
  }

  @Test("waits for the interval, then sends, then waits again from that send")
  func sendsEveryInterval() {
    #expect(policy.decide(reading(), at: .zero))
    #expect(!policy.decide(reading(), at: .seconds(59)))
    #expect(policy.decide(reading(), at: .seconds(60)))
    #expect(!policy.decide(reading(), at: .seconds(119)))
    #expect(policy.decide(reading(), at: .seconds(120)))
  }

  @Test("sends at once when active changes")
  func sendsOnActiveChange() {
    _ = policy.decide(reading(), at: .zero)
    #expect(policy.decide(reading(active: false), at: .seconds(3)))
    #expect(policy.decide(reading(active: true), at: .seconds(4)))
  }

  @Test("sends at once when suppressed changes")
  func sendsOnSuppressedChange() {
    _ = policy.decide(reading(), at: .zero)
    #expect(policy.decide(reading(suppressed: true), at: .seconds(3)))
    #expect(!policy.decide(reading(suppressed: true), at: .seconds(4)))
  }

  @Test("waits a full interval after a change before the next periodic send")
  func periodicSendFollowsTheChange() {
    _ = policy.decide(reading(), at: .zero)
    _ = policy.decide(reading(suppressed: true), at: .seconds(20))
    #expect(!policy.decide(reading(suppressed: true), at: .seconds(60)))
    #expect(!policy.decide(reading(suppressed: true), at: .seconds(79)))
    #expect(policy.decide(reading(suppressed: true), at: .seconds(80)))
  }

  @Test("sends at once when the principal returns after a minute idle")
  func sendsOnReturnFromIdle() {
    _ = policy.decide(reading(idle: 0), at: .zero)
    #expect(!policy.decide(reading(idle: 70), at: .seconds(5)))
    #expect(policy.decide(reading(idle: 2), at: .seconds(10)))
  }

  @Test("does not treat short pauses as a return")
  func ignoresShortPauses() {
    _ = policy.decide(reading(idle: 0), at: .zero)
    #expect(!policy.decide(reading(idle: 59), at: .seconds(5)))
    #expect(!policy.decide(reading(idle: 1), at: .seconds(10)))
  }

  @Test("does not send repeatedly while the principal stays away")
  func staysQuietWhileIdle() {
    _ = policy.decide(reading(idle: 0), at: .zero)
    #expect(!policy.decide(reading(idle: 70), at: .seconds(5)))
    #expect(!policy.decide(reading(idle: 75), at: .seconds(10)))
  }

  @Test("sends the next reading at once after a reset")
  func resetSendsAgain() {
    _ = policy.decide(reading(), at: .zero)
    policy.reset()
    #expect(policy.decide(reading(), at: .seconds(1)))
  }

  @Test("looks every check interval before anything has been sent")
  func looksOftenBeforeTheFirstSend() {
    #expect(policy.untilNextLook(at: .zero, reading()) == .seconds(5))
  }

  @Test("moves the periodic send to the retry time after a failed send")
  func retriesAfterAFailure() {
    _ = policy.decide(reading(), at: .zero)
    policy.sendFailed(at: .seconds(1), retryIn: .seconds(10))
    #expect(policy.untilNextLook(at: .seconds(1), reading()) == .seconds(10))
    #expect(!policy.decide(reading(), at: .seconds(10)))
    #expect(policy.decide(reading(), at: .seconds(11)))
  }

  @Test("still sends a change at once while a retry is waiting")
  func changeBeatsTheRetry() {
    _ = policy.decide(reading(), at: .zero)
    policy.sendFailed(at: .seconds(1), retryIn: .seconds(40))
    #expect(policy.decide(reading(suppressed: true), at: .seconds(2)))
  }

  @Test("sleeps until the periodic send or until idle could reach a minute, whichever is sooner")
  func sleepsUntilSomethingCouldChange() {
    _ = policy.decide(reading(), at: .zero)
    #expect(policy.untilNextLook(at: .zero, reading(idle: 0)) == .seconds(60))
    #expect(policy.untilNextLook(at: .zero, reading(idle: 45)) == .seconds(15))
    #expect(policy.untilNextLook(at: .seconds(50), reading(idle: 0)) == .seconds(10))
    #expect(policy.untilNextLook(at: .seconds(60), reading(idle: 0)) == .zero)
  }

  @Test("looks every check interval while the principal is at the Mac and has been idle a minute")
  func looksOftenWhileIdle() {
    _ = policy.decide(reading(), at: .zero)
    #expect(policy.untilNextLook(at: .seconds(10), reading(idle: 60)) == .seconds(5))
    #expect(policy.untilNextLook(at: .seconds(57), reading(idle: 300)) == .seconds(3))
  }

  @Test("waits for the periodic send while the Mac is locked or asleep")
  func waitsWhileInactive() {
    _ = policy.decide(reading(), at: .zero)
    #expect(
      policy.untilNextLook(at: .seconds(10), reading(active: false, idle: 300)) == .seconds(50))
    #expect(policy.untilNextLook(at: .seconds(10), reading(active: false, idle: 5)) == .seconds(50))
  }

  @Test("records the reading actually sent in place of the one decided on")
  func amendsTheSentReading() {
    _ = policy.decide(reading(), at: .zero)
    policy.amend(reading(suppressed: true))
    #expect(!policy.decide(reading(suppressed: true), at: .seconds(1)))
  }

  @Test("reports idle seconds as at least zero")
  func clampsIdle() {
    #expect(reading(idle: -4).idleSeconds == 0)
  }
}
