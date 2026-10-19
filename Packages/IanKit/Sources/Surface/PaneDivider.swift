import AppKit
import SwiftUI

/// The line between two panes, with a wider strip either side that takes a drag. The line keeps
/// its one point of layout; the strip is an overlay.
public struct PaneDivider: View {
  public enum Direction: Sendable {
    /// Between panes side by side; dragging moves it sideways.
    case vertical
    /// Between panes one above the other; dragging moves it up and down.
    case horizontal
  }

  private static let grabWidth: CGFloat = 9

  private let direction: Direction
  private let colour: Color
  private let value: () -> Double
  private let onChange: (Double) -> Void
  private let onEnd: () -> Void

  @State private var startValue: Double?
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
      .onDisappear { if isHovering { NSCursor.pop() } }
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
      .onHover { inside in
        guard inside != isHovering else { return }
        isHovering = inside
        if inside {
          (direction == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
        } else {
          NSCursor.pop()
        }
      }
      // Global coordinates, because the divider moves under the pointer as it drags and a local
      // translation would feed back on itself.
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
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
      // The lists remain the accessible path; resizing is a pointer convenience.
      .accessibilityHidden(true)
  }
}
