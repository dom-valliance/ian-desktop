import Contract
import Foundation
import Observation
import Store

/// What the action component draws for one item: the item's own actions in the order sent, and
/// the one line of status under them. It never hard-codes an action id or label (ADR 0001).
struct ItemActionsModel: Equatable {
  struct Button: Equatable, Identifiable {
    let action: Components.Schemas.ItemAction
    let isEnabled: Bool

    var id: String { action.id }
    var label: String { action.label }
    var style: Components.Schemas.ActionStyle { action.style }
  }

  enum Status: Equatable {
    /// Sent, and the server has not yet answered with an event.
    case pending
    /// The server refused or the call failed; the reason it gave.
    case failed(String)
    /// The `409` notice: the item changed before the action arrived.
    case changed
    case offline
    /// The first snapshot or stream is not in yet.
    case connecting

    var text: String {
      switch self {
      case .pending: "Pending"
      case .failed(let message): message
      case .changed: "This item changed"
      case .offline: "Offline. Actions are paused."
      case .connecting: "Connecting"
      }
    }
  }

  let buttons: [Button]
  let status: Status?

  init(
    item: Components.Schemas.Item, isPending: Bool, notice: IanStore.Notice?,
    actionsEnabled: Bool, isConnecting: Bool = false
  ) {
    let isEnabled = !isPending && actionsEnabled
    buttons = item.actions.map { Button(action: $0, isEnabled: isEnabled) }
    switch (isPending, notice) {
    case (true, _): status = .pending
    case (false, .failed(let message)?): status = .failed(message)
    case (false, .changed?): status = .changed
    case (false, nil):
      status = actionsEnabled ? nil : (isConnecting ? .connecting : .offline)
    }
  }
}

/// The steps between a click on an action and the call: the `confirm` question first when the
/// action has one, then a time or a note when its `input` asks for one, then the call. Which
/// steps happen comes from the action's fields, never from its id or label.
@MainActor
@Observable
final class ItemActionFlow {
  enum Prompt: Equatable {
    case confirm(Components.Schemas.ItemAction)
    case until(Components.Schemas.ItemAction)
    case note(Components.Schemas.ItemAction)

    var action: Components.Schemas.ItemAction {
      switch self {
      case .confirm(let action), .until(let action), .note(let action): action
      }
    }

    /// What VoiceOver is told when the prompt replaces the buttons: the `confirm` question, so
    /// the cursor is never left on a button that has gone. A time or note field takes focus
    /// and names itself.
    var announcement: String? {
      guard case .confirm(let action) = self else { return nil }
      return action.confirm
    }
  }

  private(set) var prompt: Prompt?
  /// Sends the action: its id, then the time and the note.
  @ObservationIgnored private let send: @MainActor (String, Date?, String?) async -> Void

  init(send: @escaping @MainActor (String, Date?, String?) async -> Void) {
    self.send = send
  }

  /// The principal chose an action.
  func choose(_ action: Components.Schemas.ItemAction) async {
    if action.confirm != nil {
      prompt = .confirm(action)
    } else {
      await advance(action)
    }
  }

  /// The principal said yes to the `confirm` question.
  func confirm() async {
    guard case .confirm(let action) = prompt else { return }
    await advance(action)
  }

  /// Whether what the principal gave answers the prompt: a time that has not passed, or a note
  /// with something in it. A confirm prompt has nothing to send yet.
  func canSubmit(until: Date?, note: String?, at date: Date = Date()) -> Bool {
    switch prompt {
    case .until: (until ?? .distantPast) > date
    case .note: !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .confirm, nil: false
    }
  }

  /// The principal gave the time or the note the action asked for. The one the action's `input`
  /// does not ask for is dropped, and an answer that `canSubmit` refuses is not sent.
  func submit(until: Date?, note: String?) async {
    guard canSubmit(until: until, note: note) else { return }
    switch prompt {
    case .until(let action), .note(let action):
      prompt = nil
      await send(
        action.id, action.input == .until ? until : nil, action.input == .note ? note : nil)
    case .confirm, nil:
      return
    }
  }

  /// Drops the prompt when the item no longer offers its action.
  func cancelIfMissing(from actions: [Components.Schemas.ItemAction]) {
    guard let action = prompt?.action, !actions.contains(where: { $0.id == action.id }) else {
      return
    }
    prompt = nil
  }

  func cancel() {
    prompt = nil
  }

  private func advance(_ action: Components.Schemas.ItemAction) async {
    switch action.input {
    case .none:
      prompt = nil
      await send(action.id, nil, nil)
    case .until:
      prompt = .until(action)
    case .note:
      prompt = .note(action)
    }
  }
}
