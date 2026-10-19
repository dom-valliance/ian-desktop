import Foundation
import Observation
import Surface

/// The expanded client's pane sizes and the field's angle: what a divider or a turn changes, and
/// what survives a relaunch (ADR 0016). Sizes are kept as the principal dragged them and clamped
/// to the room there is each time they are used, so a window that shrinks and grows again gives
/// the panes back.
@MainActor
@Observable
final class PaneLayout {
  private var sidebarWidth: Double
  private var fieldHeight: Double
  /// The saved angle, read once when the field is built. The field owns the angle while it
  /// turns, so views do not observe this.
  @ObservationIgnored private(set) var angle: Double
  @ObservationIgnored private let settings: ClientLayoutSettings

  init(settings: ClientLayoutSettings) {
    self.settings = settings
    sidebarWidth = settings.sidebarWidth
    fieldHeight = settings.fieldHeight
    angle = settings.angle
  }

  func sidebarWidth(containerWidth: Double) -> Double {
    PaneLimits.sidebarWidth(sidebarWidth, containerWidth: containerWidth)
  }

  func fieldHeight(containerHeight: Double) -> Double {
    PaneLimits.fieldHeight(fieldHeight, containerHeight: containerHeight)
  }

  func resizeSidebar(to proposed: Double, containerWidth: Double) {
    sidebarWidth = PaneLimits.sidebarWidth(proposed, containerWidth: containerWidth)
  }

  func resizeField(to proposed: Double, containerHeight: Double) {
    fieldHeight = PaneLimits.fieldHeight(proposed, containerHeight: containerHeight)
  }

  /// Saves both divider positions, when a drag lets go.
  func commitPanes() {
    settings.sidebarWidth = sidebarWidth
    settings.fieldHeight = fieldHeight
  }

  func commitAngle(_ degrees: Double) {
    angle = FieldTurn.normalised(degrees)
    settings.angle = angle
  }
}
