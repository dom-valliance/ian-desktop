import Contract
import Store
import TestSupport
import Testing

@testable import Attention

private func item(
  actions: [Fixtures.ActionSpec] = [Fixtures.ActionSpec("approve")]
) -> StoreState.Item {
  Fixtures.item(
    id: "task_9", title: "Reply to [PERSON] about [CLIENT]", actions: actions,
    attention: "urgent", meta: "[CLIENT] steering group")
}

@Suite("Notification content")
struct NotificationContentTests {
  @Test("shows the item's title and meta when text may be shown")
  func showsText() {
    let content = NotificationContent(item: item(), rung: .urgent, showsItemText: true)
    #expect(content.id == "task_9")
    #expect(content.title == "Reply to [PERSON] about [CLIENT]")
    #expect(content.body == "[CLIENT] steering group")
  }

  @Test("carries no item text while suppressed")
  func hidesText() {
    let source = item(actions: [
      Fixtures.ActionSpec("approve"), Fixtures.ActionSpec("snooze", input: "until"),
    ])
    let content = NotificationContent(item: source, rung: .stop, showsItemText: false)
    let everything =
      [content.title, content.body, content.category.id]
      + content.category.buttons.flatMap { [$0.identifier, $0.title] }
    for text in everything {
      #expect(!text.contains("[PERSON]"))
      #expect(!text.contains("[CLIENT]"))
      #expect(!text.contains("Approve"))
    }
    #expect(content.title == "Ian")
    #expect(content.body == NotificationContent.suppressedBody)
  }

  @Test("only stop plays a sound")
  func sound() {
    for rung in NotificationRung.allCases {
      let content = NotificationContent(item: item(), rung: rung, showsItemText: true)
      #expect(content.playsSound == (rung == .stop))
    }
  }

  @Test("buttons are the actions with no confirm and no input, in order, then Open")
  func quickActions() {
    let source = item(actions: [
      Fixtures.ActionSpec("approve"),
      Fixtures.ActionSpec("reject", confirm: "Reject this?"),
      Fixtures.ActionSpec("snooze", input: "until"),
      Fixtures.ActionSpec("comment", input: "note"),
      Fixtures.ActionSpec("later"),
    ])
    let category = NotificationCategory(item: source, showsItemText: true)
    #expect(category.buttons.map(\.title) == ["Approve", "Later", "Open"])
    #expect(
      category.buttons.map { NotificationButton.actionID(forIdentifier: $0.identifier) } == [
        "approve", "later", nil,
      ])
    #expect(category.id == "ian.item.task_9.1")
  }

  @Test("only Open is offered while suppressed")
  func suppressedButtons() {
    let category = NotificationCategory(item: item(), showsItemText: false)
    #expect(category.buttons.map(\.title) == ["Open"])
    #expect(category.buttons.map(\.identifier) == [NotificationButton.openIdentifier])
    #expect(category.id == "ian.item.open")
  }

  @Test("an item with no quick action offers only Open, under its own category")
  func noQuickActions() {
    let source = item(actions: [Fixtures.ActionSpec("reject", confirm: "Sure?")])
    let category = NotificationCategory(item: source, showsItemText: true)
    #expect(category.buttons.map(\.title) == ["Open"])
    #expect(category.id == "ian.item.task_9.1")
  }

  @Test("two items with the same action id get different categories")
  func categoriesPerItem() {
    let first = Fixtures.item(id: "commitment_1", actions: [Fixtures.ActionSpec("settle")])
    let second = Fixtures.item(id: "commitment_2", actions: [Fixtures.ActionSpec("settle")])
    #expect(
      NotificationCategory(item: first, showsItemText: true).id
        != NotificationCategory(item: second, showsItemText: true).id)
  }

  @Test("each item kind opens the view that holds it")
  func destinations() {
    var source = item()
    #expect(ItemDestination(item: source) == .tasks)
    source.kind = .alert
    #expect(ItemDestination(item: source) == .alerts)
    source.kind = .proposal
    #expect(ItemDestination(item: source) == .proposals)
    source.kind = .commitmentBy
    #expect(ItemDestination(item: source) == .commitments)
    source.kind = .commitmentTo
    #expect(ItemDestination(item: source) == .commitments)
  }

  @Test("the rung is the server's, mapped as sent")
  func rungMapping() {
    for (sent, rung) in [
      ("ambient", NotificationRung.ambient), ("needs_you", .needsYou), ("urgent", .urgent),
      ("stop", .stop),
    ] {
      #expect(NotificationRung(item: Fixtures.item(attention: sent)) == rung)
    }
  }
}
