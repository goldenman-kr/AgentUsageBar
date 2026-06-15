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

/// The fully-resolved snapshot the menu-bar app fetches, persists to the App
/// Group container, and that the widget renders. Keeping the widget on a flat
/// persisted snapshot means the widget never needs network or Keychain access.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let planLabel: String
    public let session: Metric
    public let weeklyAll: Metric
    public let weeklySonnet: Metric?
    public let weeklyOpus: Metric?
    public let extra: ExtraInfo?
    /// Non-nil when the most recent refresh failed; lets the UI show a reason
    /// while still rendering the last-known good numbers.
    public let errorMessage: String?

    public init(
        fetchedAt: Date,
        planLabel: String,
        session: Metric,
        weeklyAll: Metric,
        weeklySonnet: Metric?,
        weeklyOpus: Metric?,
        extra: ExtraInfo?,
        errorMessage: String? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.planLabel = planLabel
        self.session = session
        self.weeklyAll = weeklyAll
        self.weeklySonnet = weeklySonnet
        self.weeklyOpus = weeklyOpus
        self.extra = extra
        self.errorMessage = errorMessage
    }

    /// Builds a display snapshot from the raw API response.
    public init(usage: UsageResponse, planLabel: String, fetchedAt: Date) {
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
        self.errorMessage = nil
    }

    /// Returns a copy carrying an error message (used when a refresh fails but
    /// we still have prior numbers, or as a zeroed placeholder).
    public func withError(_ message: String) -> UsageSnapshot {
        UsageSnapshot(
            fetchedAt: fetchedAt,
            planLabel: planLabel,
            session: session,
            weeklyAll: weeklyAll,
            weeklySonnet: weeklySonnet,
            weeklyOpus: weeklyOpus,
            extra: extra,
            errorMessage: message
        )
    }

    /// Placeholder shown before the first successful fetch (and in widget previews).
    public static func placeholder(planLabel: String = "Claude", error: String? = nil) -> UsageSnapshot {
        UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 0),
            planLabel: planLabel,
            session: Metric(utilization: 0, resetsAt: nil),
            weeklyAll: Metric(utilization: 0, resetsAt: nil),
            weeklySonnet: Metric(utilization: 0, resetsAt: nil),
            weeklyOpus: nil,
            extra: nil,
            errorMessage: error
        )
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
            return "Claude 인증 토큰을 찾을 수 없습니다. Claude Code 또는 데스크톱 앱에 로그인하세요."
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
