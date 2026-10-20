import Contract
import Foundation
import Store
import TestSupport
import Testing

@testable import Features

private typealias Schemas = Components.Schemas

private let utc = TimeZone(identifier: "UTC")!

/// An item in the envelope the server sends, with `detail` and the fields that vary.
private func item(
  id: String, kind: String, severity: String? = nil, dueAt: String? = "2026-10-16T17:00:00.000Z",
  actions: String =
    #"[{"id":"zeta","label":"Zeta","style":"primary","confirm":null,"input":"none"}]"#,
  source: String = "null", detail: String
) -> Schemas.Item {
  Fixtures.decode(
    """
    {"id":"\(id)","kind":"\(kind)","title":"Title of \(id)","meta":"Meta of \(id)",\
    "unit":{"id":"u","name":"[CLIENT]"},"horizon":"now","pressure":0.5,"attention":"needs_you",\
    "dueAt":\(dueAt.map { "\"\($0)\"" } ?? "null"),\
    \(severity.map { "\"severity\":\"\($0)\"," } ?? "")\
    "working":false,"version":2,"actions":\(actions),"detail":\(detail),\
    "links":{"lance":"https://lance.example.invalid/items/\(id)","source":\(source)}}
    """)
}

private func proposal(confidence: String?) -> Schemas.Item {
  item(
    id: "prop_1", kind: "proposal",
    detail: """
      {"kind":"proposal","actionClass":"create_task","actionClassLabel":"Create a task",\
      "targetSystem":"notion","targetSystemLabel":"Notion","summary":"Create a task for the agenda",\
      "policyDecision":"propose","decisionTier":"personal",\
      \(confidence.map { "\"confidence\":\($0)," } ?? "")\
      "expiresAt":"2026-10-17T09:30:00.000Z"}
      """)
}

private func card(
  _ item: Schemas.Item, statuses: ItemStatuses = ItemStatuses(), removal: IanStore.Removal? = nil
) -> ItemCardModel {
  ItemCardModel(item: item, statuses: statuses, removal: removal, timeZone: utc)
}

@Suite("Card content")
struct ItemCardModelTests {
  @Test("shows a proposal's summary, target, tier, confidence with its source, and expiry")
  func proposalFields() {
    let model = card(
      proposal(confidence: #"{"value":0.82,"source":"self_report"}"#))

    #expect(model.kicker == "Proposal")
    #expect(
      model.lines.map(\.text) == [
        "Create a task for the agenda", "Target: Notion", "Decision tier: personal",
        "Confidence 0.82, self-reported", "Expires 17 Oct, 09:30",
      ])
  }

  @Test("names each confidence source without ranking them")
  func confidenceSources() {
    let trusted = card(proposal(confidence: #"{"value":0.9,"source":"lev_trusted"}"#))
    let untrusted = card(proposal(confidence: #"{"value":0.5,"source":"lev_untrusted"}"#))

    #expect(trusted.lines.map(\.text).contains("Confidence 0.90, trusted by Lev"))
    #expect(untrusted.lines.map(\.text).contains("Confidence 0.50, not trusted by Lev"))
  }

  @Test("shows no confidence line when the proposal carries none")
  func noConfidence() {
    let model = card(proposal(confidence: nil))

    #expect(!model.lines.contains { $0.text.hasPrefix("Confidence") })
  }

  @Test("shows a commitment's counterparty, due date, evidence quote with source, and chase state")
  func commitmentFields() {
    let model = card(
      item(
        id: "cmt_1", kind: "commitment_to",
        detail: """
          {"kind":"commitment_to","counterparty":{"id":"p1","name":"[PERSON]"},\
          "evidence":{"quote":"I will send the estimate","source":{"kind":"email","system":"graph",\
          "label":"Email thread","observedAt":"2026-10-14T10:00:00.000Z"}},\
          "chase":{"state":"chased","count":2,"lastChasedAt":"2026-10-15T08:00:00.000Z",\
          "nextChaseAt":null},"toConfirm":false}
          """))

    #expect(
      model.lines.map(\.text) == [
        "Counterparty: [PERSON]", "Due 16 Oct, 17:00", "\u{201C}I will send the estimate\u{201D}",
        "Evidence from Email thread, observed 14 Oct, 10:00",
        "Chase: Chased 2 times, last 15 Oct, 08:00",
      ])
    #expect(model.lines[2].role == .quote)
  }

  @Test("says a commitment has no due date when the server sent none")
  func commitmentWithoutDueDate() {
    let model = card(
      item(
        id: "cmt_2", kind: "commitment_by", dueAt: nil,
        detail: """
          {"kind":"commitment_by","counterparty":{"id":"p1","name":"[PERSON]"},\
          "evidence":{"quote":"q","source":{"kind":"record","system":"jamie","label":"Meeting",\
          "observedAt":null}},"chase":{"state":"not_chased","count":0,"lastChasedAt":null,\
          "nextChaseAt":null},"toConfirm":true}
          """))

    #expect(model.lines.map(\.text).contains("No due date"))
    #expect(model.lines.map(\.text).contains("Chase: Not chased"))
  }

  @Test("shows a task's source badge, assignee, status and a source link")
  func taskFields() {
    let model = card(
      item(
        id: "task_1", kind: "task", source: #""https://notion.example.invalid/page""#,
        detail: """
          {"kind":"task","source":"jamie","assignee":{"name":"[PERSON]","isPrincipal":true},\
          "status":"In Progress","project":"[PROJECT]"}
          """))

    #expect(model.badge == "Jamie")
    #expect(model.sourceURL?.absoluteString == "https://notion.example.invalid/page")
    #expect(model.lanceURL?.absoluteString == "https://lance.example.invalid/items/task_1")
    #expect(
      model.lines.map(\.text).prefix(3) == [
        "Assignee: [PERSON] (you)", "Status: In Progress", "Project: [PROJECT]",
      ])
  }

  @Test("shows an alert's kind label, raised time, explanation and severity")
  func alertFields() {
    let model = card(
      item(
        id: "alrt_1", kind: "alert", severity: "P0",
        detail: """
          {"kind":"alert","alertKind":"breaker_open","alertKindLabel":"Breaker open",\
          "raisedAt":"2026-10-16T08:00:00.000Z","dedupeKey":"k","relatedItemIds":[],\
          "explanation":"An agent stopped after repeated failures."}
          """))

    #expect(model.badge == "P0")
    #expect(
      model.lines.map(\.text) == [
        "Breaker open", "Raised 16 Oct, 08:00", "An agent stopped after repeated failures.",
      ])
  }

  @Test("offers no source link when the item has none, and drops a link that is not a web address")
  func linksAreWebOnly() {
    var odd = proposal(confidence: nil)
    odd.links = Schemas.ItemLinks(lance: "file:///etc/passwd", source: nil)

    let model = card(odd)

    #expect(model.sourceURL == nil)
    #expect(model.lanceURL == nil)
  }

  @Test("labels the card for VoiceOver with its kind, title and state")
  func accessibilityLabel() {
    let proposal = proposal(confidence: nil)
    let pending = card(proposal, statuses: ItemStatuses(pending: ["prop_1"]))
    let failed = card(
      proposal, statuses: ItemStatuses(notices: ["prop_1": .failed("No.")]))

    #expect(card(proposal).accessibilityLabel == "Proposal, Title of prop_1, now")
    #expect(pending.accessibilityLabel == "Proposal, Title of prop_1, now, pending")
    #expect(failed.accessibilityLabel == "Proposal, Title of prop_1, now, error: No.")
  }

  @Test("dims a removed item and shows the server's outcome line in place of its actions")
  func settledCard() {
    let item = proposal(confidence: nil)
    let removal = IanStore.Removal(
      item: item, outcome: "Approved. Recorded in dry run.", removedAt: Date())

    let model = card(item, removal: removal)

    #expect(model.settlement == "Approved. Recorded in dry run.")
    #expect(model.accessibilityLabel == "Proposal, Title of prop_1, now, settled")
    #expect(card(item).settlement == nil)
  }

  @Test("says Closed when the server sent no outcome for a removed item")
  func settledWithoutOutcome() {
    let item = proposal(confidence: nil)

    let model = card(item, removal: .init(item: item, outcome: nil, removedAt: Date()))

    #expect(model.settlement == "Closed")
  }

  @Test("gives the urgent rim to every kind the server marks urgent or stop, and to no other")
  func urgentRimFollowsAttention() {
    var base = proposal(confidence: nil)
    var rims: [Schemas.Attention: Bool] = [:]
    for rung in [Schemas.Attention.ambient, .needsYou, .urgent, .stop] {
      base.attention = rung
      rims[rung] = card(base).isUrgent
    }

    #expect(rims == [.ambient: false, .needsYou: false, .urgent: true, .stop: true])
  }

  @Test("adds a text cue and a spoken rung for urgent and stop, so the rim is not the only signal")
  func urgencyIsNotColourAlone() {
    var base = proposal(confidence: nil)
    base.attention = .urgent
    let urgent = card(base)
    base.attention = .stop
    let stop = card(base)
    base.attention = .needsYou
    let calm = card(base)

    #expect(urgent.urgency == "Urgent")
    #expect(stop.urgency == "Stop")
    #expect(calm.urgency == nil)
    #expect(urgent.accessibilityLabel == "Proposal, Title of prop_1, now, urgent")
    #expect(stop.accessibilityLabel == "Proposal, Title of prop_1, now, stop")
    #expect(calm.accessibilityLabel == "Proposal, Title of prop_1, now")
  }

  @Test("does not key the rim on an alert's severity")
  func severityGivesNoRim() {
    var alert = item(
      id: "alrt_1", kind: "alert", severity: "P0",
      detail: """
        {"kind":"alert","alertKind":"k","alertKindLabel":"L","raisedAt":"2026-10-16T08:00:00.000Z",\
        "dedupeKey":"k","relatedItemIds":[],"explanation":"E"}
        """)
    alert.attention = .needsYou

    #expect(!card(alert).isUrgent)
  }

  @Test("formats dates in the principal's time zone, and falls back to the Mac's")
  func principalTimeZone() {
    var me = Fixtures.me()
    me.timeZone = "Asia/Tokyo"
    let tokyo = CardDate.timeZone(for: me)
    me.timeZone = "Not/A_Zone"

    #expect(tokyo.identifier == "Asia/Tokyo")
    #expect(CardDate.timeZone(for: me) == .current)
    #expect(CardDate.timeZone(for: nil) == .current)
    #expect(
      ItemCardModel(item: proposal(confidence: nil), timeZone: tokyo).lines.last?.text
        == "Expires 17 Oct, 18:30")
  }
}
