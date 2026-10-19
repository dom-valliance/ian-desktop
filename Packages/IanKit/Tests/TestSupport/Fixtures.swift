import Contract
import Foundation
import OpenAPIRuntime

/// Invented contract data for tests. Nothing here is real (AGENTS.md, Data): names are
/// placeholders. The builders return JSON text, so tests can serve it over a stubbed session, and
/// decode it the way the client does.
public enum Fixtures {
  public typealias Schemas = Components.Schemas

  public struct ActionSpec: Sendable {
    public var id: String
    public var input: String

    public init(_ id: String, input: String = "none") {
      self.id = id
      self.input = input
    }
  }

  public static func decode<Value: Decodable>(_ json: String) -> Value {
    let transcoder = ISO8601DateTranscoder.iso8601WithFractionalSeconds
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      try transcoder.decode(try decoder.singleValueContainer().decode(String.self))
    }
    do {
      return try decoder.decode(Value.self, from: Data(json.utf8))
    } catch {
      preconditionFailure("The fixture does not decode as \(Value.self): \(error)")
    }
  }

  // MARK: Items

  public static func itemJSON(
    id: String = "task_1", alert: Bool = false, version: Int = 1,
    title: String = "Draft the agenda for the [CLIENT] steering group",
    actions: [ActionSpec] = [ActionSpec("done")], working: Bool = false
  ) -> String {
    let actionList = actions.map {
      """
      {"id":"\($0.id)","label":"\($0.id.capitalized)","style":"primary","confirm":null,\
      "input":"\($0.input)"}
      """
    }.joined(separator: ",")
    let detail =
      alert
      ? """
      {"kind":"alert","alertKind":"breaker_open","alertKindLabel":"Breaker open",\
      "raisedAt":"2026-10-16T08:00:00.000Z","dedupeKey":"breaker:1","relatedItemIds":[],\
      "explanation":"An agent stopped after repeated failures."}
      """
      : """
      {"kind":"task","source":"notion","assignee":{"name":"[PERSON]","isPrincipal":true},\
      "status":"In Progress","project":null}
      """
    return """
      {"id":"\(id)","kind":"\(alert ? "alert" : "task")","title":"\(title)","meta":"Notion",\
      "unit":{"id":"other","name":"Other"},"horizon":"now","pressure":0.4,"attention":"needs_you",\
      "dueAt":"2026-10-16T17:00:00.000Z",\(alert ? "\"severity\":\"P1\"," : "")\
      "working":\(working),"version":\(version),"actions":[\(actionList)],"detail":\(detail),\
      "links":{"lance":"https://lance.example.invalid/items/\(id)","source":null}}
      """
  }

  public static func item(
    id: String = "task_1", alert: Bool = false, version: Int = 1,
    title: String = "Draft the agenda for the [CLIENT] steering group",
    actions: [ActionSpec] = [ActionSpec("done")], working: Bool = false
  ) -> Schemas.Item {
    decode(
      itemJSON(
        id: id, alert: alert, version: version, title: title, actions: actions, working: working))
  }

  // MARK: Blocks

  public static func todayJSON(load: Int = 1, itemIDs: [String] = []) -> String {
    let ids = itemIDs.map { "\"\($0)\"" }.joined(separator: ",")
    return """
      {"orbit":{"itemIds":[\(ids)],"overflow":0,"nowCount":\(itemIDs.count),"urgentCount":0,\
      "load":\(load),"median":12,"working":false},\
      "field":{"units":[],"cells":[]},"lists":{"now":[\(ids)],"week":[],"later":[]},\
      "context":{"inExternalMeeting":false,"quietHoursActive":false}}
      """
  }

  public static func viewsJSON(tasks: Int = 0) -> String {
    """
    {"counts":{"today":\(tasks),"proposals":0,"commitments":0,"tasks":\(tasks),"alerts":0,\
    "agents":1},"proposals":[],"commitments":{"owedByMe":[],"owedToMe":[],"toConfirm":[]},\
    "tasks":[],"alerts":[]}
    """
  }

  public static func agentJSON(
    id: String = "agent_1", state: String = "idle", name: String = "Inbox watcher",
    pausable: Bool = true
  ) -> String {
    """
    {"id":"\(id)","name":"\(name)","kind":"watcher","state":"\(state)",\
    "lastRunAt":"2026-10-16T07:55:00.000Z","nextRunAt":null,"costTodayGbp":0.4,\
    "ceilingFraction":0.03,"pausable":\(pausable)}
    """
  }

  public static func agent(
    id: String = "agent_1", state: String = "idle", name: String = "Inbox watcher",
    pausable: Bool = true
  ) -> Schemas.Agent {
    decode(agentJSON(id: id, state: state, name: name, pausable: pausable))
  }

  public static func agentsOverview(_ agents: [Schemas.Agent], cost: Double = 0.4)
    -> Schemas.AgentsOverview
  {
    Schemas.AgentsOverview(agents: agents, costToday: decode(costJSON(cost: cost)))
  }

  public static func settings(
    mode: String = "dry_run", liveEligible: Bool = false, liveOpensAt: String? = nil,
    paused: Bool = false, pausedReason: String? = nil, globalPaused: Bool = false,
    globalReason: String? = nil
  ) -> Schemas.Settings {
    decode(
      settingsJSON(
        mode: mode, liveEligible: liveEligible, liveOpensAt: liveOpensAt, paused: paused,
        pausedReason: pausedReason, globalPaused: globalPaused, globalReason: globalReason))
  }

  public static func costJSON(cost: Double = 0.4) -> String {
    "{\"costGbp\":\(cost),\"ceilingGbp\":15,\"fraction\":0.03}"
  }

  public static func settingsJSON(
    pushBudget: Int = 3, mode: String = "dry_run", liveEligible: Bool = false,
    liveOpensAt: String? = nil, paused: Bool = false, pausedReason: String? = nil,
    globalPaused: Bool = false, globalReason: String? = nil
  ) -> String {
    func text(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
    return """
      {"quietHours":{"start":"19:00","end":"07:00"},"pushBudgetPerHour":\(pushBudget),\
      "mode":"\(mode)","liveEligible":\(liveEligible),"liveOpensAt":\(text(liveOpensAt)),\
      "paused":\(paused),"pausedReason":\(text(pausedReason)),\
      "timeZone":"Europe/London","costCeilingGbp":15,\
      "global":{"paused":\(globalPaused),"pausedReason":\(text(globalReason)),"mode":"dry_run"}}
      """
  }

  public static func meJSON(minClientVersion: String = "0.1.0") -> String {
    """
    {"principalId":"prin_1","displayName":"[PERSON]","status":"active","mode":"dry_run",\
    "timeZone":"Europe/London","minClientVersion":"\(minClientVersion)","contractVersion":"1.0.0",\
    "capabilities":{"handoff":false},"serverTime":"2026-10-16T08:00:00.000Z"}
    """
  }

  public static func me(minClientVersion: String = "0.1.0") -> Schemas.Me {
    decode(meJSON(minClientVersion: minClientVersion))
  }

  public static func snapshotJSON(
    cursor: String = "10", items: [String] = [itemJSON()], load: Int? = nil,
    today: String? = nil, views: String? = nil
  ) -> String {
    """
    {"cursor":"\(cursor)","serverTime":"2026-10-16T08:00:00.000Z",\
    "today":\(today ?? todayJSON(load: load ?? items.count)),"views":\(views ?? viewsJSON()),\
    "items":[\(items.joined(separator: ","))],\
    "agents":{"agents":[\(agentJSON())],"costToday":\(costJSON())},\
    "settings":\(settingsJSON())}
    """
  }

  public static func snapshot(
    cursor: String = "10", items: [String] = [itemJSON()], load: Int? = nil,
    today: String? = nil, views: String? = nil
  ) -> Schemas.Snapshot {
    decode(snapshotJSON(cursor: cursor, items: items, load: load, today: today, views: views))
  }

  // MARK: Events

  private static func correlation(_ id: String?) -> String {
    id.map { ",\"correlationId\":\"\($0)\"" } ?? ""
  }

  public static func upsertedJSON(_ item: String, correlationId: String? = nil) -> String {
    "{\"type\":\"item.upserted\",\"item\":\(item)\(correlation(correlationId))}"
  }

  public static func alertRaisedJSON(_ item: String, correlationId: String? = nil) -> String {
    "{\"type\":\"alert.raised\",\"item\":\(item)\(correlation(correlationId))}"
  }

  public static func removedJSON(
    _ id: String, outcome: String? = "Settled. Recorded on the ledger", correlationId: String? = nil
  ) -> String {
    let outcomeText = outcome.map { "\"\($0)\"" } ?? "null"
    return """
      {"type":"item.removed","itemId":"\(id)","outcome":\(outcomeText)\(correlation(correlationId))}
      """
  }

  public static func alertClearedJSON(_ id: String, correlationId: String? = nil) -> String {
    "{\"type\":\"alert.cleared\",\"itemId\":\"\(id)\"\(correlation(correlationId))}"
  }

  public static func todayUpdatedJSON(load: Int) -> String {
    "{\"type\":\"today.updated\",\"today\":\(todayJSON(load: load))}"
  }

  public static func viewsUpdatedJSON(tasks: Int) -> String {
    "{\"type\":\"views.updated\",\"views\":\(viewsJSON(tasks: tasks))}"
  }

  public static func agentUpdatedJSON(id: String = "agent_1", state: String, cost: Double = 0.9)
    -> String
  {
    """
    {"type":"agent.updated","agent":\(agentJSON(id: id, state: state)),\
    "costToday":\(costJSON(cost: cost))}
    """
  }

  public static func settingsUpdatedJSON(pushBudget: Int) -> String {
    "{\"type\":\"settings.updated\",\"settings\":\(settingsJSON(pushBudget: pushBudget))}"
  }

  public static func settingsUpdatedJSON(settings: String) -> String {
    "{\"type\":\"settings.updated\",\"settings\":\(settings)}"
  }

  public static func clientDeprecatedJSON(minClientVersion: String) -> String {
    """
    {"type":"client.deprecated","minClientVersion":"\(minClientVersion)","message":null}
    """
  }

  public static let heartbeatJSON =
    "{\"type\":\"heartbeat\",\"serverTime\":\"2026-10-16T08:00:25.000Z\"}"

  public static func event(_ json: String) -> Schemas.StreamEvent { decode(json) }

  /// One server-sent event as the wire carries it.
  public static func sse(id: String?, event: String, data: String) -> String {
    (id.map { "id: \($0)\n" } ?? "") + "event: \(event)\ndata: \(data)\n\n"
  }
}
