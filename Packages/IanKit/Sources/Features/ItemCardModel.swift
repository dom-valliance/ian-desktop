import Contract
import Foundation
import Store

/// What a card in Proposals, Commitments, Tasks or Alerts says about one item, as plain values
/// so it is tested without a view. Every word comes from the item the server sent: the client
/// adds labels for enums and formats dates, and decides nothing (ADR 0001). The buttons are the
/// item's own `actions`, which the card hands to the shared action component untouched.
struct ItemCardModel: Equatable {
  struct Line: Equatable {
    enum Role: Equatable {
      /// The summary or explanation the item turns on.
      case primary
      case secondary
      /// Words read verbatim from the source, such as a commitment's evidence.
      case quote
    }

    let role: Role
    let text: String
  }

  let kind: Components.Schemas.ItemKind
  let kicker: String
  /// A short tag beside the kicker: a task's source or an alert's severity.
  let badge: String?
  let title: String
  let meta: String
  let lines: [Line]
  let lanceURL: URL?
  let sourceURL: URL?
  /// The server's line for an item it has just removed. When present the card is dimmed and has
  /// no actions and no hand-off, as a settled row on Today.
  let settlement: String?
  /// "Urgent" or "Stop" when the server's attention rung (ADR 0009) is one of those. It gives the
  /// card its rim and its badge, so the cue is never colour alone.
  let urgency: String?
  var isUrgent: Bool { urgency != nil }
  let accessibilityLabel: String

  init(
    item: Components.Schemas.Item, statuses: ItemStatuses = ItemStatuses(),
    removal: IanStore.Removal? = nil, timeZone: TimeZone = .current
  ) {
    kind = item.kind
    kicker = ItemKindStyle.name(item.kind)
    title = item.title
    meta = item.meta
    lanceURL = Self.webURL(item.links.lance)
    sourceURL = item.links.source.flatMap(Self.webURL)
    settlement = removal.map { $0.outcome ?? "Closed" }
    switch item.attention {
    case .urgent: urgency = "Urgent"
    case .stop: urgency = "Stop"
    case .ambient, .needsYou: urgency = nil
    }

    let format = CardDate(timeZone: timeZone)
    switch item.detail {
    case .proposal(let detail):
      badge = nil
      lines = Self.lines(proposal: detail, format: format)
    case .commitmentBy(let detail), .commitmentTo(let detail):
      badge = nil
      lines = Self.lines(commitment: detail, dueAt: item.dueAt, format: format)
    case .task(let detail):
      badge = detail.source.badge
      lines = Self.lines(task: detail, dueAt: item.dueAt, format: format)
    case .alert(let detail):
      badge = item.severity?.rawValue
      lines = Self.lines(alert: detail, format: format)
    }

    accessibilityLabel = TodayListModel.itemLabel(
      item, horizon: ItemKindStyle.name(item.horizon).lowercased(),
      status: removal != nil ? "settled" : statuses.description(of: item.id),
      attention: urgency?.lowercased())
  }

  /// Only web addresses open from a card; anything else the server sent is dropped.
  private static func webURL(_ text: String) -> URL? {
    guard let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased())
    else { return nil }
    return url
  }

  private static func lines(proposal detail: Components.Schemas.ProposalDetail, format: CardDate)
    -> [Line]
  {
    var lines = [
      Line(role: .primary, text: detail.summary),
      Line(role: .secondary, text: "Target: \(detail.targetSystemLabel)"),
      Line(role: .secondary, text: "Decision tier: \(detail.decisionTier.label)"),
    ]
    if let confidence = detail.confidence {
      lines.append(
        Line(
          role: .secondary,
          text:
            "Confidence \(String(format: "%.2f", confidence.value)), \(confidence.source.label)"))
    }
    lines.append(Line(role: .secondary, text: "Expires \(format.string(detail.expiresAt))"))
    return lines
  }

  private static func lines(
    commitment detail: Components.Schemas.CommitmentDetail, dueAt: Date?, format: CardDate
  ) -> [Line] {
    let source = detail.evidence.source
    let observed = source.observedAt.map { ", observed \(format.string($0))" } ?? ""
    return [
      Line(role: .secondary, text: "Counterparty: \(detail.counterparty.name)"),
      Line(role: .secondary, text: dueAt.map { "Due \(format.string($0))" } ?? "No due date"),
      Line(role: .quote, text: "\u{201C}\(detail.evidence.quote)\u{201D}"),
      Line(role: .secondary, text: "Evidence from \(source.label)\(observed)"),
      Line(role: .secondary, text: chase(detail.chase, format: format)),
    ]
  }

  private static func chase(_ chase: Components.Schemas.Chase, format: CardDate) -> String {
    var parts: [String]
    switch chase.state {
    case .notChased: parts = ["Not chased"]
    case .requested: parts = ["Chase draft waiting for you"]
    case .chased: parts = [chase.count == 1 ? "Chased once" : "Chased \(chase.count) times"]
    }
    if let last = chase.lastChasedAt { parts.append("last \(format.string(last))") }
    if let next = chase.nextChaseAt { parts.append("next \(format.string(next))") }
    return "Chase: " + parts.joined(separator: ", ")
  }

  private static func lines(
    task detail: Components.Schemas.TaskDetail, dueAt: Date?, format: CardDate
  ) -> [Line] {
    let assignee = detail.assignee
    let who = assignee.name ?? "Nobody"
    var lines = [
      Line(
        role: .secondary,
        text: "Assignee: \(who)\(assignee.isPrincipal ? " (you)" : "")"),
      Line(role: .secondary, text: "Status: \(detail.status)"),
    ]
    if let project = detail.project {
      lines.append(Line(role: .secondary, text: "Project: \(project)"))
    }
    if let dueAt { lines.append(Line(role: .secondary, text: "Due \(format.string(dueAt))")) }
    return lines
  }

  private static func lines(alert detail: Components.Schemas.AlertDetail, format: CardDate)
    -> [Line]
  {
    [
      Line(role: .secondary, text: detail.alertKindLabel),
      Line(role: .secondary, text: "Raised \(format.string(detail.raisedAt))"),
      Line(role: .primary, text: detail.explanation),
    ]
  }
}

/// A date as a card shows it: "16 Oct, 17:00", in the principal's time zone and British order.
struct CardDate {
  private let formatter: DateFormatter

  init(timeZone: TimeZone) { formatter = CardDateFormatters.formatter(for: timeZone) }

  /// The zone the server named for the principal (`me.timeZone`), or the Mac's when it does not
  /// parse or `me` has not arrived.
  static func timeZone(for me: Components.Schemas.Me?) -> TimeZone {
    me.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
  }

  func string(_ date: Date) -> String { formatter.string(from: date) }
}

/// One formatter per time zone, since building a `DateFormatter` is costly and a card is built on
/// every body evaluation.
private enum CardDateFormatters {
  // `DateFormatter` is safe to share once configured, and the lock guards the dictionary, so the
  // unchecked conformance holds.
  private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var byZone: [String: DateFormatter] = [:]

    func formatter(for zone: TimeZone) -> DateFormatter {
      lock.withLock {
        if let cached = byZone[zone.identifier] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM, HH:mm"
        byZone[zone.identifier] = formatter
        return formatter
      }
    }
  }

  private static let cache = Cache()

  static func formatter(for zone: TimeZone) -> DateFormatter { cache.formatter(for: zone) }
}

extension Components.Schemas.TaskSource {
  fileprivate var badge: String {
    switch self {
    case .notion: "Notion"
    case .jamie: "Jamie"
    }
  }
}

extension Components.Schemas.DecisionTier {
  fileprivate var label: String {
    switch self {
    case .hardFloor: "hard floor"
    case .personal: "personal"
    case .organisation: "organisation"
    case .fallback: "fallback"
    }
  }
}

extension Components.Schemas.ConfidenceSource {
  /// Names where the value came from and ranks no source above another.
  fileprivate var label: String {
    switch self {
    case .levTrusted: "trusted by Lev"
    case .levUntrusted: "not trusted by Lev"
    case .selfReport: "self-reported"
    }
  }
}
