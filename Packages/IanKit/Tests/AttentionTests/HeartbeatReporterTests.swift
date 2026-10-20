import Foundation
import Observation
import TestSupport
import Testing

@testable import Attention

@MainActor
private final class FakeActivity: ActivityMonitoring {
  var isActive = true
  var idleSeconds = 0
  private(set) var started = false
  private(set) var stopped = false
  private var onChange: (@MainActor () -> Void)?

  func start(onChange: @escaping @MainActor () -> Void) {
    started = true
    self.onChange = onChange
  }

  func stop() { stopped = true }

  func setActive(_ active: Bool) {
    isActive = active
    onChange?()
  }
}

@MainActor
@Observable
private final class Inputs {
  var suppressed = false
  var session: Int? = 1
}

/// Holds a send open until the test lets it go.
private actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}

@MainActor
private final class Sent {
  private(set) var all: [(UUID, HeartbeatReading)] = []
  /// What the next sends answer.
  var delivers = true
  var gate: Gate?

  func record(_ device: UUID, _ reading: HeartbeatReading) async -> Bool {
    all.append((device, reading))
    await gate?.wait()
    return delivers
  }

  var readings: [HeartbeatReading] { all.map(\.1) }
}

@MainActor
private struct Rig {
  let clock = ManualClock()
  let activity = FakeActivity()
  let inputs = Inputs()
  let sent = Sent()
  let reporter: HeartbeatReporter

  init(device: UUID = UUID()) {
    let clock = clock
    let inputs = inputs
    let sent = sent
    reporter = HeartbeatReporter(
      deviceID: device,
      time: HeartbeatTime(
        now: { await clock.now() }, sleep: { try await clock.sleep(for: $0) }),
      activity: activity, suppressed: { inputs.suppressed }, session: { inputs.session },
      send: { await sent.record($0, $1) })
  }

  /// Lets the loop settle into its sleep and queued sends run, then moves time on.
  func advance(_ seconds: Int) async {
    await settle()
    await clock.advance(by: .seconds(seconds))
    await settle()
  }

  func settle() async {
    try? await Task.sleep(for: .milliseconds(30))
  }

  func sendsReach(_ count: Int) async -> Bool {
    await eventually("\(count) heartbeats") { await MainActor.run { sent.all.count >= count } }
  }
}

@Suite("Heartbeat reporter")
@MainActor
struct HeartbeatReporterTests {
  @Test("sends the first heartbeat as soon as it starts with a live session")
  func firstHeartbeat() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }

    #expect(await rig.sendsReach(1))
    #expect(
      rig.sent.readings == [HeartbeatReading(active: true, suppressed: false, idleSeconds: 0)])
  }

  @Test("sends every 60 seconds and not before")
  func periodic() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    await rig.advance(59)
    #expect(rig.sent.all.count == 1)
    await rig.advance(1)
    #expect(await rig.sendsReach(2))
    await rig.advance(59)
    #expect(rig.sent.all.count == 2)
    await rig.advance(1)
    #expect(await rig.sendsReach(3))
  }

  @Test("sends at once when the screen locks or unlocks")
  func activeChange() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.activity.setActive(false)
    #expect(await rig.sendsReach(2))
    rig.activity.setActive(true)
    #expect(await rig.sendsReach(3))

    #expect(rig.sent.readings.map(\.active) == [true, false, true])
  }

  @Test("sends at once when suppression changes")
  func suppressedChange() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.inputs.suppressed = true
    #expect(await rig.sendsReach(2))
    rig.inputs.suppressed = false
    #expect(await rig.sendsReach(3))

    #expect(rig.sent.readings.map(\.suppressed) == [false, true, false])
  }

  @Test("sends at once when the principal returns after a minute idle")
  func returnFromIdle() async {
    let rig = Rig()
    rig.activity.idleSeconds = 30
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    // The look at the moment idle could reach a minute finds the principal still away.
    rig.activity.idleSeconds = 65
    await rig.advance(30)
    #expect(rig.sent.all.count == 1)
    // From then on it looks every five seconds, to catch the return.
    rig.activity.idleSeconds = 3
    await rig.advance(5)

    #expect(await rig.sendsReach(2))
    #expect(rig.sent.readings.last?.idleSeconds == 3)
  }

  @Test("sends the next periodic heartbeat 60 seconds after one sent on a change")
  func periodicFollowsChange() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))
    await rig.advance(20)

    rig.inputs.suppressed = true
    #expect(await rig.sendsReach(2))
    await rig.advance(59)
    #expect(rig.sent.all.count == 2)
    await rig.advance(1)
    #expect(await rig.sendsReach(3))
  }

  @Test("sends nothing, and stops looking, while there is no live session")
  func silentWithoutSession() async {
    let rig = Rig()
    rig.inputs.session = nil
    rig.reporter.start()
    defer { rig.reporter.stop() }

    await rig.advance(120)

    #expect(rig.sent.all.isEmpty)
    #expect(await rig.clock.requestedSleeps.isEmpty)
  }

  @Test("sends the first heartbeat as soon as a session appears")
  func startsWhenSessionAppears() async {
    let rig = Rig()
    rig.inputs.session = nil
    rig.reporter.start()
    defer { rig.reporter.stop() }
    await rig.advance(30)

    rig.inputs.session = 1

    #expect(await rig.sendsReach(1))
  }

  @Test("keeps one device id across sends and across a new session, and sends at once on it")
  func sameDeviceAcrossSessions() async {
    let device = UUID()
    let rig = Rig(device: device)
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.inputs.session = nil
    rig.inputs.session = 2
    #expect(await rig.sendsReach(2))
    rig.activity.setActive(false)
    #expect(await rig.sendsReach(3))

    #expect(rig.sent.all.map(\.0) == [device, device, device])
  }

  @Test("keeps the schedule when the same session comes back from offline after a delivery")
  func offlineBlipKeepsTheSchedule() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.inputs.session = nil
    await rig.advance(20)
    rig.inputs.session = 1
    await rig.advance(20)

    #expect(rig.sent.all.count == 1)
  }

  @Test("backs off 5, 10, 20 and 40 seconds, then every interval, and starts again after a success")
  func backsOffAfterFailures() async {
    let rig = Rig()
    rig.sent.delivers = false
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    var count = 1
    for gap in [5, 10, 20, 40, 60, 60] {
      await rig.advance(gap - 1)
      #expect(rig.sent.all.count == count)
      await rig.advance(1)
      count += 1
      #expect(await rig.sendsReach(count))
    }

    rig.sent.delivers = true
    await rig.advance(59)
    await rig.advance(1)
    count += 1
    #expect(await rig.sendsReach(count))
    await rig.advance(59)
    #expect(rig.sent.all.count == count)

    rig.sent.delivers = false
    await rig.advance(1)
    count += 1
    #expect(await rig.sendsReach(count))
    await rig.advance(4)
    #expect(rig.sent.all.count == count)
    await rig.advance(1)
    #expect(await rig.sendsReach(count + 1))
  }

  @Test("sends a change at once while a retry is waiting")
  func changeBeatsTheBackoff() async {
    let rig = Rig()
    rig.sent.delivers = false
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.activity.setActive(false)

    #expect(await rig.sendsReach(2))
  }

  @Test("sends the first heartbeat of a new session at once when the old session's send fails")
  func newSessionDoesNotWaitForTheOldFailure() async {
    let rig = Rig()
    let gate = Gate()
    rig.sent.gate = gate
    rig.sent.delivers = false
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.inputs.session = 2
    await rig.settle()
    await gate.open()

    #expect(await rig.sendsReach(2))
  }

  @Test("waits for the periodic send while the Mac is locked, instead of looking every 5 seconds")
  func quietWhileLocked() async {
    let rig = Rig()
    rig.activity.isActive = false
    rig.activity.idleSeconds = 600
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))
    await rig.settle()

    #expect(await rig.clock.requestedSleeps.last == .seconds(60))
  }

  @Test("looks every 5 seconds while the principal is at the Mac and has been idle a minute")
  func watchesForTheReturn() async {
    let rig = Rig()
    rig.activity.idleSeconds = 600
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))
    await rig.settle()

    #expect(await rig.clock.requestedSleeps.last == .seconds(5))
  }

  @Test("runs one chain after a stop and a start, and does nothing while stopped")
  func restartRunsOnce() async {
    let rig = Rig()
    rig.reporter.start()
    #expect(await rig.sendsReach(1))
    rig.reporter.stop()
    rig.inputs.suppressed = true
    await rig.settle()
    #expect(rig.sent.all.count == 1)

    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(2))
    await rig.settle()
    rig.inputs.suppressed = false
    #expect(await rig.sendsReach(3))
    await rig.settle()

    #expect(rig.sent.all.count == 3)
  }

  @Test("lets one send wait behind a slow one and sends the latest values in it")
  func slowSendKeepsOneWaiting() async {
    let rig = Rig()
    let gate = Gate()
    rig.sent.gate = gate
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.activity.setActive(false)
    rig.inputs.suppressed = true
    await rig.settle()
    #expect(rig.sent.all.count == 1)
    await gate.open()

    #expect(await rig.sendsReach(2))
    await rig.settle()
    #expect(rig.sent.all.count == 2)
    #expect(
      rig.sent.readings.last == HeartbeatReading(active: false, suppressed: true, idleSeconds: 0))
  }

  @Test("makes a device id of its own when none is given")
  func randomDeviceID() {
    func reporter() -> HeartbeatReporter {
      HeartbeatReporter(
        activity: FakeActivity(), suppressed: { false }, session: { nil }, send: { _, _ in true })
    }
    #expect(reporter().deviceID != reporter().deviceID)
  }

  @Test("stops watching the activity monitor when stopped, and starts it when started")
  func startsAndStopsTheMonitor() {
    let rig = Rig()
    rig.reporter.start()
    #expect(rig.activity.started)
    rig.reporter.stop()
    #expect(rig.activity.stopped)
  }
}
