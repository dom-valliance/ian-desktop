import Foundation
import Testing

@testable import Surface

@Suite("Orbit renderer")
struct OrbitRendererTests {
  private func model(
    load: Int = 10, median: Double = 20, working: Bool = false, overflow: Int = 0,
    kinds: [OrbitModel.Kind] = []
  ) -> OrbitModel {
    OrbitModel(
      satellites: kinds.enumerated().map {
        OrbitModel.Satellite(slot: $0.offset, kind: $0.element)
      },
      overflow: overflow, load: load, median: median, working: working)
  }

  private func drawing(_ model: OrbitModel, time: Double = 0, reduced: Bool = false)
    -> OrbitDrawing
  {
    OrbitRenderer.drawing(for: model, time: time, reducedMotion: reduced)
  }

  // MARK: Ring

  @Test("draws a load arc shorter than the circle when load is below the median")
  func loadBelowMedian() throws {
    let drawing = drawing(model(load: 5, median: 20))
    #expect(try #require(drawing.loadArc).fraction == 0.25)
    #expect(drawing.overMedianArc == nil)
  }

  @Test("draws a full load arc and no outer arc when load equals the median")
  func loadAtMedian() throws {
    let drawing = drawing(model(load: 20, median: 20))
    #expect(try #require(drawing.loadArc).fraction == 1)
    #expect(drawing.overMedianArc == nil)
  }

  @Test("draws a full load arc and an outer arc for the load above the median")
  func loadAboveMedian() throws {
    let drawing = drawing(model(load: 26, median: 20))
    #expect(try #require(drawing.loadArc).fraction == 1)
    let outer = try #require(drawing.overMedianArc)
    #expect(abs(outer.fraction - 0.3) < 1e-9)
    #expect(outer.radius == 42)
  }

  @Test("caps the outer arc at the full circle")
  func outerArcCapped() throws {
    let drawing = drawing(model(load: 100, median: 20))
    #expect(try #require(drawing.overMedianArc).fraction == 1)
  }

  @Test("draws no load arc when nothing is open")
  func noLoad() {
    #expect(drawing(model(load: 0)).loadArc == nil)
  }

  // MARK: Satellites

  @Test("places satellites at the five angles in the server's order")
  func satelliteAngles() throws {
    let kinds: [OrbitModel.Kind] = [.proposal, .commitmentBy, .commitmentTo, .task, .proposal]
    let drawing = drawing(model(kinds: kinds))
    #expect(drawing.satellites.map(\.slot) == [0, 1, 2, 3, 4])
    for (satellite, degrees) in zip(drawing.satellites, [-90.0, -18, 54, 126, 198]) {
      let angle = degrees * .pi / 180
      #expect(abs(satellite.centre.x - (50 + 34 * cos(angle))) < 1e-9)
      #expect(abs(satellite.centre.y - (50 + 34 * sin(angle))) < 1e-9)
    }
    #expect(drawing.satellites[0].centre.y < 50)
  }

  @Test("colours each satellite by the kind of its item")
  func satelliteColours() {
    let drawing = drawing(model(kinds: [.commitmentBy, .commitmentTo, .proposal, .alert, .task]))
    #expect(drawing.satellites[0].colour == OrbitColour(243, 169, 130))
    #expect(drawing.satellites[1].colour == OrbitColour(176, 193, 227))
    #expect(drawing.satellites[2].colour == OrbitColour(240, 185, 226))
    #expect(drawing.satellites[3].colour == OrbitColour(216, 140, 140))
    #expect(drawing.satellites[4].colour == OrbitColour(0x7F, 0xBF, 0xC1))
  }

  @Test("draws an alert larger than other satellites, with a rim")
  func alertIsLargerWithRim() throws {
    let drawing = drawing(model(kinds: [.proposal, .alert]))
    #expect(drawing.satellites[0].radius == 4.5)
    #expect(drawing.satellites[0].rim == nil)
    #expect(drawing.satellites[1].radius == 6.5)
    #expect(try #require(drawing.satellites[1].rim).width == 1.5)
  }

  @Test("pulses an alert's rim with time and holds it full under reduced motion")
  func rimPulse() throws {
    let alert = model(kinds: [.alert])
    let moving = try #require(drawing(alert, time: 0.6).satellites[0].rim)
    let expected = 0.5 + 0.5 * (0.5 + 0.5 * sin(5 * 0.6))
    #expect(abs(moving.colour.alpha - expected) < 1e-9)

    let still = try #require(drawing(alert, time: 0.6, reduced: true).satellites[0].rim)
    #expect(still.colour.alpha == 1)
    let stillLater = try #require(drawing(alert, time: 3, reduced: true).satellites[0].rim)
    #expect(stillLater == still)
  }

  @Test("skips slots the model does not hold and keeps the others in place")
  func gapInSlots() {
    let model = OrbitModel(
      satellites: [.init(slot: 0, kind: .proposal), .init(slot: 2, kind: .task)], load: 3,
      median: 12)
    #expect(drawing(model).satellites.map(\.slot) == [0, 2])
  }

  // MARK: Overflow chip

  @Test("draws the overflow chip only when overflow is above zero")
  func overflowChip() throws {
    #expect(drawing(model(overflow: 0)).chip == nil)
    let chip = try #require(drawing(model(overflow: 5)).chip)
    #expect(chip.text == "+5")
  }

  // MARK: Core

  @Test("breathes the core while working, from a radius of six to seven")
  func coreBreath() {
    let working = model(working: true)
    let at = drawing(working, time: 0.6).core
    #expect(abs(at.radius - (6 + 0.5 + 0.5 * sin(1.5 * 0.6))) < 1e-9)
    #expect(at.colour == OrbitColour(0xB0, 0xC1, 0xE3))
  }

  @Test("holds the core still under reduced motion")
  func coreStillWhenReduced() {
    let working = model(working: true)
    #expect(drawing(working, time: 0.6, reduced: true).core.radius == 6.5)
    #expect(drawing(working, time: 2.2, reduced: true).core.radius == 6.5)
  }

  @Test("rings a working core when Reduce Motion holds it still, and only then")
  func workingRing() {
    let working = model(working: true)
    #expect(drawing(working, time: 0.6, reduced: true).core.ring == 10)
    #expect(drawing(working, time: 0.6).core.ring == nil)
    #expect(drawing(model(working: false), time: 0.6, reduced: true).core.ring == nil)
  }

  @Test("rests the core grey and small when nothing is working")
  func coreResting() {
    let core = drawing(model(working: false), time: 0.6).core
    #expect(core.radius == 6)
    #expect(core.colour == OrbitColour(0xA1, 0x9A, 0x9A))
  }

  // MARK: Motion

  @Test("reports motion only while something working or an alert is drawn")
  func hasMotion() {
    #expect(!OrbitRenderer.hasMotion(model(kinds: [.proposal])))
    #expect(OrbitRenderer.hasMotion(model(working: true)))
    #expect(OrbitRenderer.hasMotion(model(kinds: [.proposal, .alert])))
  }
}
