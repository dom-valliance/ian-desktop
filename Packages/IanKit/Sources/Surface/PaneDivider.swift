import AppKit
import SwiftUI

/// The line between two panes, with a wider strip either side that takes a drag. The line keeps
/// its one point of layout; the strip is an overlay. Rank the divider above the panes it sits
/// between (`zIndex`) in the stack that holds them all, or the strip's far half is covered.
public struct PaneDivider: View {
  public enum Direction: Sendable {
    /// Between panes side by side; dragging moves it sideways.
    case vertical
    /// Between panes one above the other; dragging moves it up and down.
    case horizontal
  }

  static let grabWidth: CGFloat = 9

  private let direction: Direction
  private let colour: Color
  private let value: () -> Double
  private let onChange: (Double) -> Void
  private let onEnd: () -> Void

  @State private var startValue: Double?
  /// True while a drag is live. SwiftUI resets it when a drag is cancelled, which `onEnded`
  /// never reports, so a change to false clears the remembered start.
  @GestureState private var isDragging = false
  /// Whether the pointer is over the strip, tracked through a drag so the arrow can come back
  /// when the drag lets go outside it.
  @State private var isHovering = false

  /// `value` is the size of the pane the divider resizes. `onChange` receives that size as the
  /// drag moves it, and `onEnd` fires when the drag lets go.
  public init(
    direction: Direction, colour: Color, value: @escaping () -> Double,
    onChange: @escaping (Double) -> Void, onEnd: @escaping () -> Void
  ) {
    self.direction = direction
    self.colour = colour
    self.value = value
    self.onChange = onChange
    self.onEnd = onEnd
  }

  public var body: some View {
    line
      .overlay { grabStrip }
      .zIndex(1)
  }

  private var resizeCursor: NSCursor {
    direction == .vertical ? .resizeLeftRight : .resizeUpDown
  }

  @ViewBuilder private var line: some View {
    switch direction {
    case .vertical: colour.frame(width: 1)
    case .horizontal: colour.frame(height: 1)
    }
  }

  private var grabStrip: some View {
    Color.clear
      .frame(
        width: direction == .vertical ? Self.grabWidth : nil,
        height: direction == .horizontal ? Self.grabWidth : nil
      )
      .contentShape(Rectangle())
      .background(ResizeCursor(cursor: resizeCursor))
      // The hosting view may reset the arrow when the pointer moves, so the cursor is set again
      // on every move over the strip.
      .onContinuousHover { phase in
        switch phase {
        case .active:
          isHovering = true
          resizeCursor.set()
        case .ended:
          isHovering = false
          if !isDragging { NSCursor.arrow.set() }
        }
      }
      // Global coordinates, because the divider moves under the pointer as it drags and a local
      // translation would feed back on itself.
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .updating($isDragging) { _, state, _ in state = true }
          .onChanged { drag in
            // Held through the drag, so it stays when the drag stops at a pane limit.
            resizeCursor.set()
            let origin = startValue ?? value()
            startValue = origin
            let travel = direction == .vertical ? drag.translation.width : drag.translation.height
            onChange(origin + travel)
          }
          .onEnded { _ in
            startValue = nil
            if !isHovering { NSCursor.arrow.set() }
            onEnd()
          }
      )
      .onChange(of: isDragging) { _, dragging in
        if !dragging { startValue = nil }
      }
      // The lists remain the accessible path; resizing is a pointer convenience.
      .accessibilityHidden(true)
  }
}

/// Keeps the resize cursor over the view's bounds with a tracking area, which the SwiftUI
/// hosting view's own cursor handling does not reset the way it does cursor rects. It is a
/// second line of defence beside the strip's hover handler.
struct ResizeCursor: NSViewRepresentable {
  let cursor: NSCursor

  func makeNSView(context: Context) -> ResizeCursorView { ResizeCursorView(cursor: cursor) }
  func updateNSView(_ view: ResizeCursorView, context: Context) { view.cursor = cursor }
}

final class ResizeCursorView: NSView {
  static let trackingOptions: NSTrackingArea.Options = [
    .cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect,
  ]

  var cursor: NSCursor

  init(cursor: NSCursor) {
    self.cursor = cursor
    super.init(frame: .zero)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Not used.") }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(rect: .zero, options: Self.trackingOptions, owner: self, userInfo: nil))
  }

  override func cursorUpdate(with event: NSEvent) { cursor.set() }
  override func mouseEntered(with event: NSEvent) { cursor.set() }
  // Clicks and drags belong to the SwiftUI gesture above this view.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
