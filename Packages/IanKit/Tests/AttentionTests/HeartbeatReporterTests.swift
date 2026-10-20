import Client
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

@MainActor
private final class Sent {
  private(set) var all: [(UUID, HeartbeatReading)] = []
  func record(_ device: UUID, _ reading: HeartbeatReading) { all.append((device, reading)) }
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
    let activity = activity
    let inputs = inputs
    let sent = sent
    reporter = HeartbeatReporter(
      deviceID: device, clock: clock, activity: activity, suppressed: { inputs.suppressed },
      session: { inputs.session }, send: { sent.record($0, $1) })
  }

  /// Lets the loop sleep, then moves time on by one check interval.
  func tick(_ seconds: Int = 5) async {
    await clock.waitForSleepers()
    await clock.advance(by: .seconds(seconds))
  }

  func tick(times: Int) async {
    for _ in 0..<times { await tick() }
    await settle()
  }

  /// Waits until the loop is asleep again, then gives queued sends a moment to run.
  func settle() async {
    await clock.waitForSleepers()
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

    await rig.tick(times: 11)
    #expect(rig.sent.all.count == 1)
    await rig.tick(times: 1)
    #expect(await rig.sendsReach(2))
    await rig.tick(times: 11)
    #expect(rig.sent.all.count == 2)
    await rig.tick(times: 1)
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
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.activity.idleSeconds = 90
    await rig.tick(times: 1)
    #expect(rig.sent.all.count == 1)
    rig.activity.idleSeconds = 3
    await rig.tick(times: 1)

    #expect(await rig.sendsReach(2))
    #expect(rig.sent.readings.last?.idleSeconds == 3)
  }

  @Test("sends the next periodic heartbeat 60 seconds after one sent on a change")
  func periodicFollowsChange() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))
    await rig.tick(times: 4)

    rig.inputs.suppressed = true
    #expect(await rig.sendsReach(2))
    await rig.tick(times: 11)
    #expect(rig.sent.all.count == 2)
    await rig.tick(times: 1)
    #expect(await rig.sendsReach(3))
  }

  @Test("sends nothing while there is no live session")
  func silentWithoutSession() async {
    let rig = Rig()
    rig.inputs.session = nil
    rig.reporter.start()
    defer { rig.reporter.stop() }

    await rig.tick(times: 14)

    #expect(rig.sent.all.isEmpty)
  }

  @Test("sends the first heartbeat as soon as a session appears")
  func startsWhenSessionAppears() async {
    let rig = Rig()
    rig.inputs.session = nil
    rig.reporter.start()
    defer { rig.reporter.stop() }
    await rig.tick(times: 3)

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

  @Test("does not repeat the first heartbeat when the same session comes back from offline")
  func offlineBlipKeepsTheSchedule() async {
    let rig = Rig()
    rig.reporter.start()
    defer { rig.reporter.stop() }
    #expect(await rig.sendsReach(1))

    rig.inputs.session = nil
    await rig.tick(times: 2)
    rig.inputs.session = 1
    await rig.tick(times: 2)

    #expect(rig.sent.all.count == 1)
  }

  @Test("makes a device id of its own when none is given")
  func randomDeviceID() {
    func reporter() -> HeartbeatReporter {
      HeartbeatReporter(
        activity: FakeActivity(), suppressed: { false }, session: { nil }, send: { _, _ in })
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
