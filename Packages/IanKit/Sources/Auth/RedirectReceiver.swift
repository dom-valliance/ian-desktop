import Foundation
import Network

public struct RedirectResult: Sendable {
  /// The redirect URI the authorisation request named, which the token request repeats.
  public let redirectURI: URL
  /// The URL the browser was sent to, with `code` and `state` or `error`.
  public let callback: URL
}

/// Receives the browser's redirect after sign-in.
public protocol RedirectReceiver: Sendable {
  /// Starts listening, calls `whenListening` with the redirect URI so the caller can open the
  /// browser, then waits for the redirect.
  func receive(whenListening: @Sendable (URL) async -> Void) async throws -> RedirectResult
}

/// A listener on a random `localhost` port (spec section 8). It accepts one redirect, answers
/// the browser with a short page and stops.
public struct LoopbackRedirectReceiver: RedirectReceiver {
  private let timeout: Duration

  public init(timeout: Duration = .seconds(300)) {
    self.timeout = timeout
  }

  public func receive(
    whenListening: @Sendable (URL) async -> Void
  ) async throws -> RedirectResult {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    // Only 127.0.0.1, so nothing off this Mac can reach the listener.
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    let listener: NWListener
    do {
      listener = try NWListener(using: parameters)
    } catch {
      throw AuthError.listenerFailed(error.localizedDescription)
    }
    let queue = DispatchQueue(label: "ai.valliance.ian.auth.loopback")
    let (states, stateSink) = AsyncStream<NWListener.State>.makeStream()
    let (callbacks, callbackSink) = AsyncStream<URL>.makeStream(
      bufferingPolicy: .bufferingNewest(1))

    listener.stateUpdateHandler = { stateSink.yield($0) }
    listener.newConnectionHandler = { connection in
      Self.serve(connection, on: queue) { target in
        guard let port = listener.port,
          let url = URL(string: "http://localhost:\(port.rawValue)\(target)")
        else { return .notFound }
        let reply = Self.reply(for: url)
        if reply != .notFound {
          callbackSink.yield(url)
          callbackSink.finish()
        }
        return reply
      }
    }
    listener.start(queue: queue)
    defer {
      listener.cancel()
      stateSink.finish()
      callbackSink.finish()
    }

    let port = try await Self.waitForPort(of: listener, states: states)
    guard let redirectURI = URL(string: "http://localhost:\(port.rawValue)") else {
      throw AuthError.listenerFailed("the port \(port.rawValue) does not form a URL")
    }
    await whenListening(redirectURI)

    let callback = try await withThrowingTaskGroup(of: URL.self) { group in
      group.addTask {
        for await url in callbacks { return url }
        throw CancellationError()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw AuthError.timedOut
      }
      defer { group.cancelAll() }
      return try await group.next()!
    }
    return RedirectResult(redirectURI: redirectURI, callback: callback)
  }

  private static func waitForPort(
    of listener: NWListener, states: AsyncStream<NWListener.State>
  ) async throws -> NWEndpoint.Port {
    for await state in states {
      switch state {
      case .ready:
        if let port = listener.port { return port }
      case .failed(let error), .waiting(let error):
        throw AuthError.listenerFailed(error.localizedDescription)
      case .cancelled:
        throw CancellationError()
      default:
        continue
      }
    }
    throw CancellationError()
  }

  /// Reads the request line, hands its target to `accept`, and answers the browser.
  private static func serve(
    _ connection: NWConnection, on queue: DispatchQueue,
    accept: @escaping @Sendable (String) -> Reply
  ) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
      let target = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(requestTarget)
      let reply = target.map(accept) ?? .notFound
      let body: String
      switch reply {
      case .signedIn: body = "Ian has your sign-in. You can close this tab and return to the app."
      case .failed: body = "Sign-in failed. Close this tab and return to Ian for the reason."
      case .notFound: body = "Nothing to see here."
      }
      let response =
        "HTTP/1.1 \(reply == .notFound ? "404 Not Found" : "200 OK")\r\n"
        + "Content-Type: text/plain; charset=utf-8\r\n"
        + "Content-Length: \(body.utf8.count)\r\n"
        + "Cache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
      connection.send(
        content: Data(response.utf8),
        completion: .contentProcessed { _ in connection.cancel() })
    }
  }

  enum Reply: Equatable {
    case signedIn
    case failed
    case notFound
  }

  /// The target of a `GET` request line, such as `/?code=abc&state=xyz`.
  static func requestTarget(_ request: String) -> String? {
    guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
    let parts = line.split(separator: " ")
    guard parts.count >= 2, parts[0] == "GET" else { return nil }
    return String(parts[1])
  }

  /// A redirect carries a result. Browsers also ask for `/favicon.ico`, which is ignored.
  static func reply(for url: URL) -> Reply {
    let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.map(\.name)
    if names?.contains("error") == true { return .failed }
    return names?.contains("code") == true ? .signedIn : .notFound
  }
}
