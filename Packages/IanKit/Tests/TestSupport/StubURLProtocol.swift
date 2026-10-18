import Foundation

/// What a stubbed request answers with.
public struct StubResponse: Sendable {
  public var status: Int
  public var headers: [String: String]
  public var body: Data
  /// When set, the request fails with this error after the body is delivered.
  public var failure: URLError?

  public init(
    status: Int = 200, headers: [String: String] = [:], body: Data = Data(),
    failure: URLError? = nil
  ) {
    self.status = status
    self.headers = headers
    self.body = body
    self.failure = failure
  }

  public static func json(_ text: String, status: Int = 200) -> StubResponse {
    StubResponse(
      status: status, headers: ["Content-Type": "application/json"], body: Data(text.utf8))
  }

  public static func problem(_ text: String, status: Int) -> StubResponse {
    StubResponse(
      status: status, headers: ["Content-Type": "application/problem+json"], body: Data(text.utf8))
  }

  public static func eventStream(_ text: String) -> StubResponse {
    StubResponse(
      status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(text.utf8))
  }
}

/// Answers requests from a closure, so tests exercise real `URLSession` code with no network.
/// Each session carries its own id in a header, so tests can run in parallel and the handler sees
/// requests for any host.
public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  public typealias Handler = @Sendable (URLRequest) -> StubResponse

  private static let sessionHeader = "X-Stub-Session"

  // `handlers` is read and written only while holding `lock`.
  private static let lock = NSLock()
  nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

  /// A session on `URLSessionConfiguration.ephemeral` that routes every request to `handler`, and
  /// the base URL to send them to.
  public static func session(handler: @escaping Handler) -> (session: URLSession, baseURL: URL) {
    let id = UUID().uuidString
    lock.withLock { handlers[id] = handler }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.httpAdditionalHeaders = [sessionHeader: id]
    return (URLSession(configuration: configuration), URL(string: "https://stub.test")!)
  }

  public override class func canInit(with request: URLRequest) -> Bool { true }

  public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  public override func startLoading() {
    guard let url = request.url,
      let id = request.value(forHTTPHeaderField: Self.sessionHeader),
      let handler = Self.lock.withLock({ Self.handlers[id] })
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let stubbed = handler(request)
    let response = HTTPURLResponse(
      url: url, statusCode: stubbed.status, httpVersion: "HTTP/1.1", headerFields: stubbed.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if !stubbed.body.isEmpty { client?.urlProtocol(self, didLoad: stubbed.body) }
    if let failure = stubbed.failure {
      client?.urlProtocol(self, didFailWithError: failure)
    } else {
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  public override func stopLoading() {}
}

/// The body of a request as text. `URLProtocol` receives bodies as streams, not `httpBody`.
public func bodyText(of request: URLRequest) -> String {
  if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
  guard let stream = request.httpBodyStream else { return "" }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    if count <= 0 { break }
    data.append(buffer, count: count)
  }
  return String(decoding: data, as: UTF8.self)
}
