/// Which of the two optional triggers hold back item text (spec 6.4). Quiet hours and the
/// principal's own pause are not toggles: they always suppress.
public struct SuppressionToggles: Equatable, Sendable {
  public var camera: Bool
  public var externalMeeting: Bool

  public init(camera: Bool = true, externalMeeting: Bool = true) {
    self.camera = camera
    self.externalMeeting = externalMeeting
  }
}
