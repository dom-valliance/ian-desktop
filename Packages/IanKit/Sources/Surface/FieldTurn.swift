import CoreGraphics
import Foundation

/// How the principal turns the Pillars field by hand. Pure arithmetic and a small state
/// machine, tested without a view. The tilt never changes; only the angle about the vertical
/// axis does.
public enum FieldTurn {
  /// The design's resting angle, which a double-click returns to.
  public static let defaultAngle = 45.0
  /// Degrees the field turns for each point the pointer moves sideways: a full turn takes 720
  /// points.
  public static let degreesPerPoint = 0.5
  /// Movement below this many points is a click, not a drag.
  public static let dragThreshold = 4.0
  /// The longest gap between two clicks that makes a double-click.
  public static let doubleClickInterval: TimeInterval = 0.4
  /// How far the second click of a double-click may land from the first.
  static let doubleClickSlop = 8.0

  /// Dragging right grabs the plate and moves it right, so the front edge travels right. The
  /// front edge moves left as the angle grows, so a rightward drag lowers the angle.
  public static func angle(from start: Double, translation: Double) -> Double {
    normalised(start - degreesPerPoint * translation)
  }

  /// `degrees` in `0..<360`.
  public static func normalised(_ degrees: Double) -> Double {
    let wrapped = degrees.truncatingRemainder(dividingBy: 360)
    return wrapped < 0 ? wrapped + 360 : wrapped
  }
}

/// One pointer on the field: a drag turns it, a click selects a pillar, and a second click soon
/// after the first returns the field to its resting angle.
public struct FieldPointer: Equatable, Sendable {
  public enum Outcome: Equatable, Sendable {
    /// A drag finished; the angle is already where the principal left it.
    case turned
    /// A click, at this point in the field's own coordinates.
    case select(CGPoint)
    /// A double-click.
    case reset
  }

  public private(set) var angle: Double
  private var start: Double?
  private var isDragging = false
  private struct Click: Equatable, Sendable {
    let time: TimeInterval
    let location: CGPoint
  }

  private var lastClick: Click?

  public init(angle: Double = FieldTurn.defaultAngle) {
    self.angle = FieldTurn.normalised(angle)
  }

  /// Follows the pointer while it is down. Nothing turns until it has moved past the click
  /// threshold, and once it has, the gesture stays a drag.
  public mutating func changed(translation: CGSize) {
    let origin = start ?? angle
    start = origin
    if hypot(translation.width, translation.height) >= FieldTurn.dragThreshold {
      isDragging = true
    }
    if isDragging {
      angle = FieldTurn.angle(from: origin, translation: translation.width)
    }
  }

  /// Ends the gesture and says what it was. The second click of a double-click resets the angle
  /// and selects nothing; the first click has already selected.
  public mutating func ended(location: CGPoint, time: TimeInterval) -> Outcome {
    defer {
      start = nil
      isDragging = false
    }
    if isDragging {
      lastClick = nil
      return .turned
    }
    if let previous = lastClick, time - previous.time <= FieldTurn.doubleClickInterval,
      hypot(location.x - previous.location.x, location.y - previous.location.y)
        <= FieldTurn.doubleClickSlop
    {
      lastClick = nil
      angle = FieldTurn.defaultAngle
      return .reset
    }
    lastClick = Click(time: time, location: location)
    return .select(location)
  }
}
