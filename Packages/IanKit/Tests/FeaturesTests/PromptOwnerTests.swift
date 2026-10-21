import Contract
import Testing

@testable import Features

@Suite("One open prompt")
@MainActor
struct PromptOwnerTests {
  private let note = Components.Schemas.ItemAction(
    id: "act_note", label: "Send", style: .primary, confirm: nil, input: .note)

  private final class Sent {
    var ids: [String] = []
  }

  private func flow(_ sent: Sent, _ name: String) -> ItemActionFlow {
    ItemActionFlow { id, _, _ in sent.ids.append("\(name):\(id)") }
  }

  @Test("opening a second prompt closes the first")
  func secondClosesFirst() async {
    let owner = PromptOwner()
    let sent = Sent()
    let a = flow(sent, "a")
    let b = flow(sent, "b")
    await a.choose(note)
    owner.opened("action:a") { a.cancel() }
    await b.choose(note)
    owner.opened("action:b") { b.cancel() }

    #expect(a.prompt == nil)
    #expect(b.prompt != nil)
    #expect(owner.openKey == "action:b")
  }

  @Test("Return acts only on the prompt that is open")
  func returnActsOnTheOpenPrompt() async {
    let owner = PromptOwner()
    let sent = Sent()
    let a = flow(sent, "a")
    let b = flow(sent, "b")
    await a.choose(note)
    owner.opened("action:a") { a.cancel() }
    await b.choose(note)
    owner.opened("action:b") { b.cancel() }

    await a.submit(until: nil, note: "for a")
    await b.submit(until: nil, note: "for b")

    #expect(sent.ids == ["b:act_note"])
  }

  @Test("a prompt that closes on its own leaves nothing open, and a stale close changes nothing")
  func closingOnItsOwn() async {
    let owner = PromptOwner()
    owner.opened("handoff:a") {}
    owner.opened("action:b") {}
    owner.closed("handoff:a")
    #expect(owner.openKey == "action:b")
    owner.closed("action:b")
    #expect(owner.openKey == nil)
  }
}
