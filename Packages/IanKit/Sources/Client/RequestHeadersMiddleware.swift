import Auth
import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Adds `Authorization` and `Desktop-Client-Version` to every request.
struct RequestHeadersMiddleware: ClientMiddleware {
  let tokens: any TokenProvider
  let clientVersion: String

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    request.headerFields[.authorization] = "Bearer \(try await tokens.token())"
    request.headerFields[.desktopClientVersion] = clientVersion
    return try await next(request, body, baseURL)
  }
}

extension HTTPField.Name {
  static let desktopClientVersion = Self("Desktop-Client-Version")!
}
