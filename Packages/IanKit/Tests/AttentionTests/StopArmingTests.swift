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
    arming.arm(.alerts, for: "item_1", isPanelOpen: false, suppression: quiet)
    #expect(arming.isArmed)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: quiet) == .alerts)
    #expect(!arming.isArmed)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: quiet) == nil)
  }

  @Test("does not arm while suppressed")
  func notArmedWhileSuppressed() {
    let arming = StopArming()
    arming.arm(.alerts, for: "item_1", isPanelOpen: false, suppression: paused)
    #expect(!arming.isArmed)
  }

  @Test("does not arm when the panel is already open")
  func notArmedWhenOpen() {
    let arming = StopArming()
    arming.arm(.alerts, for: "item_1", isPanelOpen: true, suppression: quiet)
    #expect(!arming.isArmed)
  }

  @Test("opens nothing if the panel opened or suppression began after arming")
  func staleArming() {
    let arming = StopArming()
    arming.arm(.tasks, for: "item_1", isPanelOpen: false, suppression: quiet)
    #expect(arming.pointerMoved(isPanelOpen: true, suppression: quiet) == nil)
    #expect(!arming.isArmed)

    arming.arm(.tasks, for: "item_1", isPanelOpen: false, suppression: quiet)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: paused) == nil)
    #expect(!arming.isArmed)
  }

  @Test("disarms when the item that armed it is removed, and not for another item")
  func disarmsForItsItem() {
    let arming = StopArming()
    arming.arm(.alerts, for: "item_1", isPanelOpen: false, suppression: quiet)
    arming.disarm(ifArmedFor: "item_2")
    #expect(arming.isArmed)
    arming.disarm(ifArmedFor: "item_1")
    #expect(!arming.isArmed)
  }

  @Test("a newer stop item takes over from an older one")
  func newerWins() {
    let arming = StopArming()
    arming.arm(.tasks, for: "item_1", isPanelOpen: false, suppression: quiet)
    arming.arm(.proposals, for: "item_1", isPanelOpen: false, suppression: quiet)
    #expect(arming.pointerMoved(isPanelOpen: false, suppression: quiet) == .proposals)
  }
}
