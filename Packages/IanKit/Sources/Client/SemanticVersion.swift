import Foundation

/// A `major.minor.patch` version, as `minClientVersion` and the app's bundle version carry.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  /// Reads `1`, `1.2` or `1.2.3`. Returns nil for anything else.
  public init?(_ text: String) {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else {
      return nil
    }
    let numbers = parts.compactMap { $0 } + [0, 0]
    self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
  }

  public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }

  public var description: String { "\(major).\(minor).\(patch)" }
}
