import Observation

/// Today's keyboard path into the selection footer, which works with macOS's Keyboard navigation
/// setting off. With a row selected, Return enters an action mode; Left and Right move a visible
/// highlight across the footer's targets in the order sent, wrapping at both ends; Return acts on
/// the highlighted one; Escape returns to the row. A target is an action, a member item of a
/// week group or a count of a later group. This holds only the logic, so it is tested without a
/// view; the keys themselves are bound in `TodayView` and the highlight is drawn by the footer.
@MainActor
@Observable
final class FooterKeys {
  private(set) var isActive = false
  private(set) var highlighted = 0
  /// Rises each time Return acts on the highlighted target. The view that owns the target
  /// watches it.
  private(set) var activations = 0
  private(set) var targetCount = 0
  /// A note, time, confirm or hand-off prompt is open, and it owns Return and Escape.
  var isPromptOpen = false

  /// Return does something: there is a target, and no prompt wants the key.
  var handlesReturn: Bool { !isPromptOpen && targetCount > 0 }

  func setTargetCount(_ count: Int) {
    targetCount = count
    if count == 0 {
      exit()
    } else if highlighted >= count {
      highlighted = count - 1
    }
  }

  /// Enters the mode on the first target, or acts on the highlighted one when already in it.
  func pressReturn() {
    guard handlesReturn else { return }
    if isActive {
      activations += 1
    } else {
      isActive = true
      highlighted = 0
    }
  }

  /// Moves the highlight by `step` targets, wrapping.
  func move(_ step: Int) {
    guard isActive, targetCount > 0 else { return }
    highlighted = ((highlighted + step) % targetCount + targetCount) % targetCount
  }

  /// Returns to the row. Reports whether the key was used.
  @discardableResult
  func pressEscape() -> Bool {
    guard isActive else { return false }
    exit()
    return true
  }

  func exit() {
    isActive = false
    highlighted = 0
  }
}
