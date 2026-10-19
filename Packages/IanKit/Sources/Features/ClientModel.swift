import Foundation
import Observation
import Surface

/// The expanded client's navigation state. It lives as long as the process: the app builds one
/// and the panel's view keeps it, so the last view is remembered however often the panel hides.
/// The last view is never written to disk (spec 6.4 does not list it among the settings that
/// may reach it); the pane sizes and the field's angle are (ADR 0016).
@MainActor
@Observable
public final class ClientModel {
  var section: ClientSection = .today
  let today = TodayModel()

  let layout: PaneLayout

  public init(defaults: UserDefaults = .standard) {
    layout = PaneLayout(settings: ClientLayoutSettings(defaults: defaults))
  }
}
