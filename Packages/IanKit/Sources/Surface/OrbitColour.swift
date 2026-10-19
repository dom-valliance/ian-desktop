/// An sRGB colour with 0 to 255 channels and an alpha, so the drawing is comparable in tests.
public struct OrbitColour: Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public func withAlpha(_ alpha: Double) -> OrbitColour {
    OrbitColour(red, green, blue, alpha: alpha)
  }
}

/// The Orbit's colours, from the design README's Colour and Orbit sections.
enum OrbitPalette {
  static let track = OrbitColour(255, 255, 255, alpha: 0.10)
  static let loadArc = OrbitColour(0x8D, 0x89, 0x89)
  static let overMedianArc = OrbitColour(0xF3, 0xA9, 0x82)
  static let restingCore = OrbitColour(0xA1, 0x9A, 0x9A)
  static let workingCore = OrbitColour(0xB0, 0xC1, 0xE3)
  static let rim = OrbitColour(0xF2, 0xEE, 0xEE)
  static let chipFill = OrbitColour(0x2E, 0x2E, 0x2E)
  static let chipStroke = OrbitColour(255, 255, 255, alpha: 0.3)
  static let chipText = OrbitColour(255, 255, 255)
  static let ground = OrbitColour(0x17, 0x17, 0x17)

  static func colour(for kind: OrbitModel.Kind) -> OrbitColour {
    switch kind {
    case .commitmentBy: KindPalette.colour(for: .commitmentBy)
    case .commitmentTo: KindPalette.colour(for: .commitmentTo)
    case .proposal: KindPalette.colour(for: .proposal)
    case .alert: KindPalette.colour(for: .alert)
    case .task: KindPalette.colour(for: .task)
    }
  }
}

/// The colour of each kind of item, from the design README's Colour table. The Orbit, the field
/// and the lists all read it, so a kind has one colour everywhere.
public enum KindPalette {
  public static func colour(for kind: PillarKind) -> OrbitColour {
    switch kind {
    case .commitmentBy: OrbitColour(243, 169, 130)
    case .commitmentTo: OrbitColour(176, 193, 227)
    case .proposal: OrbitColour(240, 185, 226)
    case .alert: OrbitColour(216, 140, 140)
    // The AGENTS.md Q12 default, until Dom picks.
    case .task: OrbitColour(0x7F, 0xBF, 0xC1)
    }
  }
}
