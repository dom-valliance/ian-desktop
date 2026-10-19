import AppKit
import SwiftUI

/// The Orbit panel's content view. It owns the pointer: a click toggles the expanded client, a
/// drag moves the Orbit, a right-click or control-click opens the menu. Only the avatar's circle takes events.
///
/// SwiftUI draws the avatar and carries its accessibility; this view sits above it and answers
/// the mouse, so no gesture recogniser competes with the drag.
@MainActor
final class OrbitHostView: NSView {
  private static let dragThreshold: CGFloat = 4

  var onClick: () -> Void = {}
  var onDrag: (CGPoint) -> Void = { _ in }
  var onDragEnd: () -> Void = {}
  var menuProvider: () -> NSMenu? = { nil }

  private var pressedAt: CGPoint?
  private var originAtPress: CGPoint = .zero
  private var isDragging = false

  init(content: some View) {
    super.init(frame: CGRect(origin: .zero, size: CGSize(width: 96, height: 96)))
    let hosting = NSHostingView(rootView: content)
    hosting.frame = bounds
    hosting.autoresizingMask = [.width, .height]
    addSubview(hosting)
  }

  required init?(coder: NSCoder) {
    fatalError("OrbitHostView is built in code.")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let local = convert(point, from: superview)
    return OrbitPlacement.hitsAvatar(local, in: bounds) ? self : nil
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    menuProvider()
  }

  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control) {
      // A control-click is a right-click, but only `super` would open the menu for it.
      if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
      return
    }
    pressedAt = NSEvent.mouseLocation
    originAtPress = window?.frame.origin ?? .zero
    isDragging = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let pressedAt else { return }
    let now = NSEvent.mouseLocation
    let dx = now.x - pressedAt.x
    let dy = now.y - pressedAt.y
    if !isDragging {
      guard hypot(dx, dy) >= Self.dragThreshold else { return }
      isDragging = true
    }
    onDrag(CGPoint(x: originAtPress.x + dx, y: originAtPress.y + dy))
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      pressedAt = nil
      isDragging = false
    }
    if isDragging {
      onDragEnd()
    } else if pressedAt != nil {
      onClick()
    }
  }
}
