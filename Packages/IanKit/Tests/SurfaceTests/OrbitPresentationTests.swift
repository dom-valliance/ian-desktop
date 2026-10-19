import Attention
import Testing

@testable import Surface

@Suite("Orbit presentation")
struct OrbitPresentationTests {
  private static let triggers: [(String, Suppression)] = [
    (
      "camera",
      Suppression(cameraLive: true, externalMeeting: false, quietHours: false, userPaused: false)
    ),
    (
      "external meeting",
      Suppression(cameraLive: false, externalMeeting: true, quietHours: false, userPaused: false)
    ),
    (
      "quiet hours",
      Suppression(cameraLive: false, externalMeeting: false, quietHours: true, userPaused: false)
    ),
    (
      "user pause",
      Suppression(cameraLive: false, externalMeeting: false, quietHours: false, userPaused: true)
    ),
  ]

  @Test("shows the top item's title on hover when nothing suppresses")
  func hoverShowsTopTitle() throws {
    for name in OrbitScenario.names where name != "quiet" {
      let scenario = OrbitScenario.load(name)
      let presentation = OrbitPresentation(state: scenario.state, suppression: .none)
      let topID = try #require(scenario.today.orbit.itemIds.first)
      let top = try #require(scenario.items.first { $0.id == topID })
      #expect(presentation.hoverText == top.title)
      #expect(presentation.model.topTitle == top.title)
    }
  }

  @Test("has no hover text when there is no satellite")
  func quietHasNoHover() {
    let presentation = OrbitPresentation(
      state: OrbitScenario.load("quiet").state, suppression: .none)
    #expect(presentation.hoverText == nil)
  }

  @Test(
    "keeps every item title off the Orbit, its hover and its label for each trigger alone",
    arguments: triggers)
  func suppressedHidesText(name: String, suppression: Suppression) {
    for scenarioName in OrbitScenario.names {
      let scenario = OrbitScenario.load(scenarioName)
      let presentation = OrbitPresentation(state: scenario.state, suppression: suppression)
      #expect(presentation.isSuppressed, "\(name) in \(scenarioName)")
      #expect(presentation.model.topTitle == nil, "\(name) in \(scenarioName)")
      #expect(presentation.hoverText == nil, "\(name) in \(scenarioName)")
      for title in scenario.titles {
        #expect(!presentation.accessibilityLabel.contains(title))
      }
    }
  }

  @Test("keeps showing state while suppressed")
  func suppressedKeepsState() {
    let scenario = OrbitScenario.load("normal")
    let open = OrbitPresentation(state: scenario.state, suppression: .none)
    let suppressed = OrbitPresentation(state: scenario.state, suppression: Self.triggers[0].1)
    #expect(suppressed.model.satellites == open.model.satellites)
    #expect(suppressed.model.overflow == open.model.overflow)
    #expect(suppressed.model.load == open.model.load)
    #expect(suppressed.model.working == open.model.working)
    #expect(suppressed.accessibilityLabel == open.accessibilityLabel)
  }

  @Test("takes the satellites from the Orbit block in the server's order")
  func satellitesFollowTheServer() {
    let scenario = OrbitScenario.load("incident")
    let model = OrbitPresentation(state: scenario.state, suppression: .none).model
    #expect(model.satellites.map(\.slot) == Array(0..<scenario.today.orbit.itemIds.count))
    #expect(model.satellites.first?.kind == .alert)
    #expect(model.overflow == scenario.today.orbit.overflow)
  }

  @Test("draws nothing but the empty ring before the first snapshot")
  func beforeFirstSnapshot() {
    let presentation = OrbitPresentation(
      state: .init(), suppression: .none)
    #expect(presentation.model.satellites.isEmpty)
    #expect(presentation.nowCount == 0)
    #expect(presentation.hoverText == nil)
  }
}

@Suite("Orbit accessibility label")
struct OrbitAccessibilityTests {
  @Test("reads the spec's example")
  func specExample() {
    #expect(
      OrbitAccessibility.label(nowCount: 3, load: 41, urgentCount: 1)
        == "Ian, three need you now, forty-one open, one urgent")
  }

  @Test("uses the singular when one needs you")
  func singular() {
    #expect(
      OrbitAccessibility.label(nowCount: 1, load: 1, urgentCount: 0)
        == "Ian, one needs you now, one open, none urgent")
  }

  @Test("says none for zero")
  func zero() {
    #expect(
      OrbitAccessibility.label(nowCount: 0, load: 0, urgentCount: 0)
        == "Ian, none need you now, none open, none urgent")
  }

  @Test("spells larger numbers in British English")
  func larger() {
    #expect(
      OrbitAccessibility.label(nowCount: 12, load: 101, urgentCount: 2)
        == "Ian, twelve need you now, one hundred and one open, two urgent")
  }

  @Test("is built from the server's counts")
  func fromBlock() {
    let scenario = OrbitScenario.load("normal")
    let presentation = OrbitPresentation(state: scenario.state, suppression: .none)
    let orbit = scenario.today.orbit
    #expect(
      presentation.accessibilityLabel
        == OrbitAccessibility.label(
          nowCount: orbit.nowCount, load: orbit.load, urgentCount: orbit.urgentCount))
  }
}
