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
      .background(
        ResizeCursor(cursor: direction == .vertical ? .resizeLeftRight : .resizeUpDown)
      )
      // Global coordinates, because the divider moves under the pointer as it drags and a local
      // translation would feed back on itself.
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .updating($isDragging) { _, state, _ in state = true }
          .onChanged { drag in
            let origin = startValue ?? value()
            startValue = origin
            let travel = direction == .vertical ? drag.translation.width : drag.translation.height
            onChange(origin + travel)
          }
          .onEnded { _ in
            startValue = nil
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

/// Asks the window for a cursor over the view's bounds. A cursor rect is the system's own
/// mechanism, so it cannot stick when the panel hides mid-hover, and it does not drop when a
/// drag stops at a limit.
private struct ResizeCursor: NSViewRepresentable {
  let cursor: NSCursor

  func makeNSView(context: Context) -> CursorView { CursorView(cursor: cursor) }
  func updateNSView(_ view: CursorView, context: Context) { view.cursor = cursor }

  final class CursorView: NSView {
    var cursor: NSCursor {
      didSet { window?.invalidateCursorRects(for: self) }
    }

    init(cursor: NSCursor) {
      self.cursor = cursor
      super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Not used.") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override func viewDidMoveToWindow() { window?.invalidateCursorRects(for: self) }
    override func layout() {
      super.layout()
      window?.invalidateCursorRects(for: self)
    }
    // Clicks and drags belong to the SwiftUI gesture above this view.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }
}
