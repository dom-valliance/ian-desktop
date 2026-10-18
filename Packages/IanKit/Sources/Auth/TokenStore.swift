import Foundation
import Security

public struct StoredTokens: Codable, Equatable, Sendable {
  public var accessToken: String
  public var refreshToken: String?
  public var expiresAt: Date

  public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
  }
}

/// Where tokens live between launches. The Keychain in the app, memory in tests.
public protocol TokenStore: Sendable {
  func load() throws -> StoredTokens?
  func save(_ tokens: StoredTokens) throws
  func clear() throws
}

/// Tokens as one generic password item, which works for an unsigned build (spec section 8).
public struct KeychainTokenStore: TokenStore {
  private static let account = "tokens"
  private let service: String

  /// - Parameter service: One per profile, such as `ai.valliance.ian.desktop.lance-dev`.
  public init(service: String) {
    self.service = service
  }

  public func load() throws -> StoredTokens? {
    var query = baseQuery
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return nil }
      return try? JSONDecoder().decode(StoredTokens.self, from: data)
    case errSecItemNotFound:
      return nil
    default:
      throw AuthError.keychain(status)
    }
  }

  public func save(_ tokens: StoredTokens) throws {
    let data = try JSONEncoder().encode(tokens)
    let update = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData: data] as CFDictionary
    )
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else { throw AuthError.keychain(update) }

    var attributes = baseQuery
    attributes[kSecValueData] = data
    attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let add = SecItemAdd(attributes as CFDictionary, nil)
    guard add == errSecSuccess else { throw AuthError.keychain(add) }
  }

  public func clear() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AuthError.keychain(status)
    }
  }

  private var baseQuery: [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: Self.account,
    ]
  }
}

/// Holds tokens for the life of the process. For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
  // Every access to `tokens` goes through `lock`.
  private let lock = NSLock()
  private var tokens: StoredTokens?

  public init(tokens: StoredTokens? = nil) {
    self.tokens = tokens
  }

  public func load() throws -> StoredTokens? {
    lock.withLock { tokens }
  }

  public func save(_ tokens: StoredTokens) throws {
    lock.withLock { self.tokens = tokens }
  }

  public func clear() throws {
    lock.withLock { tokens = nil }
  }
}
