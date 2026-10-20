import Testing

@testable import Attention

private let quiet = Suppression.none
private let paused = Suppression(
  cameraLive: false, externalMeeting: false, quietHours: false, userPaused: true)

@Suite("Stop arming")
@MainActor
struct StopArmingTests {
  @Test("opens the item's view on the next pointer movement, once")
  func opensOnce() {
    let arming = StopArming()
    arming.arm(.alerts, isPanelOpen: false, suppression: quiet)
    #expect(arming.isArmed)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: quiet) == .alerts)
    #expect(!arming.isArmed)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: quiet) == nil)
  }

  @Test("does not arm while suppressed")
  func notArmedWhileSuppressed() {
    let arming = StopArming()
    arming.arm(.alerts, isPanelOpen: false, suppression: paused)
    #expect(!arming.isArmed)
  }

  @Test("does not arm when the panel is already open")
  func notArmedWhenOpen() {
    let arming = StopArming()
    arming.arm(.alerts, isPanelOpen: true, suppression: quiet)
    #expect(!arming.isArmed)
  }

  @Test("opens nothing if the panel opened or suppression began after arming")
  func staleArming() {
    let arming = StopArming()
    arming.arm(.tasks, isPanelOpen: false, suppression: quiet)
    #expect(arming.pointerMoved(isPanelOpen: true, suppression: quiet) == nil)
    #expect(!arming.isArmed)

    arming.arm(.tasks, isPanelOpen: false, suppression: quiet)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: paused) == nil)
    #expect(!arming.isArmed)
  }

  @Test("a newer stop item takes over from an older one")
  func newerWins() {
    let arming = StopArming()
    arming.arm(.tasks, isPanelOpen: false, suppression: quiet)
    arming.arm(.proposals, isPanelOpen: false, suppression: quiet)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: quiet) == .proposals)
  }
}
