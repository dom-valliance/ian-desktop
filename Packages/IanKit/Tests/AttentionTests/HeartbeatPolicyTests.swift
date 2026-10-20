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

  func untilNextLook(at now: Duration) -> Duration { policy.untilNextLook(at: now) }
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

  @Test("looks again after the check interval, or sooner when a periodic send falls due")
  func untilNextLook() {
    #expect(policy.untilNextLook(at: .zero) == .seconds(5))
    _ = policy.decide(reading(), at: .zero)
    #expect(policy.untilNextLook(at: .zero) == .seconds(5))
    #expect(policy.untilNextLook(at: .seconds(57)) == .seconds(3))
    #expect(policy.untilNextLook(at: .seconds(60)) == .zero)
  }

  @Test("reports idle seconds as at least zero")
  func clampsIdle() {
    #expect(reading(idle: -4).idleSeconds == 0)
  }
}
