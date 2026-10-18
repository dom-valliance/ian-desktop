import CryptoKit
import Foundation
import Security

/// A PKCE pair, RFC 7636 with the S256 method.
public struct PKCE: Equatable, Sendable {
  public let verifier: String
  public let challenge: String

  public init(verifier: String) {
    self.verifier = verifier
    self.challenge = Self.challenge(for: verifier)
  }

  /// A fresh pair from 32 random bytes, giving a 43 character verifier.
  public static func generate() -> PKCE {
    PKCE(verifier: randomToken(byteCount: 32))
  }

  public static func challenge(for verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
  }
}

/// Random bytes as unpadded base64url, for the PKCE verifier and the `state` value.
func randomToken(byteCount: Int) -> String {
  var bytes = [UInt8](repeating: 0, count: byteCount)
  let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
  precondition(status == errSecSuccess, "The system random number generator failed")
  return base64URL(Data(bytes))
}

func base64URL(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}
