import Auth
import Contract
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// `DesktopService` over the generated client and an ephemeral `URLSession`.
public struct DesktopAPI: DesktopService {
  private let client: Contract.Client
  private let tokens: any TokenProvider

  /// - Parameters:
  ///   - session: Must come from `URLSessionConfiguration.ephemeral`, so no response is cached on
  ///     disk (AGENTS.md non-negotiable 5).
  ///   - clientVersion: The app's version, sent as `Desktop-Client-Version` on every request.
  public init(
    baseURL: URL,
    tokens: any TokenProvider,
    clientVersion: String,
    session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.tokens = tokens
    self.client = Contract.Client(
      serverURL: baseURL,
      configuration: Configuration(dateTranscoder: .iso8601WithFractionalSeconds),
      transport: URLSessionTransport(configuration: .init(session: session)),
      middlewares: [RequestHeadersMiddleware(tokens: tokens, clientVersion: clientVersion)])
  }

  /// The profile's api, with its own token provider.
  public init(
    profile: EnvironmentProfile,
    tokens: any TokenProvider,
    clientVersion: String
  ) {
    self.init(baseURL: profile.baseURL, tokens: tokens, clientVersion: clientVersion)
  }

  public func me() async throws -> Components.Schemas.Me {
    try await call {
      switch try await client.getMe() {
      case .ok(let response): return try response.body.json
      case .unauthorized: throw DesktopError.unauthorised
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }

  public func snapshot() async throws -> Components.Schemas.Snapshot {
    try await call {
      switch try await client.getSnapshot() {
      case .ok(let response): return try response.body.json
      case .unauthorized: throw DesktopError.unauthorised
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }

  public func runAction(
    itemID: String, actionID: String, version: Int, until: Date?, note: String?
  ) async throws -> String {
    try await call {
      let output = try await client.runItemAction(
        path: .init(itemId: itemID, actionId: actionID),
        body: .json(.init(version: version, until: until, note: note)))
      switch output {
      case .ok(let response): return try response.body.json.correlationId
      case .accepted(let response): return try response.body.json.correlationId
      case .badRequest(let response):
        throw DesktopError.rejected(
          status: 400, detail: try? response.body.applicationProblemJson.detail)
      case .notFound(let response):
        throw DesktopError.rejected(
          status: 404, detail: try? response.body.applicationProblemJson.detail)
      case .unauthorized: throw DesktopError.unauthorised
      case .conflict(let response):
        throw DesktopError.conflict(item: try response.body.applicationProblemJson.value2.item)
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
  }

  public func stream(
    lastEventID: String?
  ) async throws -> AsyncThrowingStream<StreamMessage, any Error> {
    let body: HTTPBody = try await call {
      switch try await client.streamEvents(headers: .init(lastEventID: lastEventID)) {
      case .ok(let response): return try response.body.textEventStream
      case .unauthorized: throw DesktopError.unauthorised
      case .gone: throw DesktopError.gone
      case .upgradeRequired(let response): throw upgrade(response)
      case .undocumented(let status, _): throw DesktopError.unexpectedStatus(status)
      }
    }
    return AsyncThrowingStream { continuation in
      let reader = Task {
        let decoder = StreamMessageDecoder()
        do {
          for try await event in body.asDecodedServerSentEvents() {
            continuation.yield(decoder.message(for: event))
          }
          continuation.finish()
        } catch {
          continuation.finish(
            throwing: Task.isCancelled ? CancellationError() : DesktopError(mapping: error))
        }
      }
      continuation.onTermination = { _ in reader.cancel() }
    }
  }

  public func signIn() async throws {
    try await tokens.signIn()
  }

  public func signOut() async {
    await tokens.signOut()
  }

  private func call<Result: Sendable>(
    _ operation: () async throws -> Result
  ) async throws -> Result {
    do {
      return try await operation()
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw DesktopError(mapping: error)
    }
  }

  private func upgrade(_ response: Components.Responses.UpgradeRequired) -> DesktopError {
    let minimum = try? response.body.applicationProblemJson.value2.minClientVersion
    return .upgradeRequired(minClientVersion: minimum)
  }
}

extension DesktopError {
  /// Reads through the runtime's `ClientError` wrapper to the cause.
  init(mapping error: any Error) {
    var cause = error
    while let wrapped = cause as? OpenAPIRuntime.ClientError { cause = wrapped.underlyingError }
    switch cause {
    case let known as DesktopError: self = known
    case AuthError.signInRequired: self = .unauthorised
    case is URLError: self = .offline
    case is DecodingError: self = .unreadableResponse
    default: self = .failed(cause.localizedDescription)
    }
  }
}
