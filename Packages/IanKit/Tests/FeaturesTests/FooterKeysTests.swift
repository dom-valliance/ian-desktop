import Testing

@testable import Features

@Suite("Footer keys")
@MainActor
struct FooterKeysTests {
  private func keys(targets: Int) -> FooterKeys {
    let keys = FooterKeys()
    keys.setTargetCount(targets)
    return keys
  }

  @Test("Return enters the mode on the first target")
  func returnEnters() {
    let keys = keys(targets: 3)
    keys.pressReturn()
    #expect(keys.isActive)
    #expect(keys.highlighted == 0)
    #expect(keys.activations == 0)
  }

  @Test("Return does nothing when there is no target")
  func returnWithoutTargets() {
    let keys = keys(targets: 0)
    #expect(!keys.handlesReturn)
    keys.pressReturn()
    #expect(!keys.isActive)
  }

  @Test("Left and Right move the highlight in the order sent and wrap at both ends")
  func movesAndWraps() {
    let keys = keys(targets: 3)
    keys.pressReturn()
    keys.move(1)
    #expect(keys.highlighted == 1)
    keys.move(1)
    keys.move(1)
    #expect(keys.highlighted == 0)
    keys.move(-1)
    #expect(keys.highlighted == 2)
    keys.move(-1)
    #expect(keys.highlighted == 1)
  }

  @Test("the arrows do nothing outside the mode")
  func arrowsNeedTheMode() {
    let keys = keys(targets: 3)
    keys.move(1)
    #expect(keys.highlighted == 0)
    #expect(!keys.isActive)
  }

  @Test("a second Return acts on the highlighted target")
  func returnActs() {
    let keys = keys(targets: 3)
    keys.pressReturn()
    keys.move(1)
    keys.pressReturn()
    #expect(keys.activations == 1)
    #expect(keys.highlighted == 1)
    #expect(keys.isActive)
  }

  @Test("Escape returns to the row, and is not used outside the mode")
  func escapeReturns() {
    let keys = keys(targets: 2)
    #expect(!keys.pressEscape())
    keys.pressReturn()
    keys.move(1)
    #expect(keys.pressEscape())
    #expect(!keys.isActive)
    #expect(keys.highlighted == 0)
  }

  @Test("an open prompt keeps Return and Escape for itself")
  func promptOwnsTheKeys() {
    let keys = keys(targets: 2)
    keys.isPromptOpen = true
    keys.pressReturn()
    #expect(!keys.isActive)
    #expect(!keys.handlesReturn)
  }

  @Test("fewer targets clamp the highlight, and none leaves the mode")
  func targetsChange() {
    let keys = keys(targets: 4)
    keys.pressReturn()
    keys.move(-1)
    #expect(keys.highlighted == 3)
    keys.setTargetCount(2)
    #expect(keys.highlighted == 1)
    keys.setTargetCount(0)
    #expect(!keys.isActive)
  }
}
