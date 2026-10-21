import AppKit
import Attention
import Observation
import Store
import SwiftUI
import os

/// Owns the app's windows and everything that reacts to the pointer: the Orbit, its hover label
/// and the expanded client (ADR 0005). Nothing here decides what an item is; it draws the
/// presentation the store and suppression give it.
@MainActor
@Observable
public final class SurfaceController {
  private static let hoverSize = CGSize(width: 320, height: 30)
  private static let hoverGap: CGFloat = 8

  public private(set) var corner: Corner
  /// False once the Orbit's panel is fully covered or off screen. Its animations are removed then.
  public private(set) var isOrbitOnScreen = true
  /// The client settings of spec 6.4 that the surface reads: motion and the suppression toggles.
  public let settings: ClientSettings
  /// Runs when the Settings command opens the panel, so the client can show its Settings view.
  /// Surface does not know the views; whoever hosts the content sets this.
  public var onOpenSettings: (@MainActor () -> Void)?
  /// Runs after the panel opens for an item, so the client can show the view that holds it.
  /// Surface does not know the views; whoever hosts the content sets this.
  public var onShowItem: (@MainActor (ItemDestination) -> Void)?
  /// The urgent item's one-line whisper, drawn in the hover label's place (spec 6.6).
  public let whisper: Whisper
  /// The Stop item's "open on the next pointer movement".
  public let stopArming = StopArming()
  /// False once the expanded client is hidden or fully covered. Its animation stops then.
  public private(set) var isExpandedOnScreen = false
  /// When the expanded client last opened, in seconds since the reference date, for the
  /// pillars' rise. Nil before the first opening.
  public private(set) var expandedOpenedAt: TimeInterval?

  @ObservationIgnored private let store: IanStore
  @ObservationIgnored private let signals: SuppressionSignals
  @ObservationIgnored private let cornerSetting: CornerSetting
  @ObservationIgnored private let screenArea: @MainActor () -> CGRect
  @ObservationIgnored private let quit: @MainActor () -> Void
  @ObservationIgnored private let orbitPanel = WindowFactory.makeOrbitPanel(content: NSView())
  @ObservationIgnored private let hoverPanel = WindowFactory.makeHoverPanel(
    content: NSView(), size: SurfaceController.hoverSize)
  @ObservationIgnored private let expandedPanel = WindowFactory.makeExpandedPanel(
    content: NSView())
  @ObservationIgnored private var isDragging = false
  @ObservationIgnored private var isHovering = false
  @ObservationIgnored private var whisperObservation: Int?
  @ObservationIgnored private var whisperObservations = 0
  @ObservationIgnored private var monitors: [Any] = []
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []

  /// - Parameters:
  ///   - screenArea: The visible frame of the main display, which is where the Orbit sits.
  ///   - quit: What "Quit Ian" does.
  public init(
    store: IanStore,
    signals: SuppressionSignals,
    defaults: UserDefaults = .standard,
    screenArea: @escaping @MainActor () -> CGRect = {
      (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame
        ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    },
    quit: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) },
    whisper: Whisper = Whisper()
  ) {
    self.whisper = whisper
    self.store = store
    self.signals = signals
    self.cornerSetting = CornerSetting(defaults: defaults)
    self.corner = CornerSetting(defaults: defaults).corner
    self.settings = ClientSettings(defaults: defaults)
    self.screenArea = screenArea
    self.quit = quit

    let host = OrbitHostView(content: OrbitRootView(controller: self))
    host.onClick = { [weak self] in self?.toggleExpanded() }
    host.onDrag = { [weak self] origin in self?.dragOrbit(to: origin) }
    host.onDragEnd = { [weak self] in self?.finishDrag() }
    host.menuProvider = { [weak self] in self?.makeMenu() }
    orbitPanel.contentView = host
    hoverPanel.contentView = NSHostingView(rootView: HoverLabelView(controller: self))
    expandedPanel.contentView = NSHostingView(rootView: ExpandedPanelSurface { Color.clear })
    expandedPanel.onCancel = { [weak self] in self?.hideExpanded() }
    placeOrbit()
  }

  // MARK: State read by the views

  /// Every window this controller opens, which tests check for `sharingType`.
  public var windows: [NSWindow] { [orbitPanel, hoverPanel, expandedPanel] }

  public var isExpandedVisible: Bool { expandedPanel.isVisible }

  /// Whether the expanded client's animation should run: it is on screen and nothing suppresses
  /// it (spec 6.9, AGENTS.md rule 7).
  public var isExpandedAnimating: Bool { isExpandedOnScreen && !suppression.isActive }

  /// Whether the Orbit's motion should run: it is on screen and nothing suppresses it (spec 6.9,
  /// AGENTS.md rule 7). Reduce Motion is applied by the view that has the system setting.
  public var isOrbitAnimating: Bool { isOrbitOnScreen && !suppression.isActive }

  /// The spec 6.4 motion setting. The system's Reduce Motion forces reduced regardless, which
  /// the views that read the environment apply.
  public var reducedMotionSetting: Bool { settings.reducedMotion }

  private var reducesMotion: Bool {
    MotionPreference.reduces(
      setting: reducedMotionSetting,
      system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }

  public var suppression: Suppression {
    let context = store.state.today?.context
    return signals.suppression(
      externalMeeting: context?.inExternalMeeting ?? false,
      quietHours: context?.quietHoursActive ?? false, toggles: settings.suppressionToggles)
  }

  /// The whisper while there is one and nothing suppresses it, else the top item's title, which
  /// the Orbit's model already withholds while suppressed.
  var hoverLabel: String? {
    if !suppression.isActive, let title = whisper.title { return title }
    return presentation.hoverText
  }

  public var presentation: OrbitPresentation {
    OrbitPresentation(state: store.state, suppression: suppression)
  }

  public var menuEntries: [AppMenu.Entry] { AppMenu.entries(isPaused: signals.isPaused) }

  public var menuBarTitle: String {
    AppMenu.barTitle(nowCount: store.state.today?.orbit.nowCount ?? 0)
  }

  // MARK: Lifecycle

  /// Puts the app's content in the expanded client's panel, on the panel's own surface. Surface
  /// does not import Features, so the app passes the view in (ADR 0004).
  public func setExpandedContent<Content: View>(_ content: Content) {
    expandedPanel.contentView = NSHostingView(rootView: ExpandedPanelSurface { content })
  }

  public func start() {
    signals.start()
    orbitPanel.orderFrontRegardless()
    installPointerMonitors()
    if whisperObservation == nil {
      whisperObservations += 1
      whisperObservation = whisperObservations
      observeWhisper(token: whisperObservations)
    }
    observeSystem()
    secureSystemWindows()
  }

  /// Removes the pointer monitors and observers, stops the camera watch and hides every panel.
  public func stop() {
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers = []
    whisperObservation = nil
    whisper.hide()
    stopArming.disarm()
    signals.stop()
    for window in windows { window.orderOut(nil) }
    isHovering = false
  }

  /// Sets `sharingType = .none` on every window the app has, including those AppKit and SwiftUI
  /// make outside the factory: the status item's window and the menus (ADR 0014).
  func secureSystemWindows() {
    for window in NSApplication.shared.windows where window.sharingType != .none {
      window.sharingType = .none
    }
  }

  // MARK: Commands

  public func perform(_ command: AppMenu.Command) {
    switch command {
    case .open: showExpanded()
    case .openSettings:
      showExpanded()
      onOpenSettings?()
    case .togglePause: signals.isPaused.toggle()
    case .quit: quit()
    }
  }

  /// Opens the expanded client once, as soon as the first snapshot is in. `scripts/measure-cpu.sh`
  /// uses it to measure the open panel without a pointer.
  public func showExpandedAfterFirstSnapshot() {
    guard store.state.today == nil else {
      showExpanded()
      return
    }
    withObservationTracking {
      _ = store.state.today
    } onChange: { [weak self] in
      Task { @MainActor in self?.showExpandedAfterFirstSnapshot() }
    }
  }

  /// Opens the expanded client on the view that holds an item.
  public func showItem(_ destination: ItemDestination) {
    showExpanded()
    onShowItem?(destination)
  }

  public func toggleExpanded() {
    if expandedPanel.isVisible { hideExpanded() } else { showExpanded() }
  }

  public func showExpanded() {
    let isOpening = !expandedPanel.isVisible
    if isOpening { expandedOpenedAt = Date().timeIntervalSinceReferenceDate }
    repositionExpanded()
    let entrance = ExpandedEntrance(
      endFrame: expandedPanel.frame,
      reducedMotion: reducesMotion)
    if isOpening {
      expandedPanel.alphaValue = 0
      expandedPanel.setFrame(entrance.startFrame, display: false)
    }
    NSApplication.shared.activate()
    expandedPanel.makeKeyAndOrderFront(nil)
    setExpandedOnScreen(true, path: "showExpanded")
    if isOpening { animate(entrance) }
  }

  private func animate(_ entrance: ExpandedEntrance) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = ExpandedEntrance.fadeDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      expandedPanel.animator().alphaValue = 1
    }
    guard entrance.rises else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = ExpandedEntrance.riseDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      expandedPanel.animator().setFrame(entrance.endFrame, display: true)
    }
  }

  /// Hides the expanded client and gives focus back to the app the principal was in.
  public func hideExpanded() {
    expandedPanel.orderOut(nil)
    expandedPanel.alphaValue = 1
    setExpandedOnScreen(false, path: "hideExpanded")
    NSApplication.shared.deactivate()
  }

  /// Moves the expanded client under its anchor without taking focus.
  private func repositionExpanded() {
    let size = CGSize(
      width: max(expandedPanel.frame.width, OrbitPlacement.expandedMinimumSize.width),
      height: max(expandedPanel.frame.height, OrbitPlacement.expandedMinimumSize.height))
    expandedPanel.setFrame(
      OrbitPlacement.expandedFrame(
        size: size, orbit: orbitPanel.frame, corner: corner, in: screenArea()),
      display: false)
  }

  // MARK: Placement and dragging

  /// Moves the Orbit to `corner`, keeps the expanded client under it, and saves the corner.
  public func setCorner(_ corner: Corner) {
    guard corner != self.corner else { return }
    self.corner = corner
    cornerSetting.corner = corner
    placeOrbit()
    if expandedPanel.isVisible { repositionExpanded() }
    syncHoverPanel()
  }

  private func placeOrbit() {
    orbitPanel.setFrame(OrbitPlacement.orbitFrame(corner: corner, in: screenArea()), display: true)
  }

  private func dragOrbit(to origin: CGPoint) {
    isDragging = true
    hoverPanel.orderOut(nil)
    orbitPanel.setFrameOrigin(origin)
  }

  private func finishDrag() {
    isDragging = false
    let area = screenArea()
    corner = OrbitPlacement.nearestCorner(to: orbitPanel.frame, in: area)
    cornerSetting.corner = corner
    orbitPanel.setFrame(
      OrbitPlacement.orbitFrame(corner: corner, in: area), display: true,
      animate: MotionPreference.glidesToCorner(reducedMotion: reducesMotion))
    if expandedPanel.isVisible { repositionExpanded() }
    updatePointer()
    syncHoverPanel()
  }

  // MARK: Pointer

  /// Opens the Orbit's panel to clicks only while the pointer is over the avatar's circle, and
  /// shows the hover label there. The panel is the avatar's square, so its four corners and
  /// everything outside it already pass clicks through; this closes the gap in the corners.
  private func installPointerMonitors() {
    guard monitors.isEmpty else { return }
    if let global = NSEvent.addGlobalMonitorForEvents(
      matching: [.mouseMoved],
      handler: { [weak self] _ in
        // Global monitors run on the main thread.
        MainActor.assumeIsolated { self?.pointerMoved() }
      })
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: [.mouseMoved],
      handler: { [weak self] event in
        MainActor.assumeIsolated { self?.pointerMoved() }
        return event
      })
    {
      monitors.append(local)
    }
  }

  private func pointerMoved() {
    if let destination = stopArming.pointerMoved(
      isPanelOpen: expandedPanel.isVisible, suppression: suppression)
    {
      showItem(destination)
    }
    updatePointer()
  }

  private func updatePointer() {
    let inside = OrbitPlacement.hitsAvatar(NSEvent.mouseLocation, in: orbitPanel.frame)
    if !isDragging, orbitPanel.ignoresMouseEvents == inside {
      orbitPanel.ignoresMouseEvents = !inside
    }
    guard inside != isHovering, !isDragging else { return }
    isHovering = inside
    syncHoverPanel()
  }

  private func syncHoverPanel() {
    let isWhispering = whisper.title != nil && !suppression.isActive
    guard (isHovering || isWhispering) && !isDragging && hoverLabel != nil else {
      hoverPanel.orderOut(nil)
      return
    }
    let orbit = orbitPanel.frame
    let size = Self.hoverSize
    let x = corner.isRight ? orbit.minX - size.width - Self.hoverGap : orbit.maxX + Self.hoverGap
    hoverPanel.setFrame(
      CGRect(x: x, y: orbit.midY - size.height / 2, width: size.width, height: size.height),
      display: true)
    hoverPanel.orderFrontRegardless()
  }

  /// Shows and hides the hover panel as the whisper starts and ends.
  private func observeWhisper(token: Int) {
    guard whisperObservation == token else { return }
    withObservationTracking {
      _ = whisper.title
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.syncHoverPanel()
        self?.observeWhisper(token: token)
      }
    }
  }

  /// The menu the Orbit opens on right-click and control-click, built from the shared model.
  func makeMenu() -> NSMenu {
    let menu = NSMenu()
    for entry in menuEntries {
      switch entry {
      case .separator:
        menu.addItem(.separator())
      case .command(let command, let title, let isChecked, let shortcut):
        let item = ClosureMenuItem(title: title, keyEquivalent: shortcut.map(String.init) ?? "") {
          [weak self] in self?.perform(command)
        }
        if let isChecked { item.state = isChecked ? .on : .off }
        menu.addItem(item)
      }
    }
    return menu
  }

  /// Escape closes the panel without going through `hideExpanded`, and another window can cover
  /// it, so the panel's own occlusion state decides whether it is on screen.
  private func syncExpandedOnScreen() {
    let onScreen = expandedPanel.isVisible && expandedPanel.occlusionState.contains(.visible)
    setExpandedOnScreen(onScreen, path: "syncExpandedOnScreen")
  }

  private static let motionLog = Logger(subsystem: "ai.valliance.ian.desktop", category: "motion")

  /// Sets `isExpandedOnScreen` and leaves a line in the unified log when the value changes.
  private func setExpandedOnScreen(_ value: Bool, path: StaticString) {
    guard value != isExpandedOnScreen else { return }
    isExpandedOnScreen = value
    Self.motionLog.notice(
      "expanded on screen \(value, privacy: .public), set by \(path, privacy: .public)")
  }

  // MARK: System

  /// Notifications are delivered on the posting thread, which is the main thread for each of
  /// these, so the handlers run at once and `assumeIsolated` holds.
  ///
  /// The window sweep runs when a menu starts tracking and when any window's occlusion state
  /// changes. A window that is newly shown changes state from unknown to visible, so the second
  /// catches system windows (the status item's, the menus') without polling.
  private func observeSystem() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: nil
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.secureSystemWindows()
          self.isOrbitOnScreen = self.orbitPanel.occlusionState.contains(.visible)
          self.syncExpandedOnScreen()
        }
      })
    observers.append(
      center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.secureSystemWindows() }
      })
    observers.append(
      center.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.placeOrbit()
          if self.expandedPanel.isVisible { self.repositionExpanded() }
        }
      })
  }
}

/// A menu item that runs a closure, so the Orbit's menu is built from `AppMenu` without a
/// responder chain.
private final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
    target = self
  }

  required init(coder: NSCoder) {
    fatalError("ClosureMenuItem is built in code.")
  }

  @objc private func run() {
    handler()
  }
}
