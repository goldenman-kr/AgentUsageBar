import Foundation

/// Fetches Claude subscription usage from the Anthropic OAuth endpoints using
/// the access token stored by the Claude Code CLI.
public struct UsageAPIClient {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// JSON decoder configured for the API's snake_case keys and ISO-8601 dates.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized ISO-8601 date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    private func authorizedRequest(_ url: URL, token: ClaudeToken) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(ClaudeAPI.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue(ClaudeAPI.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    /// Fetches the raw usage payload.
    public func fetchUsage(token: ClaudeToken) async throws -> UsageResponse {
        let (data, response) = try await dataAllowingNilBody(authorizedRequest(ClaudeAPI.usageURL, token: token))
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("HTTP 응답이 아님")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 { throw UsageError.tokenExpired(token.expiresAt) }
            if http.statusCode == 429 {
                throw UsageError.rateLimited(retryAfter: Self.retryAfterSeconds(from: http))
            }
            throw UsageError.httpStatus(http.statusCode, String(body.prefix(200)))
        }
        do {
            return try Self.makeDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageError.decoding("\(error)")
        }
    }

    /// Fetches the profile (only needed if you prefer the canonical plan label
    /// over the tier embedded in the token).
    public func fetchProfile(token: ClaudeToken) async throws -> ProfileResponse {
        let (data, response) = try await dataAllowingNilBody(authorizedRequest(ClaudeAPI.profileURL, token: token))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UsageError.httpStatus(code, "")
        }
        return try Self.makeDecoder().decode(ProfileResponse.self, from: data)
    }

    /// High-level convenience: reads the token from the Keychain, fetches usage,
    /// and returns a fully-resolved `UsageSnapshot`. The plan label is derived
    /// from the token's rate-limit tier (no extra network call).
    public func fetchSnapshot(now: Date = Date()) async throws -> UsageSnapshot {
        let token = try KeychainTokenStore.loadToken()
        if token.isExpired {
            throw UsageError.tokenExpired(token.expiresAt)
        }
        let usage = try await fetchUsage(token: token)
        let label = PlanLabel.from(rateLimitTier: token.rateLimitTier, subscriptionType: token.subscriptionType)
        return UsageSnapshot(usage: usage, planLabel: label, fetchedAt: now)
    }

    /// Parses a `Retry-After` header (delta-seconds form, or an HTTP-date) into
    /// seconds-from-now. Returns nil when absent/unparseable.
    static func retryAfterSeconds(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        guard let raw = (response.value(forHTTPHeaderField: "Retry-After") ??
                         response.value(forHTTPHeaderField: "retry-after"))?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) { return max(0, date.timeIntervalSince(now)) }
        return nil
    }

    /// `URLSession.data(for:)` wrapper that maps transport errors to `UsageError`.
    private func dataAllowingNilBody(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
    }
}
