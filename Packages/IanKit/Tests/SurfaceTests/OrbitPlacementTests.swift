import CoreGraphics
import Foundation
import Testing

@testable import Surface

@Suite("Orbit placement")
struct OrbitPlacementTests {
  private let area = CGRect(x: 0, y: 40, width: 1440, height: 1000)

  @Test("sits sixteen points from the bottom right by default")
  func defaultCorner() {
    let frame = OrbitPlacement.orbitFrame(corner: .bottomRight, in: area)
    #expect(frame == CGRect(x: 1440 - 16 - 96, y: 40 + 16, width: 96, height: 96))
  }

  @Test("places the other three corners with the same inset")
  func otherCorners() {
    #expect(
      OrbitPlacement.orbitFrame(corner: .bottomLeft, in: area)
        == CGRect(x: 16, y: 56, width: 96, height: 96))
    #expect(
      OrbitPlacement.orbitFrame(corner: .topLeft, in: area)
        == CGRect(x: 16, y: 1040 - 16 - 96, width: 96, height: 96))
    #expect(
      OrbitPlacement.orbitFrame(corner: .topRight, in: area)
        == CGRect(x: 1440 - 112, y: 1040 - 112, width: 96, height: 96))
  }

  @Test(
    "snaps a dropped Orbit to the nearest corner",
    arguments: [
      (CGPoint(x: 1300, y: 100), Corner.bottomRight),
      (CGPoint(x: 100, y: 100), .bottomLeft),
      (CGPoint(x: 100, y: 700), .topLeft),
      (CGPoint(x: 1300, y: 700), .topRight),
      (CGPoint(x: 800, y: 500), .topRight),
      (CGPoint(x: 600, y: 300), .bottomLeft),
    ])
  func snapsToNearestCorner(origin: CGPoint, expected: Corner) {
    let dropped = CGRect(origin: origin, size: CGSize(width: 96, height: 96))
    #expect(OrbitPlacement.nearestCorner(to: dropped, in: area) == expected)
  }

  @Test("anchors the expanded client above a bottom corner, on the Orbit's side")
  func expandedAboveBottomRight() {
    let orbit = OrbitPlacement.orbitFrame(corner: .bottomRight, in: area)
    let frame = OrbitPlacement.expandedFrame(orbit: orbit, corner: .bottomRight, in: area)
    #expect(frame.size == CGSize(width: 1040, height: 720))
    #expect(frame.maxX == orbit.maxX)
    #expect(frame.minY == orbit.maxY + 12)
  }

  @Test("anchors the expanded client from the left edge for a left corner")
  func expandedLeft() {
    let orbit = OrbitPlacement.orbitFrame(corner: .bottomLeft, in: area)
    let frame = OrbitPlacement.expandedFrame(orbit: orbit, corner: .bottomLeft, in: area)
    #expect(frame.minX == orbit.minX)
  }

  @Test("hangs the expanded client below a top corner")
  func expandedBelowTop() {
    let orbit = OrbitPlacement.orbitFrame(corner: .topRight, in: area)
    let frame = OrbitPlacement.expandedFrame(orbit: orbit, corner: .topRight, in: area)
    #expect(frame.maxY == orbit.minY - 12)
  }

  @Test("moves the expanded client's anchor when the Orbit moves")
  func anchorFollowsOrbit() {
    let right = OrbitPlacement.expandedFrame(
      orbit: OrbitPlacement.orbitFrame(corner: .bottomRight, in: area), corner: .bottomRight,
      in: area)
    let left = OrbitPlacement.expandedFrame(
      orbit: OrbitPlacement.orbitFrame(corner: .bottomLeft, in: area), corner: .bottomLeft,
      in: area)
    #expect(left.minX < right.minX)
  }

  @Test("shrinks the expanded client to fit a small display")
  func expandedFitsSmallDisplay() {
    let small = CGRect(x: 0, y: 0, width: 800, height: 500)
    let orbit = OrbitPlacement.orbitFrame(corner: .bottomRight, in: small)
    let frame = OrbitPlacement.expandedFrame(orbit: orbit, corner: .bottomRight, in: small)
    #expect(small.contains(frame))
  }

  @Test("takes clicks inside the avatar's circle and passes them through its corners")
  func hitRegion() {
    let frame = CGRect(x: 100, y: 100, width: 96, height: 96)
    #expect(OrbitPlacement.hitsAvatar(CGPoint(x: 148, y: 148), in: frame))
    #expect(OrbitPlacement.hitsAvatar(CGPoint(x: 190, y: 148), in: frame))
    #expect(!OrbitPlacement.hitsAvatar(CGPoint(x: 101, y: 101), in: frame))
    #expect(!OrbitPlacement.hitsAvatar(CGPoint(x: 195, y: 195), in: frame))
  }
}

@Suite("Corner setting")
@MainActor
struct CornerSettingTests {
  @Test("defaults to the bottom right")
  func defaultsToBottomRight() {
    withScratchDefaults { defaults in
      #expect(CornerSetting(defaults: defaults).corner == .bottomRight)
    }
  }

  @Test("remembers the corner across a new instance")
  func persists() {
    withScratchDefaults { defaults in
      CornerSetting(defaults: defaults).corner = .topLeft
      #expect(CornerSetting(defaults: defaults).corner == .topLeft)
    }
  }

  @Test("falls back to the bottom right for a value it does not know")
  func unknownValue() {
    withScratchDefaults { defaults in
      defaults.set("middle", forKey: CornerSetting.defaultsKey)
      #expect(CornerSetting(defaults: defaults).corner == .bottomRight)
    }
  }
}

@Suite("App menu")
struct AppMenuTests {
  @Test("lists Open, Pause me, Settings and Quit Ian in order")
  func entries() {
    let titles = AppMenu.entries(isPaused: false).compactMap { entry -> String? in
      if case .command(_, let title, _, _) = entry { title } else { nil }
    }
    #expect(titles == ["Open", "Pause me", "Settings", "Quit Ian"])
  }

  @Test("checks Pause me only while paused")
  func pauseCheckmark() {
    func state(_ paused: Bool) -> Bool? {
      for case .command(.togglePause, _, let isChecked, _) in AppMenu.entries(isPaused: paused) {
        return isChecked
      }
      return nil
    }
    #expect(state(true) == true)
    #expect(state(false) == false)
  }

  @Test("titles the menu bar with the count only when it is above zero")
  func barTitle() {
    #expect(AppMenu.barTitle(nowCount: 0) == "Ian")
    #expect(AppMenu.barTitle(nowCount: 3) == "Ian 3")
  }
}
