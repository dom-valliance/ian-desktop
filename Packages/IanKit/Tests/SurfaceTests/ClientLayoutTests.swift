import Foundation
import TestSupport
import Testing

@testable import Surface

@Suite("Client layout settings")
@MainActor
struct ClientLayoutSettingsTests {
  @Test("defaults to 45 degrees, a 190 point sidebar and a 300 point field")
  func defaults() {
    withScratchDefaults { defaults in
      let settings = ClientLayoutSettings(defaults: defaults)
      #expect(settings.angle == 45)
      #expect(settings.sidebarWidth == 190)
      #expect(settings.fieldHeight == 300)
    }
  }

  @Test("saves the angle and both divider positions and restores them")
  func roundTrip() {
    withScratchDefaults { defaults in
      let settings = ClientLayoutSettings(defaults: defaults)
      settings.angle = 225
      settings.sidebarWidth = 240
      settings.fieldHeight = 360

      let restored = ClientLayoutSettings(defaults: defaults)
      #expect(restored.angle == 225)
      #expect(restored.sidebarWidth == 240)
      #expect(restored.fieldHeight == 360)
    }
  }

  @Test("stores each value under its own key")
  func keys() {
    withScratchDefaults { defaults in
      let settings = ClientLayoutSettings(defaults: defaults)
      settings.angle = 100
      settings.sidebarWidth = 200
      settings.fieldHeight = 250
      #expect(defaults.double(forKey: "IanFieldAngle") == 100)
      #expect(defaults.double(forKey: "IanSidebarWidth") == 200)
      #expect(defaults.double(forKey: "IanFieldHeight") == 250)
    }
  }

  @Test("keeps a saved angle within 0 to 360 degrees")
  func normalisesAngle() {
    withScratchDefaults { defaults in
      let settings = ClientLayoutSettings(defaults: defaults)
      settings.angle = -90
      #expect(settings.angle == 270)
      defaults.set(450.0, forKey: ClientLayoutSettings.angleKey)
      #expect(settings.angle == 90)
    }
  }

  @Test("ignores a value that is not a finite number")
  func ignoresNonFiniteWrites() {
    withScratchDefaults { defaults in
      let settings = ClientLayoutSettings(defaults: defaults)
      settings.angle = 100
      settings.sidebarWidth = 200
      settings.fieldHeight = 250
      settings.angle = .nan
      settings.sidebarWidth = .infinity
      settings.fieldHeight = .nan
      #expect(settings.angle == 100)
      #expect(settings.sidebarWidth == 200)
      #expect(settings.fieldHeight == 250)
    }
  }

  @Test("falls back to the defaults for values that are not usable")
  func ignoresBadValues() {
    withScratchDefaults { defaults in
      defaults.set("wide", forKey: ClientLayoutSettings.sidebarWidthKey)
      defaults.set(-5.0, forKey: ClientLayoutSettings.fieldHeightKey)
      defaults.set(Double.nan, forKey: ClientLayoutSettings.angleKey)
      let settings = ClientLayoutSettings(defaults: defaults)
      #expect(settings.sidebarWidth == 190)
      #expect(settings.fieldHeight == 300)
      #expect(settings.angle == 45)
    }
  }
}

@Suite("Pane limits")
struct PaneLimitsTests {
  @Test("keeps the sidebar at least 160 points wide")
  func sidebarMinimum() {
    #expect(PaneLimits.sidebarWidth(40, containerWidth: 1000) == 160)
  }

  @Test("leaves the field and lists at least 480 points of width, and the sidebar at most 320")
  func sidebarMaximum() {
    #expect(PaneLimits.sidebarWidth(900, containerWidth: 1000) == 320)
    #expect(PaneLimits.sidebarWidth(900, containerWidth: 700) == 220)
  }

  @Test("keeps the field pane at least 180 points tall")
  func fieldMinimum() {
    #expect(PaneLimits.fieldHeight(20, containerHeight: 600) == 180)
  }

  @Test("leaves the lists and footer at least 220 points of height")
  func fieldMaximum() {
    #expect(PaneLimits.fieldHeight(900, containerHeight: 600) == 380)
  }

  @Test("lets the minimum win when the window is smaller than both minimums")
  func minimumWinsInATinyWindow() {
    #expect(PaneLimits.fieldHeight(300, containerHeight: 300) == 180)
    #expect(PaneLimits.sidebarWidth(190, containerWidth: 400) == 160)
  }

  @Test("fits the field to its pane, keeping the aspect, as the pane grows and shrinks")
  func fieldFollowsItsPane() {
    let tall = PillarsFit(size: CGSize(width: 600, height: 840))
    #expect(abs(tall.scale - 600 / 540) < 1e-9)
    #expect(abs(tall.offset.y - (840 - 420 * 600 / 540) / 2) < 1e-9)
    let small = PillarsFit(size: CGSize(width: 800, height: 210))
    #expect(abs(small.scale - 0.5) < 1e-9)
    #expect(abs(small.offset.x - (800 - 270) / 2) < 1e-9)
    #expect(small.offset.y == 0)
  }
}
