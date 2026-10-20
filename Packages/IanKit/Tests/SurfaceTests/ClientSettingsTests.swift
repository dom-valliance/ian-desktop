import AppKit
import Attention
import Client
import Store
import TestSupport
import Testing

@testable import Surface

@Suite("Client settings")
@MainActor
struct ClientSettingsTests {
  init() {
    _ = NSApplication.shared
  }

  private let area = CGRect(x: 0, y: 0, width: 1440, height: 900)

  private func controller(
    defaults: UserDefaults, store: IanStore? = nil, camera: FakeCamera = FakeCamera()
  ) -> (SurfaceController, SuppressionSignals) {
    let store =
      store
      ?? IanStore(
        service: ScriptedService(), profile: .mock,
        appVersion: SemanticVersion(major: 0, minor: 1, patch: 0))
    let signals = SuppressionSignals(camera: camera)
    signals.start()
    let controller = SurfaceController(
      store: store, signals: signals, defaults: defaults, screenArea: { area }, quit: {})
    return (controller, signals)
  }

  @Test("starts with the defaults when nothing is saved")
  func defaultsWhenNothingSaved() {
    withScratchDefaults { defaults in
      let settings = ClientSettings(defaults: defaults)
      #expect(!settings.reducedMotion)
      #expect(settings.suppressOnCamera)
      #expect(settings.suppressInExternalMeeting)
      #expect(settings.level(for: .ambient) == .off)
      #expect(settings.level(for: .needsYou) == .off)
      #expect(settings.level(for: .urgent) == .banner)
      #expect(settings.level(for: .stop) == .banner)
    }
  }

  @Test("saves each setting and reads it back in a new instance, as after a relaunch")
  func survivesARelaunch() {
    withScratchDefaults { defaults in
      let first = ClientSettings(defaults: defaults)
      first.setReducedMotion(true)
      first.setSuppressOnCamera(false)
      first.setSuppressInExternalMeeting(false)
      first.setLevel(.banner, for: .needsYou)
      first.setLevel(.off, for: .urgent)
      first.setLevel(.banner, for: .ambient)

      let second = ClientSettings(defaults: defaults)
      #expect(second.reducedMotion)
      #expect(!second.suppressOnCamera)
      #expect(!second.suppressInExternalMeeting)
      #expect(second.level(for: .needsYou) == .banner)
      #expect(second.level(for: .urgent) == .off)
      #expect(second.level(for: .ambient) == .banner)
    }
  }

  @Test("keeps Stop notifying and saves nothing for it")
  func stopCannotBeChanged() {
    withScratchDefaults { defaults in
      let settings = ClientSettings(defaults: defaults)
      settings.setLevel(.off, for: .stop)
      #expect(settings.level(for: .stop) == .banner)
      #expect(ClientSettings(defaults: defaults).level(for: .stop) == .banner)
    }
  }

  @Test("reads an unknown saved level as the rung's default")
  func unknownLevelFallsBack() {
    withScratchDefaults { defaults in
      defaults.set("loud", forKey: "IanNotificationLevelUrgent")
      #expect(ClientSettings(defaults: defaults).level(for: .urgent) == .banner)
    }
  }

  @Test("gives the surface the motion setting, which a relaunch keeps")
  func motionReachesTheSurface() {
    withScratchDefaults { defaults in
      let (surface, _) = controller(defaults: defaults)
      #expect(!surface.reducedMotionSetting)
      surface.settings.setReducedMotion(true)
      #expect(surface.reducedMotionSetting)
      #expect(controller(defaults: defaults).0.reducedMotionSetting)
    }
  }

  @Test("moves the Orbit and saves the corner when it changes")
  func cornerMovesTheOrbit() {
    withScratchDefaults { defaults in
      let (surface, _) = controller(defaults: defaults)
      #expect(surface.corner == .bottomRight)
      surface.setCorner(.topLeft)
      #expect(surface.corner == .topLeft)
      #expect(surface.windows[0].frame == OrbitPlacement.orbitFrame(corner: .topLeft, in: area))
      #expect(CornerSetting(defaults: defaults).corner == .topLeft)
    }
  }

  @Test("ignores a live camera once the camera toggle is off")
  func cameraToggleIsIgnored() {
    withScratchDefaults { defaults in
      let camera = FakeCamera()
      camera.isLive = true
      let (surface, _) = controller(defaults: defaults, camera: camera)
      #expect(surface.suppression.triggers == [.cameraLive])
      surface.settings.setSuppressOnCamera(false)
      #expect(!surface.suppression.isActive)
    }
  }

  @Test("ignores an external meeting once its toggle is off, but not quiet hours")
  func meetingToggleIsIgnored() async {
    await withScratchDefaultsAsync { defaults in
      let store = await loadedStore(
        OrbitScenario.load("normal"), externalMeeting: true, quietHours: true)
      defer { store.stop() }
      let (surface, _) = controller(defaults: defaults, store: store)
      #expect(surface.suppression.triggers == [.externalMeeting, .quietHours])
      surface.settings.setSuppressInExternalMeeting(false)
      #expect(surface.suppression.triggers == [.quietHours])
      #expect(surface.presentation.hoverText == nil)
    }
  }
}
