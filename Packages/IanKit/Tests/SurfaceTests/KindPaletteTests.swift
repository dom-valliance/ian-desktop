import Testing

@testable import Surface

@Suite("Kind palette")
struct KindPaletteTests {
  @Test("gives each kind the colour the design names")
  func designColours() {
    #expect(KindPalette.colour(for: .proposal) == OrbitColour(240, 185, 226))
    #expect(KindPalette.colour(for: .commitmentBy) == OrbitColour(243, 169, 130))
    #expect(KindPalette.colour(for: .commitmentTo) == OrbitColour(176, 193, 227))
    #expect(KindPalette.colour(for: .alert) == OrbitColour(216, 140, 140))
    #expect(KindPalette.colour(for: .task) == OrbitColour(0x7F, 0xBF, 0xC1))
  }

  @Test("gives the Orbit and the field the same colour for a kind")
  func orbitAndFieldAgree() {
    #expect(OrbitPalette.colour(for: .alert) == KindPalette.colour(for: .alert))
    #expect(OrbitPalette.colour(for: .commitmentTo) == KindPalette.colour(for: .commitmentTo))
    #expect(PillarsRenderer.colour(for: .task) == KindPalette.colour(for: .task))
  }
}
