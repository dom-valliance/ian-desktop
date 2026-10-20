import Contract
import Testing

@testable import Features

@Suite("Confirmation prompt announcement")
@MainActor
struct ConfirmAnnouncementTests {
  private func action(confirm: String?, input: Components.Schemas.ActionInput)
    -> Components.Schemas.ItemAction
  {
    Components.Schemas.ItemAction(
      id: "act_x", label: "Go", style: .primary, confirm: confirm, input: input)
  }

  @Test("speaks the confirm question when it replaces the buttons")
  func speaksTheQuestion() async {
    let flow = ItemActionFlow { _, _, _ in }
    await flow.choose(action(confirm: "Decline this?", input: .none))
    #expect(flow.prompt?.announcement == "Decline this?")
  }

  @Test("speaks nothing for a time or a note prompt, whose field names itself")
  func fieldsSpeakNothing() {
    #expect(ItemActionFlow.Prompt.note(action(confirm: nil, input: .note)).announcement == nil)
    #expect(ItemActionFlow.Prompt.until(action(confirm: nil, input: .until)).announcement == nil)
  }
}
