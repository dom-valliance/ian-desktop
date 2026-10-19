/// Whether Ian must hide item text, and why (spec 6.5, ADR 0006).
///
/// This is the one decision the client takes itself, because its inputs are local. It never
/// changes data; it only decides what is drawn and said.
public struct Suppression: Equatable, Sendable {
  public enum Trigger: String, CaseIterable, Sendable {
    /// A camera is running in some app, read through CoreMediaIO.
    case cameraLive
    /// `today.context.inExternalMeeting`.
    case externalMeeting
    /// `today.context.quietHoursActive`.
    case quietHours
    /// The principal chose "Pause me".
    case userPaused
  }

  /// The triggers that hold now, in the order of `Trigger.allCases`.
  public let triggers: [Trigger]

  public var isActive: Bool { !triggers.isEmpty }

  public init(cameraLive: Bool, externalMeeting: Bool, quietHours: Bool, userPaused: Bool) {
    let held: [(Trigger, Bool)] = [
      (.cameraLive, cameraLive), (.externalMeeting, externalMeeting),
      (.quietHours, quietHours), (.userPaused, userPaused),
    ]
    triggers = held.filter(\.1).map(\.0)
  }

  /// No trigger holds.
  public static let none = Suppression(
    cameraLive: false, externalMeeting: false, quietHours: false, userPaused: false)
}
