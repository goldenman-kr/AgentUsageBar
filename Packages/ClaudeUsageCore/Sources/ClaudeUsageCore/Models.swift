import Foundation

// MARK: - Raw API responses

/// Raw decode of `GET /api/oauth/usage`.
///
/// Every bucket may be entirely `null` (e.g. `seven_day_opus` for accounts that
/// haven't used Opus), and `resets_at` is `null` until a bucket is first used.
public struct UsageResponse: Codable, Sendable {
    public struct Bucket: Codable, Sendable {
        /// Percentage used, 0–100.
        public let utilization: Double?
        public let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct ExtraUsage: Codable, Sendable {
        public let isEnabled: Bool?
        public let monthlyLimit: Double?
        public let usedCredits: Double?
        public let utilization: Double?
        public let currency: String?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
            case currency
        }
    }

    public let fiveHour: Bucket?
    public let sevenDay: Bucket?
    public let sevenDayOpus: Bucket?
    public let sevenDaySonnet: Bucket?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

/// Raw decode of the subset of `GET /api/oauth/profile` we need for the plan label.
public struct ProfileResponse: Codable, Sendable {
    public struct Organization: Codable, Sendable {
        public let rateLimitTier: String?
        public let organizationType: String?

        enum CodingKeys: String, CodingKey {
            case rateLimitTier = "rate_limit_tier"
            case organizationType = "organization_type"
        }
    }

    public struct Account: Codable, Sendable {
        public let hasClaudeMax: Bool?
        public let hasClaudePro: Bool?

        enum CodingKeys: String, CodingKey {
            case hasClaudeMax = "has_claude_max"
            case hasClaudePro = "has_claude_pro"
        }
    }

    public let organization: Organization?
    public let account: Account?
}

// MARK: - Snapshot (persisted + rendered)

public enum UsageProvider: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    public var title: String { "\(displayName) 사용량" }
}

/// A single usage metric ready for display.
public struct Metric: Codable, Sendable, Equatable {
    /// 0–100.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    /// Clamped fraction in 0...1, suitable for a progress bar.
    public var fraction: Double { min(max(utilization / 100.0, 0), 1) }
}

/// Optional extra-usage (pay-as-you-go credits) summary.
public struct ExtraInfo: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let monthlyLimit: Double
    public let usedCredits: Double
    public let currency: String

    public init(isEnabled: Bool, monthlyLimit: Double, usedCredits: Double, currency: String) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.currency = currency
    }
}

/// Codex exposes rate-limit buckets similar to `/status`: account-wide
/// 5-hour/weekly limits plus optional model-specific limits.
public struct CodexUsageSummary: Codable, Sendable, Equatable {
    public struct RateLimit: Codable, Sendable, Equatable {
        public let usedPercent: Double
        public let windowMinutes: Int?
        public let resetsAt: Date?

        public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.windowMinutes = windowMinutes
            self.resetsAt = resetsAt
        }

        public var metric: Metric {
            Metric(utilization: usedPercent, resetsAt: resetsAt)
        }

        public var inferredWindowLabel: String? {
            guard let windowMinutes, windowMinutes > 0 else { return nil }
            if windowMinutes >= 7 * 24 * 60 {
                return "주간"
            }
            if windowMinutes % (24 * 60) == 0 {
                return "\(windowMinutes / (24 * 60))일"
            }
            if windowMinutes % 60 == 0 {
                return "\(windowMinutes / 60)시간"
            }
            return "\(windowMinutes)분"
        }

        public var usesRelativeResetCaption: Bool {
            guard let windowMinutes else { return false }
            return windowMinutes < 24 * 60
        }
    }

    public struct NamedRateLimit: Codable, Sendable, Equatable, Identifiable {
        public let name: String
        public let primary: RateLimit?
        public let secondary: RateLimit?

        public init(name: String, primary: RateLimit?, secondary: RateLimit?) {
            self.name = name
            self.primary = primary
            self.secondary = secondary
        }

        public var id: String { name }
    }

    public let source: String
    public let workspaceID: String?
    public let periodStart: Date?
    public let periodEnd: Date?
    public let primaryRateLimit: RateLimit?
    public let secondaryRateLimit: RateLimit?
    public let additionalRateLimits: [NamedRateLimit]
    public let rateLimitPlanType: String?
    public let credits: Double?
    public let threads: Int?
    public let turns: Int?
    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    public let outputTokens: Int?
    public let limitCredits: Double?

    public init(
        source: String,
        workspaceID: String?,
        periodStart: Date?,
        periodEnd: Date?,
        primaryRateLimit: RateLimit? = nil,
        secondaryRateLimit: RateLimit? = nil,
        additionalRateLimits: [NamedRateLimit] = [],
        rateLimitPlanType: String? = nil,
        credits: Double?,
        threads: Int?,
        turns: Int?,
        inputTokens: Int?,
        cachedInputTokens: Int?,
        outputTokens: Int?,
        limitCredits: Double? = nil
    ) {
        self.source = source
        self.workspaceID = workspaceID
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.primaryRateLimit = primaryRateLimit
        self.secondaryRateLimit = secondaryRateLimit
        self.additionalRateLimits = additionalRateLimits
        self.rateLimitPlanType = rateLimitPlanType
        self.credits = credits
        self.threads = threads
        self.turns = turns
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.limitCredits = limitCredits
    }

    public var totalTokens: Int? {
        let total = (inputTokens ?? 0) + (cachedInputTokens ?? 0) + (outputTokens ?? 0)
        return total > 0 ? total : nil
    }

    public var creditMetric: Metric? {
        guard let credits, let limitCredits, limitCredits > 0 else { return nil }
        return Metric(utilization: credits / limitCredits * 100, resetsAt: periodEnd)
    }

    public var bestPrimaryMetric: Metric? {
        primaryRateLimit?.metric ?? creditMetric
    }

    public var bestSecondaryMetric: Metric? {
        secondaryRateLimit?.metric
    }

    enum CodingKeys: String, CodingKey {
        case source, workspaceID, periodStart, periodEnd, primaryRateLimit, secondaryRateLimit
        case additionalRateLimits, rateLimitPlanType, credits, threads, turns, inputTokens
        case cachedInputTokens, outputTokens, limitCredits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        periodStart = try c.decodeIfPresent(Date.self, forKey: .periodStart)
        periodEnd = try c.decodeIfPresent(Date.self, forKey: .periodEnd)
        primaryRateLimit = try c.decodeIfPresent(RateLimit.self, forKey: .primaryRateLimit)
        secondaryRateLimit = try c.decodeIfPresent(RateLimit.self, forKey: .secondaryRateLimit)
        if let named = try c.decodeIfPresent([NamedRateLimit].self, forKey: .additionalRateLimits) {
            additionalRateLimits = named
        } else if let legacy = try c.decodeIfPresent([String: RateLimit].self, forKey: .additionalRateLimits) {
            additionalRateLimits = legacy
                .map { NamedRateLimit(name: $0.key, primary: $0.value, secondary: nil) }
                .sorted { $0.name < $1.name }
        } else {
            additionalRateLimits = []
        }
        rateLimitPlanType = try c.decodeIfPresent(String.self, forKey: .rateLimitPlanType)
        credits = try c.decodeIfPresent(Double.self, forKey: .credits)
        threads = try c.decodeIfPresent(Int.self, forKey: .threads)
        turns = try c.decodeIfPresent(Int.self, forKey: .turns)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
        cachedInputTokens = try c.decodeIfPresent(Int.self, forKey: .cachedInputTokens)
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
        limitCredits = try c.decodeIfPresent(Double.self, forKey: .limitCredits)
    }
}

/// The fully-resolved snapshot the menu-bar app fetches, persists to the App
/// Group container, and that the widget renders. Keeping the widget on a flat
/// persisted snapshot means the widget never needs network or Keychain access.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let provider: UsageProvider
    public let fetchedAt: Date
    public let planLabel: String
    public let session: Metric
    public let weeklyAll: Metric
    public let weeklySonnet: Metric?
    public let weeklyOpus: Metric?
    public let extra: ExtraInfo?
    public let codex: CodexUsageSummary?
    /// Non-nil when the most recent refresh failed; lets the UI show a reason
    /// while still rendering the last-known good numbers.
    public let errorMessage: String?

    public init(
        provider: UsageProvider = .claude,
        fetchedAt: Date,
        planLabel: String,
        session: Metric,
        weeklyAll: Metric,
        weeklySonnet: Metric?,
        weeklyOpus: Metric?,
        extra: ExtraInfo?,
        codex: CodexUsageSummary? = nil,
        errorMessage: String? = nil
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.planLabel = planLabel
        self.session = session
        self.weeklyAll = weeklyAll
        self.weeklySonnet = weeklySonnet
        self.weeklyOpus = weeklyOpus
        self.extra = extra
        self.codex = codex
        self.errorMessage = errorMessage
    }

    /// Builds a display snapshot from the raw API response.
    public init(usage: UsageResponse, planLabel: String, fetchedAt: Date) {
        self.provider = .claude
        self.fetchedAt = fetchedAt
        self.planLabel = planLabel
        self.session = Metric(
            utilization: usage.fiveHour?.utilization ?? 0,
            resetsAt: usage.fiveHour?.resetsAt
        )
        self.weeklyAll = Metric(
            utilization: usage.sevenDay?.utilization ?? 0,
            resetsAt: usage.sevenDay?.resetsAt
        )
        self.weeklySonnet = usage.sevenDaySonnet.map {
            Metric(utilization: $0.utilization ?? 0, resetsAt: $0.resetsAt)
        }
        self.weeklyOpus = usage.sevenDayOpus.map {
            Metric(utilization: $0.utilization ?? 0, resetsAt: $0.resetsAt)
        }
        if let e = usage.extraUsage, e.isEnabled == true {
            self.extra = ExtraInfo(
                isEnabled: true,
                monthlyLimit: e.monthlyLimit ?? 0,
                usedCredits: e.usedCredits ?? 0,
                currency: e.currency ?? "USD"
            )
        } else {
            self.extra = nil
        }
        self.codex = nil
        self.errorMessage = nil
    }

    public init(codex: CodexUsageSummary, planLabel: String, fetchedAt: Date) {
        self.provider = .codex
        self.fetchedAt = fetchedAt
        self.planLabel = CodexPlanLabel.from(planType: codex.rateLimitPlanType) == "Codex" ? planLabel : CodexPlanLabel.from(planType: codex.rateLimitPlanType)
        let primary = codex.bestPrimaryMetric ?? Metric(utilization: 0, resetsAt: codex.periodEnd)
        self.session = primary
        self.weeklyAll = codex.bestSecondaryMetric ?? primary
        self.weeklySonnet = nil
        self.weeklyOpus = nil
        self.extra = nil
        self.codex = codex
        self.errorMessage = nil
    }

    /// Returns a copy carrying an error message (used when a refresh fails but
    /// we still have prior numbers, or as a zeroed placeholder).
    public func withError(_ message: String) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            fetchedAt: fetchedAt,
            planLabel: planLabel,
            session: session,
            weeklyAll: weeklyAll,
            weeklySonnet: weeklySonnet,
            weeklyOpus: weeklyOpus,
            extra: extra,
            codex: codex,
            errorMessage: message
        )
    }

    /// Placeholder shown before the first successful fetch (and in widget previews).
    public static func placeholder(
        provider: UsageProvider = .claude,
        planLabel: String? = nil,
        error: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            fetchedAt: Date(timeIntervalSince1970: 0),
            planLabel: planLabel ?? provider.displayName,
            session: Metric(utilization: 0, resetsAt: nil),
            weeklyAll: Metric(utilization: 0, resetsAt: nil),
            weeklySonnet: Metric(utilization: 0, resetsAt: nil),
            weeklyOpus: nil,
            extra: nil,
            codex: nil,
            errorMessage: error
        )
    }

    enum CodingKeys: String, CodingKey {
        case provider, fetchedAt, planLabel, session, weeklyAll, weeklySonnet, weeklyOpus, extra, codex, errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(UsageProvider.self, forKey: .provider) ?? .claude
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        planLabel = try c.decode(String.self, forKey: .planLabel)
        session = try c.decode(Metric.self, forKey: .session)
        weeklyAll = try c.decode(Metric.self, forKey: .weeklyAll)
        weeklySonnet = try c.decodeIfPresent(Metric.self, forKey: .weeklySonnet)
        weeklyOpus = try c.decodeIfPresent(Metric.self, forKey: .weeklyOpus)
        extra = try c.decodeIfPresent(ExtraInfo.self, forKey: .extra)
        codex = try c.decodeIfPresent(CodexUsageSummary.self, forKey: .codex)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

// MARK: - Errors

public enum UsageError: LocalizedError {
    case tokenNotFound
    case tokenExpired(Date)
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int, String)
    case decoding(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            return "인증 토큰을 찾을 수 없습니다. 선택한 도구에 먼저 로그인하세요."
        case .tokenExpired:
            return "토큰이 만료되었습니다. Claude Code 실행 시 자동으로 갱신됩니다."
        case .rateLimited(let retryAfter):
            if let s = retryAfter, s > 0 {
                let mins = Int((s / 60).rounded(.up))
                return "요청이 너무 많습니다 (HTTP 429). 약 \(mins)분 후 자동 재시도합니다."
            }
            return "요청이 너무 많습니다 (HTTP 429). 잠시 후 자동 재시도합니다."
        case .httpStatus(let code, _):
            return "서버 오류 (HTTP \(code))"
        case .decoding(let detail):
            return "응답 해석 실패: \(detail)"
        case .network(let detail):
            return "네트워크 오류: \(detail)"
        }
    }
}
