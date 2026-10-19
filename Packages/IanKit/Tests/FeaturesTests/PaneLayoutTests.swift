import Foundation
import Surface
import TestSupport
import Testing

@testable import Features

@Suite("Pane layout")
@MainActor
struct PaneLayoutTests {
  @Test("starts at the default sizes and angle")
  func startsAtDefaults() {
    withScratchDefaults { defaults in
      let layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      #expect(layout.sidebarWidth(containerWidth: 1000) == 190)
      #expect(layout.fieldHeight(containerHeight: 600) == 300)
      #expect(layout.angle == 45)
    }
  }

  @Test("restores the saved sizes and angle in a new layout")
  func restoresAfterRelaunch() {
    withScratchDefaults { defaults in
      let layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      layout.resizeSidebar(to: 250, containerWidth: 1000)
      layout.resizeField(to: 340, containerHeight: 640)
      layout.commitPanes()
      layout.commitAngle(135)

      let relaunched = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      #expect(relaunched.sidebarWidth(containerWidth: 1000) == 250)
      #expect(relaunched.fieldHeight(containerHeight: 640) == 340)
      #expect(relaunched.angle == 135)
    }
  }

  @Test("saves a divider position only when the drag lets go")
  func savesOnCommit() {
    withScratchDefaults { defaults in
      let layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      layout.resizeSidebar(to: 260, containerWidth: 1000)
      #expect(ClientLayoutSettings(defaults: defaults).sidebarWidth == 190)
      layout.commitPanes()
      #expect(ClientLayoutSettings(defaults: defaults).sidebarWidth == 260)
    }
  }

  @Test("stops a divider at the minimum and maximum sizes")
  func clampsDrags() {
    withScratchDefaults { defaults in
      let layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      layout.resizeSidebar(to: 10, containerWidth: 1000)
      #expect(layout.sidebarWidth(containerWidth: 1000) == PaneLimits.sidebarMinimum)
      layout.resizeField(to: 2000, containerHeight: 600)
      #expect(layout.fieldHeight(containerHeight: 600) == 600 - PaneLimits.listsMinimumHeight)
    }
  }

  @Test("gives a pane back its size when a smaller window grows again")
  func windowShrinksAndGrows() {
    withScratchDefaults { defaults in
      let layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      layout.resizeField(to: 340, containerHeight: 700)
      #expect(layout.fieldHeight(containerHeight: 450) == 230)
      #expect(layout.fieldHeight(containerHeight: 700) == 340)
    }
  }

  @Test("keeps the angle within 0 to 360 degrees")
  func normalisesAngle() {
    withScratchDefaults { defaults in
      let layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
      layout.commitAngle(-135)
      #expect(layout.angle == 225)
    }
  }
}
