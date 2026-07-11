import Foundation

/// Fetches Codex usage by calling the exact backend endpoint the Codex CLI's
/// TUI `/status` card reads (`GET /backend-api/wham/usage`). This returns the
/// live 5-hour / weekly rate-limit windows, per-model limits, plan type and
/// credit balance — identical to what `/status` shows — without spawning the
/// CLI or mining its local logs. The OAuth `access_token` and `account_id` are
/// reused from `~/.codex/auth.json`.
public struct CodexUsageAPIClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchSnapshot(now: Date = Date()) async throws -> UsageSnapshot {
        let token = try CodexAuthStore.loadToken()
        if token.isExpired {
            throw UsageError.tokenExpired(token.expiresAt ?? now)
        }

        var req = URLRequest(url: CodexAuth.usageURL())
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(CodexAuth.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = token.accountID, !accountID.isEmpty {
            req.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("HTTP 응답이 아님")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw UsageError.tokenExpired(token.expiresAt ?? now) }
            if http.statusCode == 429 {
                throw UsageError.rateLimited(retryAfter: UsageAPIClient.retryAfterSeconds(from: http))
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageError.httpStatus(http.statusCode, String(body.prefix(200)))
        }

        let summary = try Self.parseUsagePayload(data: data, accountID: token.accountID, now: now)
        let planType = summary.rateLimitPlanType ?? token.planType
        return UsageSnapshot(
            codex: summary,
            planLabel: CodexPlanLabel.from(planType: planType),
            fetchedAt: now
        )
    }

    /// Maps the `wham/usage` JSON payload into a `CodexUsageSummary`.
    static func parseUsagePayload(data: Data, accountID: String?, now: Date) throws -> CodexUsageSummary {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.decoding("Codex usage 응답을 해석할 수 없습니다.")
        }

        let rateLimit = root["rate_limit"] as? [String: Any]
        let primary = parseWindow(rateLimit?["primary_window"] as? [String: Any])
        let secondary = parseWindow(rateLimit?["secondary_window"] as? [String: Any])
        let additional = parseAdditional(root["additional_rate_limits"])
        let credits = parseCredits(root["credits"] as? [String: Any])

        guard primary != nil || secondary != nil || !additional.isEmpty || credits != nil else {
            throw UsageError.decoding("Codex usage 응답에 rate limit 정보가 없습니다.")
        }

        return CodexUsageSummary(
            source: "Codex /status",
            workspaceID: accountID,
            periodStart: nil,
            periodEnd: now,
            primaryRateLimit: primary,
            secondaryRateLimit: secondary,
            additionalRateLimits: additional,
            rateLimitPlanType: root["plan_type"] as? String,
            credits: credits,
            threads: nil,
            turns: nil,
            inputTokens: nil,
            cachedInputTokens: nil,
            outputTokens: nil
        )
    }

    private static func parseWindow(_ value: [String: Any]?) -> CodexUsageSummary.RateLimit? {
        guard let value, let usedPercent = number(value["used_percent"]) else { return nil }
        let windowMinutes = number(value["limit_window_seconds"]).flatMap(windowMinutes(fromSeconds:))
        let resetsAt = number(value["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        return CodexUsageSummary.RateLimit(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func parseAdditional(_ value: Any?) -> [CodexUsageSummary.NamedRateLimit] {
        guard let array = value as? [[String: Any]] else { return [] }
        var result: [CodexUsageSummary.NamedRateLimit] = []
        for entry in array {
            let name = (entry["limit_name"] as? String)
                ?? (entry["metered_feature"] as? String)
                ?? "기타"
            let rateLimit = entry["rate_limit"] as? [String: Any]
            let primary = parseWindow(rateLimit?["primary_window"] as? [String: Any])
            let secondary = parseWindow(rateLimit?["secondary_window"] as? [String: Any])
            guard primary != nil || secondary != nil else { continue }
            result.append(CodexUsageSummary.NamedRateLimit(
                name: name,
                primary: primary,
                secondary: secondary
            ))
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Only surfaces a credit balance when the account actually has purchased
    /// credits, so the menu bar doesn't render a misleading "0 cr" for plans
    /// that bill purely on rate-limit windows.
    private static func parseCredits(_ value: [String: Any]?) -> Double? {
        guard let value, (value["has_credits"] as? Bool) == true else { return nil }
        if let balance = number(value["balance"]) { return balance }
        if let balanceString = value["balance"] as? String { return Double(balanceString) }
        return nil
    }

    /// Codex rounds partial windows up, mirroring `(secs + 59) / 60` in
    /// `codex-rs` so reset windows match the CLI exactly.
    private static func windowMinutes(fromSeconds seconds: Double) -> Int? {
        let secs = Int(seconds)
        guard secs > 0 else { return nil }
        return (secs + 59) / 60
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
