import CoreGraphics
import Foundation

/// What the expanded client remembers about its layout: the field's angle and the two divider
/// positions. With the corner, these are the settings spec 6.4 lets reach disk (ADR 0016).
public struct ClientLayoutSettings {
  public static let angleKey = "IanFieldAngle"
  public static let sidebarWidthKey = "IanSidebarWidth"
  public static let fieldHeightKey = "IanFieldHeight"

  public static let defaultSidebarWidth = 190.0
  public static let defaultFieldHeight = 300.0

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The field's angle in degrees, `0..<360`. 45 when none is saved.
  public var angle: Double {
    get { stored(Self.angleKey).map(FieldTurn.normalised) ?? FieldTurn.defaultAngle }
    nonmutating set {
      guard newValue.isFinite else { return }
      defaults.set(FieldTurn.normalised(newValue), forKey: Self.angleKey)
    }
  }

  /// The sidebar's width in points. The panes clamp it to their limits when they lay out.
  public var sidebarWidth: Double {
    get { stored(Self.sidebarWidthKey, positive: true) ?? Self.defaultSidebarWidth }
    nonmutating set {
      guard newValue.isFinite else { return }
      defaults.set(newValue, forKey: Self.sidebarWidthKey)
    }
  }

  /// The field pane's height in points. The panes clamp it to their limits when they lay out.
  public var fieldHeight: Double {
    get { stored(Self.fieldHeightKey, positive: true) ?? Self.defaultFieldHeight }
    nonmutating set {
      guard newValue.isFinite else { return }
      defaults.set(newValue, forKey: Self.fieldHeightKey)
    }
  }

  /// A saved number, or nil when it is absent, not a finite number, or (if `positive`) not
  /// above zero.
  private func stored(_ key: String, positive: Bool = false) -> Double? {
    guard let value = defaults.object(forKey: key) as? Double, value.isFinite else { return nil }
    return positive && value <= 0 ? nil : value
  }
}

/// The expanded client's pane sizes. A pane never shrinks below its minimum, and the panes it
/// leaves room for do not either, so a divider stops where the next pane would be too small.
public enum PaneLimits {
  public static let sidebarMinimum = 160.0
  /// The width the right-hand panes keep.
  public static let contentMinimumWidth = 480.0
  public static let sidebarMaximumWidth = 320.0
  public static let fieldMinimumHeight = 180.0
  /// The height the lists and the footer keep.
  public static let listsMinimumHeight = 220.0

  public static func sidebarWidth(_ proposed: Double, containerWidth: Double) -> Double {
    clamp(
      proposed, minimum: sidebarMinimum,
      maximum: min(sidebarMaximumWidth, containerWidth - contentMinimumWidth))
  }

  public static func fieldHeight(_ proposed: Double, containerHeight: Double) -> Double {
    clamp(
      proposed, minimum: fieldMinimumHeight, maximum: containerHeight - listsMinimumHeight)
  }

  /// When the room is smaller than the minimum, the minimum wins.
  private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
    max(minimum, min(maximum, value))
  }
}
