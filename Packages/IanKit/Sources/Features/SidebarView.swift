import Contract
import SwiftUI

/// The seven views with the counts the server sent in `views.counts` (spec 6.2). A list, so the
/// arrow keys move through it and VoiceOver reads each row with its count.
struct SidebarView: View {
  let counts: Components.Schemas.ViewCounts?
  let width: Double
  @Binding var selection: ClientSection

  var body: some View {
    List(
      ClientSection.allCases,
      selection: Binding<ClientSection?>(
        get: { selection }, set: { if let section = $0 { selection = section } })
    ) { section in
      HStack {
        Text(section.title)
          .font(.system(size: 13))
        Spacer(minLength: 8)
        if let count = section.count(in: counts) {
          Text(String(count))
            .font(ClientPalette.label)
            .foregroundStyle(ClientPalette.secondary(0.6))
        }
      }
      .frame(minHeight: 28)
      .padding(.horizontal, 6)
      .listRowSeparator(.hidden)
      .tag(section)
      .accessibilityElement(children: .combine)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .frame(width: width)
    .accessibilityLabel("Views")
  }
}
