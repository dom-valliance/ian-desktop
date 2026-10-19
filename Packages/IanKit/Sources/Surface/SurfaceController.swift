import AppKit
import Attention
import Observation
import Store
import SwiftUI

/// Owns the app's windows and everything that reacts to the pointer: the Orbit, its hover label
/// and the expanded client (ADR 0005). Nothing here decides what an item is; it draws the
/// presentation the store and suppression give it.
@MainActor
@Observable
public final class SurfaceController {
  private static let hoverSize = CGSize(width: 320, height: 30)
  private static let hoverGap: CGFloat = 8

  public private(set) var corner: Corner
  /// False once the Orbit's panel is fully covered or off screen. The clock stops then.
  public private(set) var isOrbitOnScreen = true
  /// The spec 6.4 motion setting. The system's Reduce Motion forces reduced regardless.
  public var reducedMotionSetting: Bool

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
  @ObservationIgnored private var monitors: [Any] = []
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []

  /// - Parameters:
  ///   - screenArea: The visible frame of the main display, which is where the Orbit sits.
  ///   - quit: What "Quit Ian" does.
  public init(
    store: IanStore,
    signals: SuppressionSignals,
    defaults: UserDefaults = .standard,
    reducedMotionSetting: Bool = false,
    screenArea: @escaping @MainActor () -> CGRect = {
      (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame
        ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    },
    quit: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
  ) {
    self.store = store
    self.signals = signals
    self.cornerSetting = CornerSetting(defaults: defaults)
    self.corner = CornerSetting(defaults: defaults).corner
    self.reducedMotionSetting = reducedMotionSetting
    self.screenArea = screenArea
    self.quit = quit

    let host = OrbitHostView(content: OrbitRootView(controller: self))
    host.onClick = { [weak self] in self?.toggleExpanded() }
    host.onDrag = { [weak self] origin in self?.dragOrbit(to: origin) }
    host.onDragEnd = { [weak self] in self?.finishDrag() }
    host.onContextMenu = { [weak self] event, view in self?.showMenu(event: event, in: view) }
    orbitPanel.contentView = host
    hoverPanel.contentView = NSHostingView(rootView: HoverLabelView(controller: self))
    expandedPanel.contentView = NSHostingView(rootView: ExpandedPlaceholderView())
    placeOrbit()
  }

  // MARK: State read by the views

  /// Every window this controller opens, which tests check for `sharingType`.
  public var windows: [NSWindow] { [orbitPanel, hoverPanel, expandedPanel] }

  public var isExpandedVisible: Bool { expandedPanel.isVisible }

  public var suppression: Suppression {
    let context = store.state.today?.context
    return signals.suppression(
      externalMeeting: context?.inExternalMeeting ?? false,
      quietHours: context?.quietHoursActive ?? false)
  }

  public var presentation: OrbitPresentation {
    OrbitPresentation(state: store.state, suppression: suppression)
  }

  public var menuEntries: [AppMenu.Entry] { AppMenu.entries(isPaused: signals.isPaused) }

  public var menuBarTitle: String { AppMenu.barTitle(nowCount: presentation.nowCount) }

  // MARK: Lifecycle

  public func start() {
    signals.start()
    orbitPanel.orderFrontRegardless()
    installPointerMonitors()
    observeSystem()
  }

  // MARK: Commands

  public func perform(_ command: AppMenu.Command) {
    switch command {
    case .open, .openSettings: showExpanded()
    case .togglePause: signals.isPaused.toggle()
    case .quit: quit()
    }
  }

  public func toggleExpanded() {
    if expandedPanel.isVisible { hideExpanded() } else { showExpanded() }
  }

  public func showExpanded() {
    let size = CGSize(
      width: max(expandedPanel.frame.width, OrbitPlacement.expandedMinimumSize.width),
      height: max(expandedPanel.frame.height, OrbitPlacement.expandedMinimumSize.height))
    expandedPanel.setFrame(
      OrbitPlacement.expandedFrame(
        size: size, orbit: orbitPanel.frame, corner: corner, in: screenArea()),
      display: false)
    NSApplication.shared.activate()
    expandedPanel.makeKeyAndOrderFront(nil)
  }

  public func hideExpanded() {
    expandedPanel.orderOut(nil)
  }

  // MARK: Placement and dragging

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
      OrbitPlacement.orbitFrame(corner: corner, in: area), display: true, animate: true)
    if expandedPanel.isVisible { showExpanded() }
    updatePointer()
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
        MainActor.assumeIsolated { self?.updatePointer() }
      })
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: [.mouseMoved],
      handler: { [weak self] event in
        MainActor.assumeIsolated { self?.updatePointer() }
        return event
      })
    {
      monitors.append(local)
    }
  }

  private func updatePointer() {
    let inside = OrbitPlacement.hitsAvatar(NSEvent.mouseLocation, in: orbitPanel.frame)
    if !isDragging { orbitPanel.ignoresMouseEvents = !inside }
    guard inside != isHovering, !isDragging else { return }
    isHovering = inside
    syncHoverPanel()
  }

  private func syncHoverPanel() {
    guard isHovering, presentation.hoverText != nil else {
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

  private func showMenu(event: NSEvent, in view: NSView) {
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
    NSMenu.popUpContextMenu(menu, with: event, for: view)
  }

  // MARK: System

  private func observeSystem() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification, object: orbitPanel, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.isOrbitOnScreen = self.orbitPanel.occlusionState.contains(.visible)
        }
      })
    observers.append(
      center.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.placeOrbit()
          if self.expandedPanel.isVisible { self.showExpanded() }
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
