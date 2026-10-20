import Testing

@testable import Surface

@Suite("Motion preference")
struct MotionPreferenceTests {
  @Test(
    "reduces motion when either the setting or the system says so",
    arguments: [
      (setting: false, system: false, reduced: false),
      (setting: true, system: false, reduced: true),
      (setting: false, system: true, reduced: true),
      (setting: true, system: true, reduced: true),
    ])
  func either(setting: Bool, system: Bool, reduced: Bool) {
    #expect(MotionPreference.reduces(setting: setting, system: system) == reduced)
  }

  @Test("glides the Orbit to its corner only while motion is allowed")
  func cornerGlide() {
    #expect(MotionPreference.glidesToCorner(reducedMotion: false))
    #expect(!MotionPreference.glidesToCorner(reducedMotion: true))
  }
}
