import Attention
import Foundation
import Observation

/// The client settings of spec 6.4 that are not the corner or the environment: motion, the level
/// per attention rung and the two suppression toggles. Each is saved the moment it changes and
/// read back when the app launches. The corner is `CornerSetting`, the environment profile is
/// `EnvironmentProfile.defaultsKey`, and launch at login is the system's to remember.
@MainActor
@Observable
public final class ClientSettings {
  public static let reducedMotionKey = "IanReducedMotion"
  public static let suppressOnCameraKey = "IanSuppressOnCamera"
  public static let suppressInExternalMeetingKey = "IanSuppressInExternalMeeting"

  /// The principal chose reduced motion. The system's Reduce Motion forces it on regardless.
  public private(set) var reducedMotion: Bool
  public private(set) var suppressOnCamera: Bool
  public private(set) var suppressInExternalMeeting: Bool
  public private(set) var notificationLevels: [NotificationRung: NotificationLevel]

  @ObservationIgnored private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    reducedMotion = defaults.bool(forKey: Self.reducedMotionKey)
    suppressOnCamera = defaults.object(forKey: Self.suppressOnCameraKey) as? Bool ?? true
    suppressInExternalMeeting =
      defaults.object(forKey: Self.suppressInExternalMeetingKey) as? Bool ?? true
    notificationLevels = Dictionary(
      uniqueKeysWithValues: NotificationRung.allCases.map { rung in
        let saved = rung.defaultsKey.flatMap { defaults.string(forKey: $0) }
        return (rung, saved.flatMap(NotificationLevel.init(rawValue:)) ?? rung.defaultLevel)
      })
  }

  public var suppressionToggles: SuppressionToggles {
    SuppressionToggles(camera: suppressOnCamera, externalMeeting: suppressInExternalMeeting)
  }

  public func level(for rung: NotificationRung) -> NotificationLevel {
    notificationLevels[rung] ?? rung.defaultLevel
  }

  public func setReducedMotion(_ value: Bool) {
    reducedMotion = value
    defaults.set(value, forKey: Self.reducedMotionKey)
  }

  public func setSuppressOnCamera(_ value: Bool) {
    suppressOnCamera = value
    defaults.set(value, forKey: Self.suppressOnCameraKey)
  }

  public func setSuppressInExternalMeeting(_ value: Bool) {
    suppressInExternalMeeting = value
    defaults.set(value, forKey: Self.suppressInExternalMeetingKey)
  }

  /// Stop always notifies (spec 6.6), so a level for it is ignored.
  public func setLevel(_ level: NotificationLevel, for rung: NotificationRung) {
    guard let key = rung.defaultsKey else { return }
    notificationLevels[rung] = level
    defaults.set(level.rawValue, forKey: key)
  }
}
