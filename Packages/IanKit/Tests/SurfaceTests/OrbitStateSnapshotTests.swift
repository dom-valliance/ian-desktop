import AppKit
import SnapshotTesting
import Testing

@testable import Surface

/// The Orbit states the four scenarios never reach, built from invented models: the core on its
/// own, the overflow chip at its limits, an alert on its own, one satellite of each kind and the
/// load ring at its edges. Drawn through the same renderer as the scenarios.
@Suite("Orbit state snapshots")
@MainActor
struct OrbitStateSnapshotTests {
  private static let time = 0.6

  /// A state whose parts move, so it is drawn with motion on and off.
  enum Moving: String, CaseIterable {
    case coreWorking = "core-working"
    case alertAlone = "alert-alone"
    case everyKind = "every-kind"

    var model: OrbitModel {
      switch self {
      case .coreWorking:
        OrbitModel(load: 4, median: 12, working: true)
      case .alertAlone:
        OrbitModel(
          satellites: [.init(slot: 0, kind: .alert)], overflow: 0, load: 6, median: 12)
      case .everyKind:
        OrbitModel(
          satellites: [
            .init(slot: 0, kind: .proposal), .init(slot: 1, kind: .commitmentBy),
            .init(slot: 2, kind: .commitmentTo), .init(slot: 3, kind: .task),
            .init(slot: 4, kind: .alert),
          ], overflow: 0, load: 12, median: 12, working: true)
      }
    }
  }

  /// A state that does not move, so one drawing covers both motion settings.
  enum Still: String, CaseIterable {
    case empty
    case overflowOne = "overflow-1"
    case overflowLarge = "overflow-128"
    case loadAtMedian = "load-at-median"
    case loadTwiceMedian = "load-twice-median"

    var model: OrbitModel {
      let one = [OrbitModel.Satellite(slot: 0, kind: .proposal)]
      switch self {
      case .empty:
        return OrbitModel()
      case .overflowOne:
        return OrbitModel(satellites: one, overflow: 1, load: 5, median: 12)
      case .overflowLarge:
        return OrbitModel(satellites: one, overflow: 128, load: 5, median: 12)
      case .loadAtMedian:
        return OrbitModel(satellites: one, overflow: 0, load: 12, median: 12)
      case .loadTwiceMedian:
        return OrbitModel(satellites: one, overflow: 0, load: 24, median: 12)
      }
    }
  }

  private func check(_ model: OrbitModel, reducedMotion: Bool, named name: String) {
    assertSnapshot(
      of: OrbitImage.of(model, time: Self.time, reducedMotion: reducedMotion),
      as: .image(precision: 0.998, perceptualPrecision: 0.98), named: name, testName: "orbit")
  }

  @Test("matches the reference with motion on", arguments: Moving.allCases)
  func movingOn(state: Moving) {
    check(state.model, reducedMotion: false, named: "\(state.rawValue)-motion-on")
  }

  @Test("matches the reference with motion off", arguments: Moving.allCases)
  func movingOff(state: Moving) {
    check(state.model, reducedMotion: true, named: "\(state.rawValue)-motion-off")
  }

  @Test("matches the reference", arguments: Still.allCases)
  func still(state: Still) {
    check(state.model, reducedMotion: true, named: state.rawValue)
  }

  @Test("draws a state with nothing moving identically with motion on and off")
  func stillIsIndependentOfMotion() {
    for state in Still.allCases {
      #expect(
        OrbitRenderer.drawing(for: state.model, time: Self.time, reducedMotion: false)
          == OrbitRenderer.drawing(for: state.model, time: Self.time, reducedMotion: true))
    }
  }
}
