import Client
import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

private typealias Schemas = Components.Schemas

private func action(
  _ id: String, label: String, style: Schemas.ActionStyle = .secondary, confirm: String? = nil,
  input: Schemas.ActionInput = .none
) -> Schemas.ItemAction {
  Schemas.ItemAction(id: id, label: label, style: style, confirm: confirm, input: input)
}

private func item(_ actions: [Schemas.ItemAction]) -> Schemas.Item {
  var item = Fixtures.item(id: "task_1")
  item.actions = actions
  return item
}

@Suite("Action component model")
struct ItemActionsModelTests {
  private let odd = [
    action("zz_first", label: "Alpha", style: .quiet),
    action("aa_second", label: "Zulu", style: .primary),
    action("mm_third", label: "Mike"),
  ]

  @Test("draws exactly the item's actions, in the order sent, with the ids and labels it sent")
  func drawsTheItemsActions() {
    let model = ItemActionsModel(
      item: item(odd), isPending: false, notice: nil, actionsEnabled: true)

    #expect(model.buttons.map(\.id) == ["zz_first", "aa_second", "mm_third"])
    #expect(model.buttons.map(\.label) == ["Alpha", "Zulu", "Mike"])
    #expect(model.buttons.map(\.style) == [.quiet, .primary, .secondary])
    #expect(model.buttons.allSatisfy { $0.isEnabled })
    #expect(model.status == nil)
  }

  @Test("draws no button for an item with no actions")
  func noActionsNoButtons() {
    let model = ItemActionsModel(
      item: item([]), isPending: false, notice: nil, actionsEnabled: true)
    #expect(model.buttons.isEmpty)
  }

  @Test("shows Pending and disables every button while the item is marked pending")
  func pendingDisablesButtons() {
    let model = ItemActionsModel(
      item: item(odd), isPending: true, notice: nil, actionsEnabled: true)

    #expect(model.status == .pending)
    #expect(model.status?.text == "Pending")
    #expect(model.buttons.count == 3)
    #expect(model.buttons.allSatisfy { !$0.isEnabled })
  }

  @Test("shows the error recorded on the item and keeps the buttons usable")
  func showsRecordedError() {
    let model = ItemActionsModel(
      item: item(odd), isPending: false, notice: .failed("Choose a later time."),
      actionsEnabled: true)

    #expect(model.status == ItemActionsModel.Status.failed("Choose a later time."))
    #expect(model.status?.text == "Choose a later time.")
    #expect(model.buttons.allSatisfy { $0.isEnabled })
  }

  @Test("shows the 409 notice as This item changed")
  func showsChangedNotice() {
    let model = ItemActionsModel(
      item: item(odd), isPending: false, notice: .changed, actionsEnabled: true)
    #expect(model.status?.text == "This item changed")
  }

  @Test("disables every button while offline and says why")
  func offlineDisablesButtons() {
    let model = ItemActionsModel(
      item: item(odd), isPending: false, notice: nil, actionsEnabled: false)

    #expect(model.status == .offline)
    #expect(model.buttons.allSatisfy { !$0.isEnabled })
  }

  @Test("puts the item's own notice before the offline line")
  func noticeBeforeOffline() {
    let model = ItemActionsModel(
      item: item(odd), isPending: false, notice: .changed, actionsEnabled: false)
    #expect(model.status == .changed)
  }
}

@Suite("Action component flow")
@MainActor
struct ItemActionFlowTests {
  private func flow(for itemID: String, store: IanStore) -> ItemActionFlow {
    ItemActionFlow { actionID, until, note in
      await store.run(actionID: actionID, on: itemID, until: until, note: note)
    }
  }

  private func scenarioAction(_ itemID: String, _ actionID: String) -> Schemas.ItemAction {
    TodayScenario.items.first { $0.id == itemID }!.actions.first { $0.id == actionID }!
  }

  @Test("sends an action with no question and no input at once, and marks the item pending")
  func sendsPlainAction() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "prop_a1", store: store)

    await flow.choose(scenarioAction("prop_a1", "act_yes"))

    #expect(flow.prompt == nil)
    #expect(service.actionCalls.map(\.actionID) == ["act_yes"])
    #expect(service.actionCalls.first?.until == nil)
    #expect(service.actionCalls.first?.note == nil)
    #expect(store.pending["prop_a1"]?.actionID == "act_yes")
    #expect(store.state.items["prop_a1"] != nil)
  }

  @Test("asks the confirm text first and sends only once it is confirmed")
  func asksToConfirmFirst() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "prop_a1", store: store)

    await flow.choose(scenarioAction("prop_a1", "act_no"))
    #expect(flow.prompt == .confirm(scenarioAction("prop_a1", "act_no")))
    #expect(flow.prompt?.action.confirm == "Decline this?")
    #expect(service.actionCalls.isEmpty)

    await flow.confirm()
    #expect(service.actionCalls.map(\.actionID) == ["act_no"])
  }

  @Test("sends nothing when the principal cancels")
  func cancelSendsNothing() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "prop_a1", store: store)

    await flow.choose(scenarioAction("prop_a1", "act_no"))
    flow.cancel()
    await flow.confirm()

    #expect(flow.prompt == nil)
    #expect(service.actionCalls.isEmpty)
  }

  @Test("asks for a time when the input is until, and sends the time and no note")
  func sendsUntilOnly() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "alrt_b1", store: store)
    let time = Date().addingTimeInterval(3600)

    await flow.choose(scenarioAction("alrt_b1", "act_later"))
    #expect(flow.prompt == .until(scenarioAction("alrt_b1", "act_later")))
    #expect(service.actionCalls.isEmpty)
    await flow.submit(until: time, note: "ignored")

    #expect(service.actionCalls.first?.until == time)
    #expect(service.actionCalls.first?.note == nil)
  }

  @Test("asks for a note when the input is note, and sends the note and no time")
  func sendsNoteOnly() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "cmt_a2", store: store)

    await flow.choose(scenarioAction("cmt_a2", "act_nudge"))
    #expect(flow.prompt == .note(scenarioAction("cmt_a2", "act_nudge")))
    await flow.submit(until: Date(timeIntervalSince1970: 1), note: "Any news?")

    #expect(service.actionCalls.first?.note == "Any news?")
    #expect(service.actionCalls.first?.until == nil)
  }

  @Test("asks the confirm text before the input when an action has both")
  func confirmThenInput() async {
    var both = scenarioAction("cmt_a2", "act_nudge")
    both.confirm = "Send a nudge?"
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "cmt_a2", store: store)

    await flow.choose(both)
    #expect(flow.prompt == .confirm(both))
    await flow.submit(until: nil, note: "too early")
    #expect(service.actionCalls.isEmpty)
    await flow.confirm()
    #expect(flow.prompt == .note(both))
    await flow.submit(until: nil, note: "Any news?")

    #expect(service.actionCalls.map(\.actionID) == ["act_nudge"])
  }

  @Test("shows the error the store recorded when the call fails")
  func showsFailure() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    service.planAction { _ in throw DesktopError.rejected(status: 400, detail: "Not allowed.") }
    let flow = flow(for: "prop_a1", store: store)

    await flow.choose(scenarioAction("prop_a1", "act_yes"))

    let model = ItemActionsModel(
      item: store.state.items["prop_a1"]!, isPending: store.pending["prop_a1"] != nil,
      notice: store.notices["prop_a1"], actionsEnabled: store.actionsEnabled)
    #expect(model.status == ItemActionsModel.Status.failed("Not allowed."))
    #expect(model.buttons.allSatisfy { $0.isEnabled })
  }

  @Test("shows the 409 notice and the newer item the store took from the problem body")
  func showsConflict() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    var newer = store.state.items["prop_a1"]!
    newer.version += 1
    newer.title = "Changed elsewhere"
    service.planAction { [newer] _ in throw DesktopError.conflict(item: newer) }
    let flow = flow(for: "prop_a1", store: store)

    await flow.choose(scenarioAction("prop_a1", "act_yes"))

    let model = ItemActionsModel(
      item: store.state.items["prop_a1"]!, isPending: false, notice: store.notices["prop_a1"],
      actionsEnabled: store.actionsEnabled)
    #expect(model.status?.text == "This item changed")
    #expect(store.state.items["prop_a1"]?.title == "Changed elsewhere")
  }

  @Test("refuses a time that has passed and keeps the prompt open")
  func refusesPastTime() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "alrt_b1", store: store)

    await flow.choose(scenarioAction("alrt_b1", "act_later"))
    #expect(!flow.canSubmit(until: Date().addingTimeInterval(-60), note: nil))
    await flow.submit(until: Date().addingTimeInterval(-60), note: nil)

    #expect(service.actionCalls.isEmpty)
    #expect(flow.prompt != nil)
    #expect(flow.canSubmit(until: Date().addingTimeInterval(3600), note: nil))
  }

  @Test("refuses a blank note and keeps the prompt open")
  func refusesBlankNote() async {
    let (store, service, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "cmt_a2", store: store)

    await flow.choose(scenarioAction("cmt_a2", "act_nudge"))
    await flow.submit(until: nil, note: "   ")

    #expect(service.actionCalls.isEmpty)
    #expect(flow.prompt != nil)
    #expect(!flow.canSubmit(until: nil, note: ""))
    #expect(flow.canSubmit(until: nil, note: "Any news?"))
  }

  @Test("cancels the prompt when the item stops offering its action")
  func cancelsWhenActionDisappears() async {
    let (store, _, _) = await TodayScenario.liveStore()
    defer { store.stop() }
    let flow = flow(for: "cmt_a2", store: store)
    await flow.choose(scenarioAction("cmt_a2", "act_nudge"))

    flow.cancelIfMissing(from: [TodayScenario.approve, TodayScenario.chase])
    #expect(flow.prompt != nil)
    flow.cancelIfMissing(from: [TodayScenario.approve])
    #expect(flow.prompt == nil)
  }

  @Test("says Connecting, not Offline, before the first connection")
  func connectingStatus() {
    let model = ItemActionsModel(
      item: item([action("a", label: "A")]), isPending: false, notice: nil,
      actionsEnabled: false, isConnecting: true)
    #expect(model.status?.text == "Connecting")
    #expect(model.buttons.allSatisfy { !$0.isEnabled })
  }

  @Test("disables the buttons and sends nothing while the stream is down")
  func offline() async {
    let (store, service, feed) = await TodayScenario.liveStore()
    defer { store.stop() }
    feed.finish()
    #expect(await eventually("offline") { await MainActor.run { store.connection == .offline } })

    let model = ItemActionsModel(
      item: store.state.items["prop_a1"]!, isPending: false, notice: nil,
      actionsEnabled: store.actionsEnabled)
    #expect(model.status == .offline)
    #expect(model.buttons.allSatisfy { !$0.isEnabled })
    await flow(for: "prop_a1", store: store).choose(scenarioAction("prop_a1", "act_yes"))
    #expect(service.actionCalls.isEmpty)
  }
}
