import Observation

/// The expanded client's navigation state. It lives as long as the process: the app builds one
/// and the panel's view keeps it, so the last view is remembered however often the panel hides.
/// It is never written to disk (spec 6.4 does not list the last view among the settings that
/// may reach it).
@MainActor
@Observable
public final class ClientModel {
  var section: ClientSection = .today
  let today = TodayModel()

  public init() {}
}
