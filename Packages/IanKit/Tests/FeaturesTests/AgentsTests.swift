import Contract
import Foundation
import TestSupport
import Testing

@testable import Features

@Suite("Agents table rows")
struct AgentRowTests {
  private let london = TimeZone(identifier: "Europe/London")!

  @Test("shows the state, cost and share of the ceiling as the server sent them")
  func showsServerValues() {
    var agent = Fixtures.agent(id: "agent_7", state: "breaker_open", name: "Calendar job")
    agent.kind = .job
    agent.costTodayGbp = 1.5
    agent.ceilingFraction = 0.1
    agent.breaker = .open

    let row = AgentRow(agent: agent, timeZone: london)

    #expect(row.name == "Calendar job")
    #expect(row.kind == "Job")
    #expect(row.state == "Breaker open")
    #expect(row.breaker == "Breaker open")
    #expect(row.cost == "£1.50")
    #expect(row.share == "10%")
  }

  @Test("says so when an agent has not run or has nothing planned")
  func missingTimes() {
    var agent = Fixtures.agent()
    agent.lastRunAt = nil
    agent.nextRunAt = nil

    let row = AgentRow(agent: agent, timeZone: london)

    #expect(row.lastRun == "Not yet")
    #expect(row.nextRun == "None planned")
  }

  @Test("names a time in the zone it is given, in British English")
  func timesUseTheZone() {
    let row = AgentRow(agent: Fixtures.agent(), timeZone: london)

    #expect(row.lastRun.contains("16 Oct 2026"))
    #expect(row.lastRun.contains("8:55"))
  }

  @Test("offers Pause to a running agent and Resume to a paused one")
  func commandFollowsTheState() {
    #expect(AgentRow(agent: Fixtures.agent(state: "idle")).command == .pause)
    #expect(AgentRow(agent: Fixtures.agent(state: "failed")).command == .pause)
    #expect(AgentRow(agent: Fixtures.agent(state: "paused")).command == .resume)
  }

  @Test("offers no command for an agent that is not pausable")
  func noCommandWhenNotPausable() {
    #expect(AgentRow(agent: Fixtures.agent(pausable: false)).command == nil)
  }

  @Test("keeps the order the server sent")
  func keepsOrder() {
    let agents = ["b", "a", "c"].map { Fixtures.agent(id: $0) }
    #expect(agents.map { AgentRow(agent: $0).id } == ["b", "a", "c"])
  }
}

@Suite("Kill switch notice")
struct KillSwitchTests {
  @Test("shows when the global kill switch is on, with the reason")
  func showsWithReason() {
    let global = Fixtures.settings(globalPaused: true, globalReason: "Maintenance window").global

    let notice = KillSwitchNotice(global: global)

    #expect(notice?.title == "Paused for everyone")
    #expect(notice?.message.contains("Reason: Maintenance window") == true)
  }

  @Test("shows without a reason when the server gave none")
  func showsWithoutReason() {
    let notice = KillSwitchNotice(global: Fixtures.settings(globalPaused: true).global)

    #expect(notice != nil)
    #expect(notice?.message.contains("Reason") == false)
  }

  @Test("is absent when the kill switch is off")
  func absentWhenOff() {
    #expect(KillSwitchNotice(global: Fixtures.settings().global) == nil)
  }
}
