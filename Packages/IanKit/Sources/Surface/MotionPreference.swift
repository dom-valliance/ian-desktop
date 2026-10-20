/// Reduce Motion as the principal and the system set it (spec 6.8). One rule for every surface
/// that moves, so none reads one switch and forgets the other.
public enum MotionPreference {
  /// Motion is reduced when the Settings switch or the system's Reduce Motion is on.
  public static func reduces(setting: Bool, system: Bool) -> Bool {
    setting || system
  }

  /// Whether the Orbit glides to its corner after a drag. Reduce Motion places it at once.
  static func glidesToCorner(reducedMotion: Bool) -> Bool {
    !reducedMotion
  }
}
