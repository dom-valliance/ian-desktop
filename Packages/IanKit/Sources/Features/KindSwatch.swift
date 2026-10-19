import Contract
import SwiftUI

/// The 10-point square with radius 2 that marks an item's kind in a row. An alert also carries
/// the light rim the design gives it, so urgency is never carried by colour alone (spec 6.8).
/// Rows and the footer's group members share it.
struct KindSwatch: View {
  let kind: Components.Schemas.ItemKind?

  var body: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(kind.map(ItemKindStyle.colour) ?? ClientPalette.secondary())
      .overlay {
        if kind == .alert {
          RoundedRectangle(cornerRadius: 2).strokeBorder(ClientPalette.text, lineWidth: 1.5)
        }
      }
      .frame(width: 10, height: 10)
  }
}
