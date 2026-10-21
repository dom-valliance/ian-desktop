import AppKit
import os

/// Whether the field's display link should be ticking. Pure, so each reason to stop is tested.
enum FieldClock {
  /// The link runs while the field may animate, is on screen, and something moves. The yaw sways
  /// for as long as it is visible; under Reduce Motion only a growth or a sink moves it.
  static func shouldRun(
    isAnimating: Bool, isOnScreen: Bool, reducedMotion: Bool, hasTransition: Bool
  ) -> Bool {
    isAnimating && isOnScreen && (!reducedMotion || hasTransition)
  }
}

/// The Pillars field as a layer-backed view that draws with Core Graphics (ADR 0018).
///
/// A SwiftUI `TimelineView` re-lays out and re-commits its view graph every frame, which cost
/// more than the drawing itself. This view draws `PillarsRenderer`'s output with
/// `PillarsPainter` in `draw(_:)`, and a display link asks for a frame only while the field
/// animates, is on screen and something moves. Otherwise the link is paused and the field keeps
/// the pose it was last drawn in (non-negotiable 7).
///
/// The view takes the mouse itself and feeds `FieldPointer`: a drag turns the field, a click
/// selects a pillar and a double-click returns it to 45 degrees.
@MainActor
final class PillarsFieldNSView: NSView {
  /// Spec 6.9 asks for 60 frames a second. A ProMotion display would otherwise draw at 120.
  static let frameRate: Float = 60
  /// A frame is repainted once something has moved this many device pixels.
  static let pixelFraction = 1.0
  /// ... or a colour channel has changed this much on the 0 to 255 scale.
  static let colourStep = 6.0

  var scene: PillarsScene {
    didSet { if scene != oldValue { sceneChanged() } }
  }
  var isAnimating: Bool {
    didSet { if isAnimating != oldValue { settingsChanged() } }
  }
  var reducedMotion: Bool {
    didSet { if reducedMotion != oldValue { settingsChanged() } }
  }
  var onSelect: (PillarCellKey) -> Void
  var onTurn: (Double) -> Void

  /// Whether the view can be seen: in a visible, unoccluded window and not hidden. A seam so
  /// tests can stand for a window the system has put on screen.
  var isOnScreen: () -> Bool = { false }
  /// Seconds since the reference date, the scale scene times use.
  var clock: () -> Double = { Date.now.timeIntervalSinceReferenceDate }

  private(set) var pointer: FieldPointer
  /// How many times a repaint has been asked for. A window the system has not shown never
  /// clears `needsDisplay`, so tests count requests instead.
  private(set) var repaintRequests = 0
  private var link: CADisplayLink?
  private static let log = Logger(subsystem: "ai.valliance.ian.desktop", category: "motion")
  /// What the last frame showed. A tick repaints only if the new drawing differs visibly.
  private var shown: PillarsDrawing?
  private let labels = PillarsLabels()

  /// Whether the display link is delivering frames.
  var isTicking: Bool { link.map { !$0.isPaused } ?? false }

  init(
    scene: PillarsScene, isAnimating: Bool, reducedMotion: Bool, angle: Double,
    onTurn: @escaping (Double) -> Void, onSelect: @escaping (PillarCellKey) -> Void
  ) {
    self.scene = scene
    self.isAnimating = isAnimating
    self.reducedMotion = reducedMotion
    self.onSelect = onSelect
    self.onTurn = onTurn
    pointer = FieldPointer(angle: angle)
    super.init(frame: .zero)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    setAccessibilityElement(false)
    isOnScreen = { [unowned self] in
      guard let window else { return false }
      return window.occlusionState.contains(.visible) && !isHiddenOrHasHiddenAncestor
    }
  }

  required init?(coder: NSCoder) {
    fatalError("PillarsFieldNSView is built in code.")
  }

  /// The system picks a half-float backing store on a wide-colour display, and Core Graphics
  /// composites every polygon into that slower than into 8 bits a channel.
  override func makeBackingLayer() -> CALayer {
    let layer = CALayer()
    layer.contentsFormat = .RGBA8Uint
    return layer
  }

  /// With `.onSetNeedsDisplay` a resize does not mark the layer for display, and the old bitmap
  /// would stretch. A paused field, under Reduce Motion or suppression, would stay distorted, so
  /// a new size or scale repaints at once.
  override func setFrameSize(_ newSize: NSSize) {
    let changed = newSize != frame.size
    super.setFrameSize(newSize)
    if changed { redrawNow() }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    redrawNow()
  }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // MARK: Clock

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    link?.invalidate()
    link = nil
    guard let window else { return }
    NotificationCenter.default.addObserver(
      self, selector: #selector(visibilityChanged),
      name: NSWindow.didChangeOcclusionStateNotification,
      object: window)
    let link = displayLink(target: LinkTarget(view: self), selector: #selector(LinkTarget.tick))
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: Self.frameRate, maximum: Self.frameRate, preferred: Self.frameRate)
    link.isPaused = true
    // `.common` keeps frames coming while a drag or a divider holds the run loop in tracking.
    link.add(to: .main, forMode: .common)
    self.link = link
    Self.log.notice("field window attached, display link created")
    updateClock()
  }

  override func viewDidHide() {
    super.viewDidHide()
    updateClock()
  }

  override func viewDidUnhide() {
    super.viewDidUnhide()
    updateClock()
  }

  @objc private func visibilityChanged(_ note: Notification) {
    Self.log.notice(
      "field window occlusion changed, visible: \(self.window?.occlusionState.contains(.visible) ?? false, privacy: .public)"
    )
    updateClock()
    redrawNow()
  }

  /// Starts or pauses the link to match the field's state, and draws the pose once when it stops.
  func updateClock() {
    guard let link else { return }
    let run = FieldClock.shouldRun(
      isAnimating: isAnimating, isOnScreen: isOnScreen(), reducedMotion: reducedMotion,
      hasTransition: clock() < scene.transitionEnd)
    guard link.isPaused == run else { return }
    link.isPaused = !run
    Self.log.notice(
      "field clock \(run ? "started" : "paused", privacy: .public), animating: \(self.isAnimating, privacy: .public), on screen: \(self.isOnScreen(), privacy: .public), reduced motion: \(self.reducedMotion, privacy: .public), transition running: \(self.clock() < self.scene.transitionEnd, privacy: .public)"
    )
    if !run { redrawNow() }
  }

  /// One display frame. The drawing is cheap to make; painting it is not, so a frame that would
  /// look like the last one is dropped.
  @objc func tick() {
    updateClock()
    let next = drawing(at: clock())
    let fit = PillarsFit(size: bounds.size)
    if let shown,
      !next.isVisiblyDifferent(
        from: shown, pointTolerance: pointTolerance(for: fit), colourTolerance: Self.colourStep)
    {
      return
    }
    shown = next
    repaintRequests += 1
    setNeedsDisplay(fit.rect)
  }

  /// One device pixel, in box units, scaled by `pixelFraction`.
  func pointTolerance(for fit: PillarsFit) -> Double {
    Self.pixelFraction / (fit.scale * backingScale)
  }

  private var backingScale: Double { Double(window?.backingScaleFactor ?? 2) }

  private func sceneChanged() {
    updateClock()
    redrawNow()
  }

  private func settingsChanged() {
    updateClock()
    redrawNow()
  }

  /// Repaints the next display cycle whatever the last frame showed.
  private func redrawNow() {
    shown = nil
    repaintRequests += 1
    needsDisplay = true
  }

  // MARK: Drawing

  /// A stopped field holds its pose, and Reduce Motion never sways.
  private var still: Bool { reducedMotion || !isAnimating }

  private func drawing(at clock: Double) -> PillarsDrawing {
    PillarsRenderer.drawing(
      for: scene,
      time: PillarsFieldView.drawTime(scene: scene, isAnimating: isAnimating, clock: clock),
      reducedMotion: still, angle: pointer.angle)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let drawing = shown ?? drawing(at: clock())
    shown = drawing
    PillarsPainter.paint(
      drawing, in: context, fit: PillarsFit(size: bounds.size), labels: labels)
  }

  // MARK: Pointer

  override func mouseDown(with event: NSEvent) {
    pointerDown(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    pointerMoved(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    pointerUp(
      at: convert(event.locationInWindow, from: nil), time: event.timestamp,
      doubleClickInterval: NSEvent.doubleClickInterval)
  }

  private var pressedAt: CGPoint?

  func pointerDown(at location: CGPoint) {
    pressedAt = location
    pointer.changed(translation: .zero)
  }

  func pointerMoved(to location: CGPoint) {
    guard let pressedAt else { return }
    pointer.changed(
      translation: CGSize(width: location.x - pressedAt.x, height: location.y - pressedAt.y))
    redrawNow()
  }

  func pointerUp(
    at location: CGPoint, time: TimeInterval,
    doubleClickInterval: TimeInterval = FieldTurn.doubleClickInterval
  ) {
    guard pressedAt != nil else { return }
    pressedAt = nil
    switch pointer.ended(location: location, time: time, doubleClickInterval: doubleClickInterval) {
    case .turned, .reset:
      onTurn(pointer.angle)
      redrawNow()
    case .select(let location):
      let fit = PillarsFit(size: bounds.size)
      if let key = PillarsRenderer.hit(fit.toBox(location), in: drawing(at: clock())) {
        onSelect(key)
      }
    }
  }
}

/// What the display link retains in place of the view, so a view that never leaves its window
/// can still be released.
@MainActor
private final class LinkTarget: NSObject {
  private weak var view: PillarsFieldNSView?

  init(view: PillarsFieldNSView) {
    self.view = view
  }

  @objc func tick() {
    view?.tick()
  }
}
