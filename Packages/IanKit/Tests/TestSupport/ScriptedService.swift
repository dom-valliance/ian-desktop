import Client
import Contract
import Foundation

/// A `DesktopService` the test scripts. Each call to `stream` takes the next planned stream, and
/// once the plan is empty a stream stays open and silent until it is cancelled.
public final class ScriptedService: DesktopService, @unchecked Sendable {
  public enum StreamPlan: Sendable {
    case messages(AsyncThrowingStream<StreamMessage, any Error>)
    case fail(DesktopError)
  }

  public struct ActionCall: Equatable, Sendable {
    public let itemID: String
    public let actionID: String
    public let version: Int
    public let until: Date?
    public let note: String?
  }

  // Every stored property is read and written only while holding `lock`.
  private let lock = NSLock()
  private var meResults: [Result<Components.Schemas.Me, DesktopError>]
  private var snapshotResults: [Result<Components.Schemas.Snapshot, DesktopError>]
  private var streamPlans: [StreamPlan] = []
  private var actionResult: @Sendable (ActionCall) async throws -> String = { _ in "corr_1" }
  private var _snapshotCalls = 0
  private var _streamCalls: [String?] = []
  private var _actionCalls: [ActionCall] = []
  private var handoffResult: @Sendable (HandoffCall) async throws -> String = { _ in "corr_h" }
  private var _handoffCalls: [HandoffCall] = []
  private var _signOuts = 0
  private var _signIns = 0
  private var signInFailure: (any Error)?
  private var snapshotHook: (@Sendable (Int) async -> Void)?
  private var signInHook: (@Sendable () async -> Void)?

  public init(
    me: Components.Schemas.Me = Fixtures.me(),
    snapshots: [Result<Components.Schemas.Snapshot, DesktopError>] = [
      .success(Fixtures.snapshot())
    ]
  ) {
    meResults = [.success(me)]
    snapshotResults = snapshots
  }

  public var snapshotCalls: Int { lock.withLock { _snapshotCalls } }
  public var streamCalls: [String?] { lock.withLock { _streamCalls } }
  public var actionCalls: [ActionCall] { lock.withLock { _actionCalls } }
  public var signOuts: Int { lock.withLock { _signOuts } }
  public var signIns: Int { lock.withLock { _signIns } }

  /// Queues the stream the next `stream` call returns, and gives back its feed.
  @discardableResult
  public func planStream() -> AsyncThrowingStream<StreamMessage, any Error>.Continuation {
    let (stream, feed) = AsyncThrowingStream<StreamMessage, any Error>.makeStream()
    lock.withLock { streamPlans.append(.messages(stream)) }
    return feed
  }

  public func planStreamFailure(_ error: DesktopError) {
    lock.withLock { streamPlans.append(.fail(error)) }
  }

  public func planMe(_ result: Result<Components.Schemas.Me, DesktopError>) {
    lock.withLock { meResults = [result] }
  }

  public func planSnapshots(_ results: [Result<Components.Schemas.Snapshot, DesktopError>]) {
    lock.withLock { snapshotResults = results }
  }

  public func planAction(_ result: @escaping @Sendable (ActionCall) async throws -> String) {
    lock.withLock { actionResult = result }
  }

  /// Runs after a snapshot call has taken its planned result and before it returns, with the
  /// call's number from 1. Lets a test hold one call while others complete.
  public func planSnapshotHook(_ hook: @escaping @Sendable (Int) async -> Void) {
    lock.withLock { snapshotHook = hook }
  }

  /// Runs inside `signIn`, so a test can hold a sign-in open.
  public func planSignInHook(_ hook: @escaping @Sendable () async -> Void) {
    lock.withLock { signInHook = hook }
  }

  public func planSignInFailure(_ error: any Error) {
    lock.withLock { signInFailure = error }
  }

  public func me() async throws -> Components.Schemas.Me {
    let result = lock.withLock { meResults[0] }
    return try result.get()
  }

  /// Answers with each planned snapshot in turn, then repeats the last.
  public func snapshot() async throws -> Components.Schemas.Snapshot {
    let (result, number, hook) = lock.withLock {
      _snapshotCalls += 1
      let next = snapshotResults.count > 1 ? snapshotResults.removeFirst() : snapshotResults[0]
      return (next, _snapshotCalls, snapshotHook)
    }
    await hook?(number)
    return try result.get()
  }

  public func runAction(
    itemID: String, actionID: String, version: Int, until: Date?, note: String?
  ) async throws -> String {
    let call = ActionCall(
      itemID: itemID, actionID: actionID, version: version, until: until, note: note)
    let handler = lock.withLock {
      _actionCalls.append(call)
      return actionResult
    }
    return try await handler(call)
  }

  public func stream(
    lastEventID: String?
  ) async throws -> AsyncThrowingStream<StreamMessage, any Error> {
    let plan = lock.withLock {
      _streamCalls.append(lastEventID)
      return streamPlans.isEmpty ? nil : streamPlans.removeFirst()
    }
    switch plan {
    case .messages(let stream): return stream
    case .fail(let error): throw error
    case nil: return AsyncThrowingStream { _ in }
    }
  }

  public func signIn() async throws {
    let (failure, hook) = lock.withLock {
      _signIns += 1
      return (signInFailure, signInHook)
    }
    await hook?()
    if let failure { throw failure }
  }

  public func signOut() async {
    lock.withLock { _signOuts += 1 }
  }

  // MARK: Hand to Ian

  public struct HandoffCall: Equatable, Sendable {
    public let itemID: String
    public let instruction: String?

    public init(itemID: String, instruction: String?) {
      self.itemID = itemID
      self.instruction = instruction
    }
  }

  public var handoffCalls: [HandoffCall] { lock.withLock { _handoffCalls } }

  public func planHandoff(_ result: @escaping @Sendable (HandoffCall) async throws -> String) {
    lock.withLock { handoffResult = result }
  }

  public func handOff(itemID: String, instruction: String?) async throws -> String {
    let call = HandoffCall(itemID: itemID, instruction: instruction)
    let handler = lock.withLock {
      _handoffCalls.append(call)
      return handoffResult
    }
    return try await handler(call)
  }
}
