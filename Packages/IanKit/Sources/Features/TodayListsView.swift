import Contract
import SwiftUI

/// The Now list, This week's rolled-up groups and Later's counts (spec 6.3), as one sectioned
/// list bound to the selection, so the arrow keys move through it without any system keyboard
/// setting. The list is the accessible path to every item the field shows.
struct TodayListsView: View {
  let list: TodayListModel
  /// Whether Today has loaded, so an empty list can say that nothing is open.
  let hasToday: Bool
  @Binding var selection: TodaySelection?

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: highlighted) {
        if hasToday && list.now.isEmpty && list.week.isEmpty && list.later.isEmpty {
          Text("Nothing is open.")
            .font(.system(size: 13))
            .foregroundStyle(ClientPalette.secondary(0.6))
            .selectionDisabled()
        }
        if !list.now.isEmpty {
          Section {
            ForEach(list.now) { row in
              RowContent(
                kind: row.kind, title: row.title, tag: "NOW", isSettled: row.isSettled
              )
              .accessibilityLabel(row.accessibilityLabel)
              .tag(TodaySelection.item(row.id))
              .id(TodaySelection.item(row.id))
            }
          } header: {
            header("Now")
          }
        }
        if !list.week.isEmpty {
          Section {
            ForEach(list.week) { row in
              RowContent(
                kind: row.kind, title: row.unitName, tag: String(row.itemIDs.count),
                isSettled: false
              )
              .accessibilityLabel(row.accessibilityLabel)
              .tag(TodaySelection.week(unitID: row.unitID))
              .id(TodaySelection.week(unitID: row.unitID))
            }
          } header: {
            header("This week")
          }
        }
        if !list.later.isEmpty {
          Section {
            ForEach(list.later) { row in
              RowContent(kind: row.kind, title: row.unitName, tag: nil, isSettled: false)
                .accessibilityLabel(row.accessibilityLabel)
                .tag(TodaySelection.later(unitID: row.unitID))
                .id(TodaySelection.later(unitID: row.unitID))
            }
          } header: {
            header("Later")
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .environment(\.defaultMinListRowHeight, 36)
      .onChange(of: highlighted.wrappedValue) { _, new in
        if let new { proxy.scrollTo(new) }
      }
    }
  }

  /// A week group is highlighted when it is selected or when an item inside it is.
  private var highlighted: Binding<TodaySelection?> {
    Binding(
      get: {
        guard case .item(let id) = selection,
          let group = list.week.first(where: { $0.itemIDs.contains(id) })
        else { return selection }
        return list.now.contains { $0.id == id } ? selection : .week(unitID: group.unitID)
      },
      set: { selection = $0 })
  }

  private func header(_ title: String) -> some View {
    Text(title.uppercased())
      .font(ClientPalette.label)
      .tracking(ClientPalette.labelTracking)
      .foregroundStyle(ClientPalette.secondary(0.6))
      .accessibilityAddTraits(.isHeader)
  }
}

/// A kind swatch, the title at 13 points truncated, and a monospaced 11-point tag. A settled row
/// dims until it leaves.
private struct RowContent: View {
  let kind: Components.Schemas.ItemKind?
  let title: String
  let tag: String?
  let isSettled: Bool

  var body: some View {
    HStack(spacing: 10) {
      KindSwatch(kind: kind)
      Text(title)
        .font(.system(size: 13))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let tag {
        Text(tag)
          .font(ClientPalette.label)
          .foregroundStyle(ClientPalette.secondary(0.6))
      }
    }
    .frame(minHeight: 28)
    .opacity(isSettled ? 0.35 : 1)
  }
}

/// A selected row has a fill of white at 0.08 and a border of white at 0.3.
struct ListRowButtonStyle: ButtonStyle {
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(minHeight: 36)
      .foregroundStyle(ClientPalette.text)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isSelected || configuration.isPressed ? Color.white.opacity(0.08) : .clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isSelected ? Color.white.opacity(0.3) : .clear, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
