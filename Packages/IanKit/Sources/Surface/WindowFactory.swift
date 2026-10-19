import AppKit

/// The one place Ian's windows are made (ADR 0005, 0006). Every panel gets `sharingType = .none`
/// here, so no window is missed and Settings has nothing to switch off.
@MainActor
public enum WindowFactory {
  /// The Orbit: borderless, never key, floating over every Space and full-screen apps,
  /// transparent and shadowless.
  public static func makeOrbitPanel(content: NSView) -> NSPanel {
    let panel = make(
      OrbitPanel.self, style: [.borderless, .nonactivatingPanel],
      frame: CGRect(
        x: 0, y: 0, width: OrbitPlacement.avatarSize, height: OrbitPlacement.avatarSize),
      content: content)
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    return panel
  }

  /// The hover label beside the Orbit. It takes no mouse events.
  public static func makeHoverPanel(content: NSView, size: CGSize) -> NSPanel {
    let panel = make(
      OrbitPanel.self, style: [.borderless, .nonactivatingPanel],
      frame: CGRect(origin: .zero, size: size), content: content)
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    return panel
  }

  /// The expanded client: it can become key so text fields take input, and Escape closes it.
  public static func makeExpandedPanel(content: NSView) -> NSPanel {
    let panel = make(
      ExpandedPanel.self, style: [.borderless, .resizable],
      frame: CGRect(origin: .zero, size: OrbitPlacement.expandedDefaultSize), content: content)
    panel.minSize = OrbitPlacement.expandedMinimumSize
    panel.hasShadow = true
    return panel
  }

  private static func make<Panel: NSPanel>(
    _ type: Panel.Type, style: NSWindow.StyleMask, frame: CGRect, content: NSView
  ) -> Panel {
    let panel = Panel(contentRect: frame, styleMask: style, backing: .buffered, defer: true)
    panel.contentView = content
    panel.sharingType = .none
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    return panel
  }
}

/// A borderless panel returns false from `canBecomeKey` already; it is stated so that stays true.
private final class OrbitPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private final class ExpandedPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    orderOut(sender)
  }
}
