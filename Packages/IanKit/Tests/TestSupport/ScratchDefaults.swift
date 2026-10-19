import Foundation

/// Runs `body` with settings held apart from the app's own, and clears them afterwards.
/// `removePersistentDomain` leaves an empty preferences file, so that is deleted too.
@MainActor
public func withScratchDefaults<Result>(_ body: (UserDefaults) throws -> Result) rethrows -> Result
{
  let name = "ian.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defer {
    defaults.removePersistentDomain(forName: name)
    let file = URL.libraryDirectory.appending(path: "Preferences/\(name).plist")
    try? FileManager.default.removeItem(at: file)
  }
  return try body(defaults)
}

/// Runs `body` with scratch settings, for tests that await.
@MainActor
public func withScratchDefaultsAsync(_ body: (UserDefaults) async -> Void) async {
  let name = "ian.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  await body(defaults)
  defaults.removePersistentDomain(forName: name)
  let file = URL.libraryDirectory.appending(path: "Preferences/\(name).plist")
  try? FileManager.default.removeItem(at: file)
}
