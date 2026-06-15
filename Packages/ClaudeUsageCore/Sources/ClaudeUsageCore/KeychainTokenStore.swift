import Foundation
import Security

/// The OAuth credential the Claude Code CLI stores in the Keychain.
///
/// Stored as JSON under the generic-password service `Claude Code-credentials`:
/// ```json
/// { "claudeAiOauth": { "accessToken": "...", "refreshToken": "...",
///   "expiresAt": 1781514393211, "scopes": [...],
///   "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x" },
///   "organizationUuid": "..." }
/// ```
public struct ClaudeToken: Sendable {
    public let accessToken: String
    public let expiresAt: Date
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public var isExpired: Bool { expiresAt <= Date() }
}

/// Reads the Claude Code OAuth access token from the macOS Keychain.
///
/// This is intentionally **read-only**: the widget reuses whatever token Claude
/// Code / the desktop app already maintains. It never refreshes or rotates the
/// token, which would invalidate the refresh token those apps depend on.
public enum KeychainTokenStore {

    /// Decodes a credential blob. Exposed for testing.
    public static func decodeToken(from data: Data) throws -> ClaudeToken {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let access = oauth["accessToken"] as? String, !access.isEmpty
        else {
            throw UsageError.decoding("Keychain 자격 증명 형식이 올바르지 않습니다.")
        }
        // `expiresAt` is epoch milliseconds. Accept Double or Int.
        let expiresMs: Double
        if let n = oauth["expiresAt"] as? Double {
            expiresMs = n
        } else if let n = oauth["expiresAt"] as? Int {
            expiresMs = Double(n)
        } else {
            expiresMs = 0
        }
        return ClaudeToken(
            accessToken: access,
            expiresAt: expiresMs > 0 ? Date(timeIntervalSince1970: expiresMs / 1000.0) : .distantFuture,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    /// Loads and decodes the active Claude Code token from the Keychain.
    ///
    /// May trigger a one-time macOS Keychain access prompt the first time a new
    /// (re)signed build reads the item; choose "Always Allow".
    public static func loadToken(service: String = KeychainCoordinates.service) throws -> ClaudeToken {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            throw UsageError.tokenNotFound
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw UsageError.network("Keychain 접근 실패 (OSStatus \(status))")
        }
        return try decodeToken(from: data)
    }
}
