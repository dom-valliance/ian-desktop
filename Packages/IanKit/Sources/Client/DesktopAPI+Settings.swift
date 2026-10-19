import Contract

extension DesktopAPI {
  public func updateSettings(
    _ patch: Components.Schemas.SettingsPatch
  ) async throws -> Components.Schemas.Settings {
    try await call {
      switch try await client.updateSettings(body: .json(patch)) {
      case .ok(let response): return try response.body.json
      case .badRequest(let response):
        throw DesktopError.rejected(
          status: 400, detail: try? response.body.applicationProblemJson.detail)
      case .unprocessableContent(let response):
        throw DesktopError.rejected(
          status: 422, detail: try? response.body.applicationProblemJson.detail)
      case .unauthorized: throw DesktopError.unauthorised
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }
}
