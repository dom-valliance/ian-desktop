import AppKit
import SwiftUI

@testable import Surface

/// The Orbit drawn through the renderer the app uses, at a fixed time, on the ground colour.
@MainActor
enum OrbitImage {
  static let scale: CGFloat = 2

  static func of(_ model: OrbitModel, time: Double, reducedMotion: Bool) -> NSImage {
    let drawing = OrbitRenderer.drawing(for: model, time: time, reducedMotion: reducedMotion)
    let view = OrbitDrawingView(drawing: drawing)
      .frame(width: OrbitPlacement.avatarSize, height: OrbitPlacement.avatarSize)
      .background(OrbitPalette.ground.color)
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage else {
      preconditionFailure("The Orbit did not render to an image.")
    }
    return image
  }
}
