import Contract
import Store
import SwiftUI

extension ClientPalette {
  /// The card fill, grey-900 (design README, Colour).
  static let card = rgb(0x24, 0x24, 0x24)
}

/// A card for one item in Proposals, Commitments, Tasks or Alerts (the Context artboard): the
/// kind, title and meta line, the fields of its kind, links to Lance and the source, "Hand to
/// Ian" when the server offers it, and the item's own actions through the shared component.
struct ItemCardView: View {
  let store: IanStore
  let item: Components.Schemas.Item

  @Environment(\.openURL) private var openURL
  @State private var isHandingOff = false
  @State private var instruction = ""
  @FocusState private var instructionFocused: Bool

  private var model: ItemCardModel {
    ItemCardModel(
      item: item, statuses: ItemStatuses(store: store), actionsEnabled: store.actionsEnabled,
      isConnecting: store.connection == .connecting, handoffOffered: store.offersHandoff)
  }

  private var isUrgentAlert: Bool { item.kind == .alert && item.severity == .p0 }

  var body: some View {
    let model = model
    VStack(alignment: .leading, spacing: 10) {
      header(model)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.title)
          .font(.system(size: 15, weight: .medium))
        Text(model.meta)
          .font(.system(size: 13))
          .foregroundStyle(ClientPalette.secondary())
      }
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
          lineView(line)
        }
      }
      footer(model)
      if isHandingOff { handoffField }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10).fill(ClientPalette.card))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(
          isUrgentAlert ? ItemKindStyle.colour(.alert).opacity(0.6) : ClientPalette.line,
          lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(model.accessibilityLabel)
  }

  private func header(_ model: ItemCardModel) -> some View {
    HStack(spacing: 8) {
      KindSwatch(kind: model.kind)
      Text(model.kicker.uppercased())
        .font(ClientPalette.label)
        .tracking(ClientPalette.labelTracking)
        .foregroundStyle(ClientPalette.secondary(0.7))
      if let badge = model.badge {
        Text(badge.uppercased())
          .font(ClientPalette.label)
          .tracking(ClientPalette.labelTracking)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
      }
      if item.working {
        Text("Ian is working on this")
          .font(.system(size: 12))
          .foregroundStyle(ClientPalette.secondary(0.7))
      }
    }
  }

  @ViewBuilder private func lineView(_ line: ItemCardModel.Line) -> some View {
    switch line.role {
    case .primary:
      Text(line.text).font(.system(size: 13))
    case .secondary:
      Text(line.text)
        .font(.system(size: 13))
        .foregroundStyle(ClientPalette.secondary())
    case .quote:
      Text(line.text)
        .font(.system(size: 13).italic())
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.white.opacity(0.2)).frame(width: 2)
        }
    }
  }

  private func footer(_ model: ItemCardModel) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 8) {
        links(model)
        Spacer(minLength: 12)
        controls(model)
      }
      VStack(alignment: .leading, spacing: 8) {
        links(model)
        controls(model)
      }
    }
  }

  private func links(_ model: ItemCardModel) -> some View {
    HStack(spacing: 4) {
      if let url = model.lanceURL {
        Button("Open in Lance") { openURL(url) }
          .buttonStyle(ActionButtonStyle(style: .quiet))
      }
      if let url = model.sourceURL {
        Button("Open in source") { openURL(url) }
          .buttonStyle(ActionButtonStyle(style: .quiet))
      }
    }
  }

  private func controls(_ model: ItemCardModel) -> some View {
    HStack(alignment: .top, spacing: 8) {
      if model.showsHandoff {
        Button("Hand to Ian") { isHandingOff.toggle() }
          .buttonStyle(ActionButtonStyle(style: .secondary))
          .disabled(!store.actionsEnabled || store.pending[item.id] != nil)
          .accessibilityLabel("Hand to Ian, \(item.title)")
      }
      ItemActionsView(store: store, item: item)
    }
  }

  private var handoffField: some View {
    let isTooLong = instruction.count > IanStore.handoffInstructionLimit
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        TextField("Instruction for Ian (optional)", text: $instruction)
          .textFieldStyle(.roundedBorder)
          .focused($instructionFocused)
          .onSubmit(sendHandoff)
        Button("Send", action: sendHandoff)
          .buttonStyle(ActionButtonStyle(style: .primary))
          .keyboardShortcut(.defaultAction)
          .disabled(isTooLong || !store.actionsEnabled)
        Button("Cancel", action: closeHandoff)
          .buttonStyle(ActionButtonStyle(style: .quiet))
          .keyboardShortcut(.cancelAction)
      }
      if isTooLong {
        Text("Shorten the instruction to \(IanStore.handoffInstructionLimit) characters or fewer.")
          .font(.system(size: 13))
          .foregroundStyle(ItemKindStyle.colour(.alert))
      }
    }
    .onAppear { instructionFocused = true }
  }

  private func sendHandoff() {
    guard instruction.count <= IanStore.handoffInstructionLimit else { return }
    let text = instruction
    closeHandoff()
    Task { await store.handOff(itemID: item.id, instruction: text) }
  }

  private func closeHandoff() {
    isHandingOff = false
    instruction = ""
  }
}
