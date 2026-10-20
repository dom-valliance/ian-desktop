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
      held.contentView = hosting
      held.appearance = hosting.appearance
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
      preconditionFailure("The view did not produce a bitmap.")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window?.contentView = nil
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
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
