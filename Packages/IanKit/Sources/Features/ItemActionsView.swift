import Contract
import Store
import SwiftUI

/// The one action component every view uses (spec 6.3, D5 and D6). It draws the item's
/// `actions` in the order sent, asks a `confirm` question, a time or a note when the action
/// says so, and calls the store. It shows "Pending" while the server has not settled the item,
/// the error or the `409` notice the store recorded, and it is disabled while offline.
struct ItemActionsView: View {
  private let store: IanStore
  private let item: Components.Schemas.Item
  /// Today's footer passes its keyboard path, so Return can run the highlighted action here.
  private let keys: FooterKeys?
  @State private var flow: ItemActionFlow
  @State private var until = Date().addingTimeInterval(3600)
  @State private var note = ""
  @FocusState private var focus: PromptFocus?
  @Environment(\.promptOwner) private var promptOwner

  /// The control that takes focus when a prompt opens, so the keyboard can answer it at once.
  private enum PromptFocus: Hashable { case confirm, until, note }

  init(store: IanStore, item: Components.Schemas.Item, keys: FooterKeys? = nil) {
    self.store = store
    self.item = item
    self.keys = keys
    let itemID = item.id
    _flow = State(
      initialValue: ItemActionFlow { actionID, until, note in
        await store.run(actionID: actionID, on: itemID, until: until, note: note)
      })
  }

  private var model: ItemActionsModel {
    ItemActionsModel(
      item: item, isPending: store.pending[item.id] != nil, notice: store.notices[item.id],
      actionsEnabled: store.actionsEnabled,
      isConnecting: store.connection == .connecting)
  }

  /// Return in Today's action mode: runs the highlighted action as a click would, so its confirm,
  /// time or note prompt opens and takes focus, then leaves the mode.
  private func runHighlighted() {
    guard let keys, keys.isActive else { return }
    let buttons = model.buttons
    if buttons.indices.contains(keys.highlighted), buttons[keys.highlighted].isEnabled {
      let action = buttons[keys.highlighted].action
      Task { await flow.choose(action) }
    }
    keys.exit()
  }

  private var promptKey: String { "action:\(item.id)" }

  private var canAct: Bool { store.actionsEnabled && store.pending[item.id] == nil }

  var body: some View {
    let model = model
    VStack(alignment: .trailing, spacing: 6) {
      if let prompt = flow.prompt {
        promptView(prompt)
      } else {
        HStack(spacing: 8) {
          ForEach(Array(model.buttons.enumerated()), id: \.element.id) { index, button in
            Button(button.label) { Task { await flow.choose(button.action) } }
              .buttonStyle(ActionButtonStyle(style: button.style))
              .disabled(!button.isEnabled)
              .keyboardHighlight(keys?.isActive == true && keys?.highlighted == index)
          }
        }
      }
      if let status = model.status { statusView(status) }
    }
    .onChange(of: item.actions) { _, actions in flow.cancelIfMissing(from: actions) }
    .onDisappear { promptOwner?.closed(promptKey) }
    .onChange(of: model.buttons.count, initial: true) { _, count in keys?.setTargetCount(count) }
    .onChange(of: keys?.activations) { runHighlighted() }
    .onChange(of: flow.prompt) { old, prompt in
      keys?.isPromptOpen = prompt != nil
      if prompt == nil {
        promptOwner?.closed(promptKey)
      } else if old == nil {
        promptOwner?.opened(promptKey) { [flow] in flow.cancel() }
      }
      if let text = prompt?.announcement { AccessibilityNotification.Announcement(text).post() }
      switch prompt {
      case .confirm: focus = .confirm
      case .until:
        until = Date().addingTimeInterval(3600)
        focus = .until
      case .note:
        note = ""
        focus = .note
      case nil: focus = nil
      }
    }
  }

  @ViewBuilder private func promptView(_ prompt: ItemActionFlow.Prompt) -> some View {
    let action = prompt.action
    HStack(spacing: 8) {
      switch prompt {
      case .confirm:
        Text(action.confirm ?? "")
          .font(.system(size: 13))
          .foregroundStyle(ClientPalette.secondary())
        sendButton(action, isReady: true) { await flow.confirm() }
          .focused($focus, equals: .confirm)
      case .until:
        DatePicker(
          "Until", selection: $until, in: Date()..., displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .focused($focus, equals: .until)
        sendButton(action, isReady: flow.canSubmit(until: until, note: nil)) {
          await flow.submit(until: until, note: nil)
        }
      case .note:
        TextField("Note", text: $note)
          .textFieldStyle(.roundedBorder)
          .frame(minWidth: 180, maxWidth: 280)
          .focused($focus, equals: .note)
        sendButton(action, isReady: flow.canSubmit(until: nil, note: note)) {
          await flow.submit(until: nil, note: note)
        }
      }
      Button("Cancel") { flow.cancel() }
        .buttonStyle(ActionButtonStyle(style: .quiet))
        .keyboardShortcut(.cancelAction)
    }
  }

  /// Return sends. It is off while offline, while the item is pending, and until the answer is
  /// one the prompt accepts.
  private func sendButton(
    _ action: Components.Schemas.ItemAction, isReady: Bool,
    send: @escaping () async -> Void
  ) -> some View {
    Button(action.label) { Task { await send() } }
      .buttonStyle(ActionButtonStyle(style: action.style))
      .keyboardShortcut(.defaultAction)
      .disabled(!canAct || !isReady)
  }

  @ViewBuilder private func statusView(_ status: ItemActionsModel.Status) -> some View {
    HStack(spacing: 8) {
      Text(status.text)
        .font(.system(size: 13))
        .foregroundStyle(
          status.isProblem ? ItemKindStyle.colour(.alert) : ClientPalette.secondary()
        )
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
      if status.isDismissible {
        Button("Dismiss") { store.dismissNotice(for: item.id) }
          .buttonStyle(ActionButtonStyle(style: .quiet))
      }
    }
    .accessibilityElement(children: .combine)
  }
}

extension ItemActionsModel.Status {
  var isProblem: Bool {
    switch self {
    case .failed, .changed: true
    case .pending, .offline, .connecting: false
    }
  }

  /// A notice stays until the principal dismisses it or acts again.
  var isDismissible: Bool { isProblem }
}

/// Primary is filled, secondary is outlined and quiet is plain; at least 36 points tall with a
/// 6 point radius (design README, selection footer).
struct ActionButtonStyle: ButtonStyle {
  let style: Components.Schemas.ActionStyle
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .frame(minHeight: 36)
      .foregroundStyle(foreground)
      .background(RoundedRectangle(cornerRadius: 6).fill(fill))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(stroke, lineWidth: 1))
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: 6))
  }

  private var foreground: Color {
    style == .primary ? ClientPalette.ground : ClientPalette.text
  }

  private var fill: Color {
    style == .primary ? ClientPalette.text : .clear
  }

  private var stroke: Color {
    style == .secondary ? Color.white.opacity(0.2) : .clear
  }
}

extension View {
  /// The ring the keyboard path draws round the target Return would act on. It is visual only.
  func keyboardHighlight(_ isOn: Bool) -> some View {
    overlay {
      if isOn {
        RoundedRectangle(cornerRadius: 8).stroke(ClientPalette.text, lineWidth: 2).padding(-3)
      }
    }
  }
}
