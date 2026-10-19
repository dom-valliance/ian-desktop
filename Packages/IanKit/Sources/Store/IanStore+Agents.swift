import Client
import Contract
import Foundation
import os

extension IanStore {
  private static let agentsLog = Logger(subsystem: "ai.valliance.ian.desktop", category: "agents")

  /// Pauses an agent. The agent is marked pending, and only its `agent.updated` event changes
  /// the state shown (ADR 0001).
  public func pause(agent id: String) async {
    await command(agent: id) { try await $0.pauseAgent(id: id) }
  }

  public func resume(agent id: String) async {
    await command(agent: id) { try await $0.resumeAgent(id: id) }
  }

  public func dismissNotice(forAgent id: String) {
    agentNotices[id] = nil
  }

  private func command(
    agent id: String,
    _ send: (any DesktopService) async throws -> Components.Schemas.Agent
  ) async {
    guard let agent = state.agents.first(where: { $0.id == id }), agent.pausable,
      !agentPending.contains(id)
    else { return }
    guard actionsEnabled else {
      agentNotices[id] = DesktopError.offline.localizedDescription
      return
    }
    agentNotices[id] = nil
    agentPending.insert(id)
    do {
      _ = try await send(service)
    } catch {
      agentPending.remove(id)
      handleAgentFailure(error, agent: id)
    }
  }

  private func handleAgentFailure(_ error: any Error, agent id: String) {
    guard let failure = error as? DesktopError else {
      agentNotices[id] = error.localizedDescription
      return
    }
    switch failure {
    case .unauthorised, .upgradeRequired: handle(failure)
    default: agentNotices[id] = failure.localizedDescription
    }
  }

  // MARK: Agents the store has not seen

  /// The id of the agent an `agent.updated` event names when the store holds no such agent.
  func unseenAgentID(in event: Components.Schemas.StreamEvent) -> String? {
    guard case .agent_updated(let updated) = event,
      !state.agents.contains(where: { $0.id == updated.agent.id })
    else { return nil }
    return updated.agent.id
  }

  /// Clears the pending mark an `agent.updated` event settles, and refetches the list when the
  /// event names an agent the store has not seen, so the list takes the server's order instead
  /// of the new agent being appended.
  func noteSettingsAndAgents(
    _ event: Components.Schemas.StreamEvent, unseenAgent: String?
  ) {
    switch event {
    case .agent_updated(let updated):
      agentPending.remove(updated.agent.id)
      agentsTouchedDuringRefetch?.insert(updated.agent.id)
    case .settings_updated:
      settingsPending = false
    case .heartbeat(let beat):
      eventLag = max(0, now().timeIntervalSince(beat.serverTime))
    default:
      break
    }
    if unseenAgent != nil { startAgentsRefetch() }
  }

  private func startAgentsRefetch() {
    guard agentsTouchedDuringRefetch == nil else { return }
    agentsTouchedDuringRefetch = []
    let mine = generation
    Task { [weak self] in
      guard let self else { return }
      do {
        let overview = try await service.agents()
        guard generation == mine else { return }
        replaceAgents(with: overview)
      } catch {
        Self.agentsLog.error(
          "agent list refetch failed: \(error.localizedDescription, privacy: .private)")
        if generation == mine { agentsTouchedDuringRefetch = nil }
      }
    }
  }

  /// Takes the server's list and order. An agent whose event arrived while the request was in
  /// flight keeps that newer copy, and one the response does not list yet stays at the end.
  private func replaceAgents(with overview: Components.Schemas.AgentsOverview) {
    let touched = agentsTouchedDuringRefetch ?? []
    let held = Dictionary(
      state.agents.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    let listed = Set(overview.agents.map(\.id))
    state.agents =
      overview.agents.map { touched.contains($0.id) ? (held[$0.id] ?? $0) : $0 }
      + state.agents.filter { !listed.contains($0.id) }
    if touched.isEmpty { state.costToday = overview.costToday }
    agentsTouchedDuringRefetch = nil
  }
}
