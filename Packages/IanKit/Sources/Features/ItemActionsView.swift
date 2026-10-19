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
  @State private var flow: ItemActionFlow
  @State private var until = Date().addingTimeInterval(3600)
  @State private var note = ""

  init(store: IanStore, item: Components.Schemas.Item) {
    self.store = store
    self.item = item
    let itemID = item.id
    _flow = State(
      initialValue: ItemActionFlow { actionID, until, note in
        await store.run(actionID: actionID, on: itemID, until: until, note: note)
      })
  }

  private var model: ItemActionsModel {
    ItemActionsModel(
      item: item, isPending: store.pending[item.id] != nil, notice: store.notices[item.id],
      actionsEnabled: store.actionsEnabled)
  }

  var body: some View {
    let model = model
    VStack(alignment: .trailing, spacing: 6) {
      if let prompt = flow.prompt {
        promptView(prompt)
      } else {
        HStack(spacing: 8) {
          ForEach(model.buttons) { button in
            Button(button.label) { Task { await flow.choose(button.action) } }
              .buttonStyle(ActionButtonStyle(style: button.style))
              .disabled(!button.isEnabled)
          }
        }
      }
      if let status = model.status { statusView(status) }
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
        Button(action.label) { Task { await flow.confirm() } }
          .buttonStyle(ActionButtonStyle(style: action.style))
      case .until:
        DatePicker(
          "Until", selection: $until, in: Date()..., displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        Button(action.label) { Task { await flow.submit(until: until, note: nil) } }
          .buttonStyle(ActionButtonStyle(style: action.style))
      case .note:
        TextField("Note", text: $note)
          .textFieldStyle(.roundedBorder)
          .frame(minWidth: 180, maxWidth: 280)
        Button(action.label) { Task { await flow.submit(until: nil, note: note) } }
          .buttonStyle(ActionButtonStyle(style: action.style))
      }
      Button("Cancel") { flow.cancel() }
        .buttonStyle(ActionButtonStyle(style: .quiet))
    }
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
    case .pending, .offline: false
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
