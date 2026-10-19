import Contract

extension DesktopAPI {
  public func agents() async throws -> Components.Schemas.AgentsOverview {
    try await call {
      switch try await client.getAgents() {
      case .ok(let response): return try response.body.json
      case .unauthorized: throw DesktopError.unauthorised
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }

  public func pauseAgent(id: String) async throws -> Components.Schemas.Agent {
    try await call {
      let output = try await client.pauseAgent(path: .init(agentId: id))
      switch output {
      case .ok(let response): return try response.body.json
      case .unauthorized: throw DesktopError.unauthorised
      case .forbidden(let response): throw rejection(403, response.body)
      case .notFound(let response):
        throw DesktopError.rejected(
          status: 404, detail: try? response.body.applicationProblemJson.detail)
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }

  public func resumeAgent(id: String) async throws -> Components.Schemas.Agent {
    try await call {
      let output = try await client.resumeAgent(path: .init(agentId: id))
      switch output {
      case .ok(let response): return try response.body.json
      case .unauthorized: throw DesktopError.unauthorised
      case .forbidden(let response): throw rejection(403, response.body)
      case .notFound(let response):
        throw DesktopError.rejected(
          status: 404, detail: try? response.body.applicationProblemJson.detail)
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }

  private func rejection(_ status: Int, _ body: Components.Responses.Forbidden.Body)
    -> DesktopError
  {
    .rejected(status: status, detail: try? body.applicationProblemJson.detail)
  }
}
