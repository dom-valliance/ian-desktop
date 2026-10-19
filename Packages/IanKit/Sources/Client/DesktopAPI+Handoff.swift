import Contract
import Foundation

extension DesktopAPI {
  public func handOff(itemID: String, instruction: String?) async throws -> String {
    try await call {
      let output = try await client.handOff(
        body: .json(.init(itemId: itemID, instruction: instruction)))
      switch output {
      case .accepted(let response): return try response.body.json.correlationId
      case .badRequest(let response):
        throw DesktopError.rejected(
          status: 400, detail: try? response.body.applicationProblemJson.detail)
      case .notFound(let response):
        throw DesktopError.rejected(
          status: 404, detail: try? response.body.applicationProblemJson.detail)
      case .unauthorized: throw DesktopError.unauthorised
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }
}
