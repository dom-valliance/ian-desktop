import CoreGraphics
import Foundation

/// The four corners the Orbit snaps to. The raw value is what `UserDefaults` holds.
public enum Corner: String, CaseIterable, Sendable {
  case topLeft, topRight, bottomLeft, bottomRight

  var isRight: Bool { self == .topRight || self == .bottomRight }
  var isTop: Bool { self == .topLeft || self == .topRight }
}

/// Where the Orbit and the expanded client sit. Frames use AppKit's coordinates: the origin is
/// the bottom left of the screen and y grows upward. Pure geometry, tested without a screen.
public enum OrbitPlacement {
  public static let avatarSize: CGFloat = 96
  /// The distance from the display's usable edge (spec 6.1).
  public static let inset: CGFloat = 16
  /// The gap between the Orbit and the expanded client.
  public static let gap: CGFloat = 12

  public static let expandedDefaultSize = CGSize(width: 1040, height: 720)
  public static let expandedMinimumSize = CGSize(width: 880, height: 600)

  /// The Orbit's frame in `corner` of `area`, the display's visible frame.
  public static func orbitFrame(corner: Corner, in area: CGRect) -> CGRect {
    let x = corner.isRight ? area.maxX - inset - avatarSize : area.minX + inset
    let y = corner.isTop ? area.maxY - inset - avatarSize : area.minY + inset
    return CGRect(x: x, y: y, width: avatarSize, height: avatarSize)
  }

  /// The corner nearest to an Orbit frame: the quadrant of `area` its centre is in.
  public static func nearestCorner(to orbit: CGRect, in area: CGRect) -> Corner {
    let right = orbit.midX >= area.midX
    let top = orbit.midY >= area.midY
    switch (top, right) {
    case (true, true): return .topRight
    case (true, false): return .topLeft
    case (false, true): return .bottomRight
    case (false, false): return .bottomLeft
    }
  }

  /// The expanded client's frame, on the Orbit's side of the display and clear of the Orbit,
  /// kept inside `area`. A display smaller than the client shrinks it to fit.
  public static func expandedFrame(
    size: CGSize = expandedDefaultSize, orbit: CGRect, corner: Corner, in area: CGRect
  ) -> CGRect {
    let width = min(size.width, area.width - 2 * inset)
    let height = min(size.height, area.height - 2 * inset - avatarSize - gap)
    let x = corner.isRight ? orbit.maxX - width : orbit.minX
    let y = corner.isTop ? orbit.minY - gap - height : orbit.maxY + gap
    return CGRect(
      x: min(max(x, area.minX + inset), area.maxX - inset - width),
      y: min(max(y, area.minY + inset), area.maxY - inset - height),
      width: width, height: height)
  }

  /// Whether a point lies in the avatar's circle, the only part of the Orbit's panel that takes
  /// clicks. The panel is the avatar's square, so its four corners pass clicks through.
  public static func hitsAvatar(_ point: CGPoint, in frame: CGRect) -> Bool {
    let radius = frame.width / 2
    let dx = point.x - frame.midX
    let dy = point.y - frame.midY
    return dx * dx + dy * dy <= radius * radius
  }
}

/// The remembered corner, the one placement setting in spec 6.4.
public struct CornerSetting {
  public static let defaultsKey = "IanOrbitCorner"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The saved corner, or bottom right when none is saved or the value is unknown.
  public var corner: Corner {
    get {
      defaults.string(forKey: Self.defaultsKey).flatMap(Corner.init(rawValue:)) ?? .bottomRight
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Self.defaultsKey) }
  }
}
