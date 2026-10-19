import Contract
import SwiftUI

/// How an item's kind and horizon are named and coloured. These are the design's own words and
/// colours (design README, Colour); the server decides which kind an item is.
enum ItemKindStyle {
  typealias Kind = Components.Schemas.ItemKind

  /// The kind in words, as VoiceOver reads it and the footer's first line shows it.
  static func name(_ kind: Kind) -> String {
    switch kind {
    case .proposal: "Proposal"
    case .commitmentBy: "Owed by you"
    case .commitmentTo: "Owed to you"
    case .task: "Task"
    case .alert: "Alert"
    }
  }

  /// "3 tasks", "1 proposal": a count and the kind it counts.
  static func phrase(_ kind: Kind, count: Int) -> String {
    let noun: String
    switch kind {
    case .proposal: noun = count == 1 ? "proposal" : "proposals"
    case .commitmentBy: noun = "owed by you"
    case .commitmentTo: noun = "owed to you"
    case .task: noun = count == 1 ? "task" : "tasks"
    case .alert: noun = count == 1 ? "alert" : "alerts"
    }
    return "\(count) \(noun)"
  }

  /// The view that holds items of this kind, which a Later count links to.
  static func section(for kind: Kind) -> ClientSection {
    switch kind {
    case .proposal: .proposals
    case .commitmentBy, .commitmentTo: .commitments
    case .task: .tasks
    case .alert: .alerts
    }
  }

  static func colour(_ kind: Kind) -> Color {
    switch kind {
    case .commitmentBy: ClientPalette.rgb(243, 169, 130)
    case .commitmentTo: ClientPalette.rgb(176, 193, 227)
    case .proposal: ClientPalette.rgb(240, 185, 226)
    case .alert: ClientPalette.rgb(216, 140, 140)
    // The AGENTS.md Q12 default, until Dom picks.
    case .task: ClientPalette.rgb(0x7F, 0xBF, 0xC1)
    }
  }

  static func name(_ horizon: Components.Schemas.Horizon) -> String {
    switch horizon {
    case .now: "Now"
    case .week: "This week"
    case .later: "Later"
    }
  }
}

/// The expanded client's colours and type, from the design README.
enum ClientPalette {
  static let text = rgb(0xF2, 0xEE, 0xEE)
  static let ground = rgb(0x17, 0x17, 0x17)
  static let resolved = rgb(0x9E, 0xC2, 0xA1)
  static let line = Color.white.opacity(0.08)

  static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
    Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: 1)
  }

  static func secondary(_ opacity: Double = 0.75) -> Color { text.opacity(opacity) }

  /// The monospaced, tracked small capitals the design uses for labels.
  static let label = Font.system(size: 11, design: .monospaced)
  static let labelTracking: CGFloat = 1.76
}
