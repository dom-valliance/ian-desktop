import AppKit
import Testing

@testable import Surface

/// These check the plumbing only. That the pointer changes over a divider is proved by hand.
@Suite("Resize cursor")
@MainActor
struct ResizeCursorTests {
  private func event() throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
  }

  @Test("installs one tracking area that works without the app active")
  func installsTrackingArea() throws {
    let view = ResizeCursorView(cursor: .resizeLeftRight)
    view.updateTrackingAreas()
    view.updateTrackingAreas()
    let area = try #require(view.trackingAreas.first)
    #expect(view.trackingAreas.count == 1)
    #expect(area.options == [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect])
    #expect(area.owner === view)
  }

  @Test("sets its cursor on a cursor update and on entering")
  func setsTheCursor() throws {
    let view = ResizeCursorView(cursor: .resizeUpDown)
    NSCursor.arrow.set()
    view.cursorUpdate(with: try event())
    #expect(NSCursor.current == .resizeUpDown)
    NSCursor.arrow.set()
    view.mouseEntered(with: try event())
    #expect(NSCursor.current == .resizeUpDown)
    NSCursor.arrow.set()
  }

  @Test("lets clicks through to the gesture above it")
  func passesClicksThrough() {
    #expect(ResizeCursorView(cursor: .arrow).hitTest(.zero) == nil)
  }
}
