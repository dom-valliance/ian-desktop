import Contract

extension DesktopAPI {
  public func recordSession(_ heartbeat: Components.Schemas.SessionHeartbeat) async throws {
    try await call {
      switch try await client.recordSession(body: .json(heartbeat)) {
      case .noContent: return
      case .badRequest(let response):
        throw DesktopError.rejected(
          status: 400, detail: try? response.body.applicationProblemJson.detail)
      case .unauthorized: throw DesktopError.unauthorised
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }
}
