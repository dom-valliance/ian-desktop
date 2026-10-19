import AppKit
import Testing

@testable import Surface

@Suite("Pillars field clock")
struct FieldClockTests {
  @Test("runs only while animating, on screen and something moves")
  func runsWhenAnimatingOnScreenAndMoving() {
    func run(
      _ animating: Bool = true, _ onScreen: Bool = true, _ reduced: Bool = false,
      _ transition: Bool = false
    ) -> Bool {
      FieldClock.shouldRun(
        isAnimating: animating, isOnScreen: onScreen, reducedMotion: reduced,
        hasTransition: transition)
    }
    #expect(run())
    #expect(run(true, true, false, true))
    #expect(!run(false))
    #expect(!run(true, false))
    #expect(!run(true, true, true, false))
    #expect(run(true, true, true, true))
    #expect(!run(false, true, true, true))
    #expect(!run(true, false, true, true))
  }
}

@Suite("Pillars field view")
@MainActor
struct PillarsFieldViewTests {
  private let key = PillarCellKey(unitID: "u", horizon: .now)
  private let now = 1_000.0

  private func scene(openedAt: Double? = nil) -> PillarsScene {
    PillarsScene(
      unitIDs: ["u"],
      cells: [PillarCell(key: key, pressure: 0.8, kind: .proposal, working: false)],
      selected: nil, openedAt: openedAt, sinking: [:])
  }

  /// Windows the test made, detached when it ends so no display link outlives it.
  @MainActor
  private final class Hosts {
    var windows: [NSWindow] = []
    isolated deinit { for window in windows { window.contentView = nil } }
  }
  private let hosts = Hosts()

  private final class Log {
    var selected: [PillarCellKey] = []
    var turned: [Double] = []
  }

  /// A field in a window the test says is on screen, at the box's own size so the fit is one.
  private func field(
    scene: PillarsScene, isAnimating: Bool = true, reducedMotion: Bool = false,
    angle: Double = FieldTurn.defaultAngle, log: Log = Log()
  ) -> (PillarsFieldNSView, NSWindow, Log) {
    let view = PillarsFieldNSView(
      scene: scene, isAnimating: isAnimating, reducedMotion: reducedMotion, angle: angle,
      onTurn: { log.turned.append($0) }, onSelect: { log.selected.append($0) })
    view.frame = CGRect(origin: .zero, size: PillarsRenderer.boxSize)
    view.clock = { [now] in now }
    view.isOnScreen = { true }
    let window = NSWindow(
      contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
    window.contentView = view
    hosts.windows.append(window)
    view.updateClock()
    return (view, window, log)
  }

  // MARK: Display link

  @Test("has no display link until it is in a window")
  func noLinkWithoutWindow() {
    let view = PillarsFieldNSView(
      scene: scene(), isAnimating: true, reducedMotion: false, angle: 45, onTurn: { _ in },
      onSelect: { _ in })
    view.updateClock()
    #expect(!view.isTicking)
  }

  @Test("ticks while animating and on screen")
  func ticksWhenAnimating() {
    let (view, _, _) = field(scene: scene())
    #expect(view.isTicking)
  }

  @Test("pauses when the panel is not animating, and resumes")
  func pausesWhenNotAnimating() {
    let (view, _, _) = field(scene: scene())
    view.isAnimating = false
    #expect(!view.isTicking)
    view.isAnimating = true
    #expect(view.isTicking)
  }

  @Test("pauses when occluded or hidden, and resumes when seen")
  func pausesWhenUnseen() {
    var seen = true
    let (view, _, _) = field(scene: scene())
    view.isOnScreen = { seen }
    seen = false
    view.updateClock()
    #expect(!view.isTicking)
    seen = true
    view.updateClock()
    #expect(view.isTicking)
  }

  @Test("pauses under Reduce Motion when nothing is growing or sinking")
  func pausesWhenReducedAndStill() {
    let (view, _, _) = field(scene: scene(), reducedMotion: true)
    #expect(!view.isTicking)
    view.reducedMotion = false
    #expect(view.isTicking)
  }

  @Test("under Reduce Motion ticks through a growth and pauses when it ends")
  func ticksThroughReducedGrowth() {
    let (view, _, _) = field(scene: scene(openedAt: now), reducedMotion: true)
    #expect(view.isTicking)
    view.clock = { [now] in now + PillarsRenderer.longestGrow + 0.1 }
    view.tick()
    #expect(!view.isTicking)
  }

  @Test("starts again when a new sink begins under Reduce Motion")
  func ticksForANewSink() {
    let (view, _, _) = field(scene: scene(), reducedMotion: true)
    #expect(!view.isTicking)
    var sinking = scene()
    sinking.sinking[key] = now
    view.scene = sinking
    #expect(view.isTicking)
  }

  @Test("returns from an occlusion notification and follows what it says")
  func occlusionNotificationReturns() {
    var seen = true
    let (view, window, _) = field(scene: scene())
    view.isOnScreen = { seen }
    seen = false
    let before = view.repaintRequests
    NotificationCenter.default.post(
      name: NSWindow.didChangeOcclusionStateNotification, object: window)
    #expect(!view.isTicking)
    #expect(view.repaintRequests > before)
    seen = true
    NotificationCenter.default.post(
      name: NSWindow.didChangeOcclusionStateNotification, object: window)
    #expect(view.isTicking)
  }

  @Test("hiding and showing the view returns and follows what it says")
  func hidingReturns() {
    let (view, _, _) = field(scene: scene())
    view.isOnScreen = { [unowned view] in !view.isHiddenOrHasHiddenAncestor }
    view.isHidden = true
    #expect(!view.isTicking)
    view.isHidden = false
    #expect(view.isTicking)
  }

  @Test("repaints at once when resized, even with the link paused")
  func resizeRepaints() {
    let (view, _, _) = field(scene: scene(), reducedMotion: true)
    #expect(!view.isTicking)
    let before = view.repaintRequests
    view.setFrameSize(CGSize(width: 300, height: 200))
    #expect(view.repaintRequests > before)
    #expect(!view.isTicking)
  }

  @Test("does not repaint when set to the size it already has")
  func sameSizeDoesNotRepaint() {
    let (view, _, _) = field(scene: scene(), reducedMotion: true)
    let before = view.repaintRequests
    view.setFrameSize(view.frame.size)
    #expect(view.repaintRequests == before)
  }

  @Test("asks for an 8-bit backing store")
  func eightBitBackingStore() {
    let (view, _, _) = field(scene: scene())
    #expect(view.layer?.contentsFormat == .RGBA8Uint)
  }

  // MARK: Repaint decision

  @Test("a tick at the same time leaves the field unpainted")
  func sameTimeSkips() {
    let (view, _, _) = field(scene: scene())
    view.tick()
    let before = view.repaintRequests
    view.tick()
    #expect(view.repaintRequests == before)
  }

  @Test("a tick under one device pixel of sway leaves the field unpainted")
  func tinyMoveSkips() {
    let (view, _, _) = field(scene: scene())
    view.tick()
    let before = view.repaintRequests
    view.clock = { [now] in now + 1.0 / 60 }
    view.tick()
    #expect(view.repaintRequests == before)
  }

  @Test("a tick after the sway has moved a device pixel paints")
  func visibleMovePaints() {
    let (view, _, _) = field(scene: scene())
    view.tick()
    let before = view.repaintRequests
    view.clock = { [now] in now + 10 }
    view.tick()
    #expect(view.repaintRequests > before)
  }

  @Test("stopping under Reduce Motion paints the finished pose")
  func reducedStopPaints() {
    let (view, _, _) = field(scene: scene(openedAt: now), reducedMotion: true)
    view.tick()
    let before = view.repaintRequests
    view.clock = { [now] in now + PillarsRenderer.longestGrow + 0.1 }
    view.tick()
    #expect(!view.isTicking)
    #expect(view.repaintRequests > before)
  }

  @Test("stops the link when it leaves its window")
  func stopsWhenRemoved() {
    let (view, window, _) = field(scene: scene())
    window.contentView = NSView()
    #expect(!view.isTicking)
  }

  // MARK: Pointer

  private func centre(of key: PillarCellKey, in view: PillarsFieldNSView) -> CGPoint {
    let drawing = PillarsRenderer.drawing(
      for: view.scene, time: now, reducedMotion: true, angle: view.pointer.angle)
    let top = drawing.cells.first { $0.key == key }!.faces.last!
    let count = Double(top.points.count)
    return CGPoint(
      x: top.points.map(\.x).reduce(0, +) / count, y: top.points.map(\.y).reduce(0, +) / count)
  }

  @Test("selects the pillar under a click")
  func clickSelects() {
    let (view, _, log) = field(scene: scene(), reducedMotion: true)
    let point = centre(of: key, in: view)
    view.pointerDown(at: point)
    view.pointerUp(at: point, time: 1)
    #expect(log.selected == [key])
    #expect(log.turned.isEmpty)
  }

  @Test("selects nothing for a click outside every cell")
  func clickOutsideSelectsNothing() {
    let (view, _, log) = field(scene: scene(), reducedMotion: true)
    view.pointerDown(at: CGPoint(x: 2, y: 2))
    view.pointerUp(at: CGPoint(x: 2, y: 2), time: 1)
    #expect(log.selected.isEmpty)
  }

  @Test("turns on a drag, reports the angle once and selects nothing")
  func dragTurns() {
    let (view, _, log) = field(scene: scene(), reducedMotion: true)
    let start = centre(of: key, in: view)
    view.pointerDown(at: start)
    view.pointerMoved(to: CGPoint(x: start.x - 100, y: start.y))
    view.pointerUp(at: CGPoint(x: start.x - 100, y: start.y), time: 1)
    #expect(abs(view.pointer.angle - 95) < 1e-9)
    #expect(log.turned == [view.pointer.angle])
    #expect(log.selected.isEmpty)
  }

  @Test("a double-click returns to 45 degrees and selects only once")
  func doubleClickResets() {
    let (view, _, log) = field(scene: scene(), reducedMotion: true, angle: 135)
    let point = centre(of: key, in: view)
    view.pointerDown(at: point)
    view.pointerUp(at: point, time: 1)
    view.pointerDown(at: point)
    view.pointerUp(at: point, time: 1.2)
    #expect(view.pointer.angle == FieldTurn.defaultAngle)
    #expect(log.turned == [FieldTurn.defaultAngle])
    #expect(log.selected.count == 1)
  }

  @Test("hits the pillar at a turned angle")
  func hitFollowsTheAngle() {
    for angle in [135.0, 225.0, 315.0] {
      let (view, _, log) = field(scene: scene(), reducedMotion: true, angle: angle)
      let point = centre(of: key, in: view)
      view.pointerDown(at: point)
      view.pointerUp(at: point, time: 1)
      #expect(log.selected == [key])
    }
  }

  @Test("hits the same pillar through the view as the renderer's hit test")
  func hitMatchesTheRenderer() {
    let (view, _, _) = field(scene: scene(), reducedMotion: true, angle: 200)
    let drawing = PillarsRenderer.drawing(
      for: view.scene, time: now, reducedMotion: true, angle: 200)
    #expect(PillarsRenderer.hit(centre(of: key, in: view), in: drawing) == key)
  }
}
