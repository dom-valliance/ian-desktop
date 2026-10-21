import AppKit
import SnapshotTesting
import SwiftUI

@testable import Features

/// How the Features snapshots draw a view: in an `NSHostingView` that never enters a window,
/// since pickers and fields are AppKit controls that `ImageRenderer` would draw as placeholders.
/// The size, the dark appearance and the comparison tolerances are the same for every suite.
@MainActor
enum SnapshotHarness {
  static let panelSize = CGSize(width: 640, height: 720)

  /// - Parameter inWindow: Holds the view in a window that is never ordered on screen. A `List`
  ///   draws no rows until it has one.
  static func image(
    of view: some View, size: CGSize = panelSize, inWindow: Bool = false
  ) -> NSImage {
    // The scroller style follows a system setting, so a list draws none.
    let hosting = NSHostingView(
      rootView: view.scrollIndicators(.hidden).frame(width: size.width, height: size.height)
        .background(ClientPalette.ground).foregroundStyle(ClientPalette.text)
        .environment(\.colorScheme, .dark)
        .environment(\.reduceMotionReading, false))
    hosting.appearance = NSAppearance(named: .darkAqua)
    hosting.frame = CGRect(origin: .zero, size: size)
    var window: NSWindow?
    if inWindow {
      _ = NSApplication.shared
      let held = NSWindow(
        contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: true)
      window = held
      held.sharingType = .none
      held.contentView = hosting
      held.appearance = hosting.appearance
      waitForRows(in: hosting)
    }
    removeScrollerGutters(in: hosting)
    hosting.layoutSubtreeIfNeeded()
    if inWindow { waitForRows(in: hosting) }
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
      preconditionFailure("The view did not produce a bitmap.")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window?.contentView = nil
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }

  /// Steps the run loop in short slices until every table the view hosts has drawn a row, so a
  /// loaded machine gets the time it needs and a fast one does not wait. It stops the test
  /// with a message when no table has its rows by the deadline.
  private static func waitForRows(in view: NSView, deadline: TimeInterval = 5) {
    let limit = Date(timeIntervalSinceNow: deadline)
    while Date() < limit {
      view.layoutSubtreeIfNeeded()
      let tables = tableViews(in: view)
      if !tables.isEmpty,
        tables.allSatisfy({
          $0.numberOfRows > 0 && $0.rowView(atRow: 0, makeIfNecessary: false) != nil
        })
      {
        return
      }
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    preconditionFailure(
      "The hosted List drew no rows within \(Int(deadline)) seconds, so the snapshot would be blank."
    )
  }

  /// Forces every hosted scroll view to overlay scrollers with none shown, so no gutter is
  /// reserved whatever the machine's scroller style or however late SwiftUI applies
  /// `.scrollIndicators(.hidden)`. The reference images were recorded without a gutter.
  private static func removeScrollerGutters(in view: NSView) {
    for subview in view.subviews {
      if let scrollView = subview as? NSScrollView {
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.tile()
      }
      removeScrollerGutters(in: subview)
    }
  }

  private static func tableViews(in view: NSView) -> [NSTableView] {
    view.subviews.flatMap { subview in
      (subview as? NSTableView).map { [$0] } ?? tableViews(in: subview)
    }
  }

  static func check(
    _ image: NSImage, named name: String, testName: String, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    assertSnapshot(
      of: image, as: .image(precision: 0.998, perceptualPrecision: 0.98), named: name,
      file: file, testName: testName, line: line)
  }
}
