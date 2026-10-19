import Foundation

/// The VoiceOver label for the Orbit (spec 6.1): "Ian, three need you now, forty-one open, one
/// urgent". It is built from three counts the server sends and never from an item's text.
public enum OrbitAccessibility {
  public static func label(nowCount: Int, load: Int, urgentCount: Int) -> String {
    let needYou = nowCount == 1 ? "needs you now" : "need you now"
    return [
      "Ian",
      "\(words(nowCount)) \(needYou)",
      "\(words(load)) open",
      "\(words(urgentCount)) urgent",
    ].joined(separator: ", ")
  }

  private static let spellOut: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.numberStyle = .spellOut
    return formatter
  }()

  /// The number spelled out in British English, and "none" for zero.
  static func words(_ number: Int) -> String {
    guard number != 0 else { return "none" }
    guard var text = spellOut.string(from: NSNumber(value: number)) else { return String(number) }
    // The formatter omits British English's "and" after hundreds and thousands.
    for (word, divisor) in [("thousand", 1000), ("hundred", 100)]
    where number >= divisor && (1..<100).contains(number % divisor) {
      text = text.replacingOccurrences(of: "\(word) ", with: "\(word) and ")
    }
    return text
  }
}
