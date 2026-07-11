import Foundation

public struct CodexToken: Sendable {
    public let accessToken: String
    public let accountID: String?
    public let workspaceID: String?
    public let planType: String?
    public let email: String?
    public let expiresAt: Date?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum CodexAuthStore {
    public static func loadToken(authURL: URL = CodexAuth.defaultAuthFileURL()) throws -> CodexToken {
        guard let data = try? Data(contentsOf: authURL) else {
            throw UsageError.tokenNotFound
        }
        return try decodeToken(from: data)
    }

    public static func decodeToken(from data: Data) throws -> CodexToken {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let access = tokens["access_token"] as? String,
            !access.isEmpty
        else {
            throw UsageError.decoding("Codex auth.json 형식이 올바르지 않습니다.")
        }

        let accessPayload = decodeJWTPayload(access)
        let idPayload = (tokens["id_token"] as? String).flatMap(decodeJWTPayload)
        let auth = mergedNamespace("https://api.openai.com/auth", primary: accessPayload, fallback: idPayload)
        let profile = mergedNamespace("https://api.openai.com/profile", primary: accessPayload, fallback: idPayload)
        let accountID = tokens["account_id"] as? String ?? auth?["chatgpt_account_id"] as? String
        let exp = (accessPayload?["exp"] as? Double)
            ?? (accessPayload?["exp"] as? Int).map(Double.init)

        return CodexToken(
            accessToken: access,
            accountID: accountID,
            workspaceID: accountID,
            planType: auth?["chatgpt_plan_type"] as? String,
            email: profile?["email"] as? String,
            expiresAt: exp.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 { base64.append(String(repeating: "=", count: padding)) }
        guard
            let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func mergedNamespace(
        _ key: String,
        primary: [String: Any]?,
        fallback: [String: Any]?
    ) -> [String: Any]? {
        var merged = fallback?[key] as? [String: Any] ?? [:]
        if let primaryValues = primary?[key] as? [String: Any] {
            for (key, value) in primaryValues {
                merged[key] = value
            }
        }
        return merged.isEmpty ? nil : merged
    }
}
