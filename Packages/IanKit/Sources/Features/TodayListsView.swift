import Store
import SwiftUI

/// The Now list, This week's rolled-up groups and Later's counts (spec 6.3). Every row is a
/// real button, and the list is the accessible path to every item the field shows.
struct TodayListsView: View {
  let list: TodayListModel
  let selection: TodaySelection?
  let onSelect: (TodaySelection) -> Void
  let onNavigate: (ClientSection) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if list.now.isEmpty && list.week.isEmpty && list.later.isEmpty {
        Text("Nothing is open.")
          .font(.system(size: 13))
          .foregroundStyle(ClientPalette.secondary(0.6))
          .padding(.horizontal, 8)
      }
      if !list.now.isEmpty {
        section("Now") {
          ForEach(list.now) { row in
            Button {
              onSelect(.item(row.id))
            } label: {
              RowContent(
                kindColour: ItemKindStyle.colour(row.kind), title: row.title, tag: "NOW",
                isSettled: row.isSettled)
            }
            .buttonStyle(ListRowButtonStyle(isSelected: selection == .item(row.id)))
            .accessibilityLabel(row.accessibilityLabel)
          }
        }
      }
      if !list.week.isEmpty {
        section("This week") {
          ForEach(list.week) { row in
            Button {
              onSelect(.week(unitID: row.unitID))
            } label: {
              RowContent(
                kindColour: row.kind.map(ItemKindStyle.colour) ?? ClientPalette.secondary(),
                title: row.unitName, tag: String(row.itemIDs.count), isSettled: false)
            }
            .buttonStyle(ListRowButtonStyle(isSelected: isSelected(row)))
            .accessibilityLabel(row.accessibilityLabel)
          }
        }
      }
      if !list.later.isEmpty {
        section("Later") {
          ForEach(list.later) { row in
            HStack(spacing: 6) {
              Button {
                onSelect(.later(unitID: row.unitID))
              } label: {
                RowContent(
                  kindColour: row.kind.map(ItemKindStyle.colour) ?? ClientPalette.secondary(),
                  title: row.unitName, tag: nil, isSettled: false)
              }
              .buttonStyle(ListRowButtonStyle(isSelected: selection == .later(unitID: row.unitID)))
              .accessibilityLabel(row.accessibilityLabel)
              ForEach(row.counts, id: \.kind) { count in
                Button {
                  onNavigate(count.section)
                } label: {
                  Text(count.phrase.uppercased())
                    .font(ClientPalette.label)
                    .tracking(ClientPalette.labelTracking)
                    .foregroundStyle(ClientPalette.secondary(0.8))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(count.phrase), open \(count.section.title)")
              }
            }
          }
        }
      }
    }
    .padding(.vertical, 10)
  }

  /// A week group is selected when it is, or when an item inside it is.
  private func isSelected(_ row: TodayListModel.WeekRow) -> Bool {
    switch selection {
    case .week(let unitID): unitID == row.unitID
    case .item(let id): row.itemIDs.contains(id)
    case .later, nil: false
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder rows: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased())
        .font(ClientPalette.label)
        .tracking(ClientPalette.labelTracking)
        .foregroundStyle(ClientPalette.secondary(0.6))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
      rows()
    }
  }
}

/// A 10-point colour square with radius 2, the title at 13 points truncated, and a monospaced
/// 11-point tag. A settled row dims until it leaves.
private struct RowContent: View {
  let kindColour: Color
  let title: String
  let tag: String?
  let isSettled: Bool

  var body: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 2)
        .fill(kindColour)
        .frame(width: 10, height: 10)
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
