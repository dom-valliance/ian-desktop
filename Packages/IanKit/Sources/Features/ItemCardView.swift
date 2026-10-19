import Contract
import Store
import SwiftUI

extension ClientPalette {
  /// The card fill, grey-900 (design README, Colour).
  static let card = rgb(0x24, 0x24, 0x24)
}

/// A card for one item in Proposals, Commitments, Tasks or Alerts (the Context artboard): the
/// kind, title and meta line, the fields of its kind, links to Lance and the source, "Hand to
/// Ian" when the server offers it, and the item's own actions through the shared component. An
/// item the server has just removed is dimmed and shows the server's outcome line instead.
struct ItemCardView: View {
  let store: IanStore
  let entry: ListedItem

  private var item: Components.Schemas.Item { entry.item }

  @Environment(\.openURL) private var openURL
  @State private var isHandingOff = false
  @State private var instruction = ""
  @FocusState private var instructionFocused: Bool

  private var model: ItemCardModel {
    ItemCardModel(
      item: item, statuses: ItemStatuses(store: store), removal: entry.removal,
      timeZone: CardDate.timeZone(for: store.state.me))
  }

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
      if let settlement = model.settlement {
        Text(settlement)
          .font(.system(size: 13))
          .foregroundStyle(ClientPalette.resolved)
      } else {
        footer(model)
        if isHandingOff { handoffField }
      }
    }
    .opacity(model.settlement == nil ? 1 : 0.35)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10).fill(ClientPalette.card))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(
          model.isUrgent ? ItemKindStyle.colour(.alert).opacity(0.6) : ClientPalette.line,
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

  /// Links on one row and the controls on the next, so the action component is created once
  /// and keeps its prompt and field state whatever the card's width.
  private func footer(_ model: ItemCardModel) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      links(model)
      HStack(alignment: .top, spacing: 8) {
        Spacer(minLength: 0)
        controls
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
    // A quiet button keeps its 14 points of side padding as hit area; pulling the row back by
    // that much lines the first link's text up with the card's.
    .padding(.leading, -14)
  }

  private var controls: some View {
    HStack(alignment: .top, spacing: 8) {
      if store.offersHandoff {
        Button("Hand to Ian") { isHandingOff.toggle() }
          .buttonStyle(HandoffButtonStyle())
          .disabled(!store.actionsEnabled || store.pending[item.id] != nil)
          .accessibilityLabel("Hand to Ian, \(item.title)")
      }
      ItemActionsView(store: store, item: item)
    }
  }

  private var handoffField: some View {
    let isTooLong = !IanStore.instructionFits(instruction)
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        TextField("Instruction for Ian (optional)", text: $instruction)
          .textFieldStyle(.roundedBorder)
          .focused($instructionFocused)
        Button("Send", action: sendHandoff)
          .buttonStyle(ActionButtonStyle(style: .primary))
          .keyboardShortcut(.defaultAction)
          .disabled(isTooLong || !store.actionsEnabled || store.pending[item.id] != nil)
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
    guard IanStore.instructionFits(instruction) else { return }
    let text = instruction
    closeHandoff()
    Task { await store.handOff(itemID: item.id, instruction: text) }
  }

  private func closeHandoff() {
    isHandingOff = false
    instruction = ""
  }
}

/// "Hand to Ian": outline `rgba(176,193,227,0.45)` and text `#C7D3EB`, at least 36 points tall
/// with radius 6, like the action buttons (design README, selection footer).
struct HandoffButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .frame(minHeight: 36)
      .foregroundStyle(ClientPalette.rgb(0xC7, 0xD3, 0xEB))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(ClientPalette.rgb(176, 193, 227).opacity(0.45), lineWidth: 1)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: 6))
  }
}
