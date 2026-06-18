import XCTest
@testable import ClaudeUsageCore

final class ClaudeUsageCoreTests: XCTestCase {

    // MARK: Keychain token decoding

    func testDecodeToken() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat-XXXX",
            "refreshToken": "sk-ant-ort-YYYY",
            "expiresAt": 1781514393211,
            "scopes": ["user:inference", "user:profile"],
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x"
          },
          "organizationUuid": "00000000-0000-0000-0000-000000000000"
        }
        """.data(using: .utf8)!
        let token = try KeychainTokenStore.decodeToken(from: json)
        XCTAssertEqual(token.accessToken, "sk-ant-oat-XXXX")
        XCTAssertEqual(token.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(token.subscriptionType, "max")
        XCTAssertEqual(token.expiresAt.timeIntervalSince1970, 1781514393.211, accuracy: 0.01)
    }

    func testDecodeTokenRejectsMalformed() {
        let json = #"{ "foo": "bar" }"#.data(using: .utf8)!
        XCTAssertThrowsError(try KeychainTokenStore.decodeToken(from: json))
    }

    func testDecodeCodexAuthToken() throws {
        let payload = #"{"exp":1900000000,"https://api.openai.com/auth":{"chatgpt_account_id":"acct_1","chatgpt_plan_type":"plus","organizations":[{"id":"org_1","is_default":true}]},"https://api.openai.com/profile":{"email":"user@example.com"}}"#
        let encodedPayload = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "header.\(encodedPayload).signature"
        let json = """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(jwt)",
            "account_id": "acct_1",
            "refresh_token": "refresh"
          }
        }
        """.data(using: .utf8)!

        let token = try CodexAuthStore.decodeToken(from: json)
        XCTAssertEqual(token.accessToken, jwt)
        XCTAssertEqual(token.accountID, "acct_1")
        XCTAssertEqual(token.workspaceID, "acct_1")
        XCTAssertEqual(token.planType, "plus")
        XCTAssertEqual(token.email, "user@example.com")
        XCTAssertEqual(token.expiresAt?.timeIntervalSince1970, 1_900_000_000)
    }

    func testDecodeCodexAuthTokenReadsWorkspaceFromIDToken() throws {
        let accessPayload = #"{"exp":1900000000,"https://api.openai.com/auth":{"chatgpt_account_id":"acct_1","chatgpt_plan_type":"plus"},"https://api.openai.com/profile":{"email":"user@example.com"}}"#
        let idPayload = #"{"https://api.openai.com/auth":{"organizations":[{"id":"org_from_id","is_default":true}]}}"#
        let accessJWT = "header.\(Self.base64URL(accessPayload)).signature"
        let idJWT = "header.\(Self.base64URL(idPayload)).signature"
        let json = """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(accessJWT)",
            "id_token": "\(idJWT)",
            "account_id": "acct_1"
          }
        }
        """.data(using: .utf8)!

        let token = try CodexAuthStore.decodeToken(from: json)
        XCTAssertEqual(token.workspaceID, "acct_1")
        XCTAssertEqual(token.planType, "plus")
        XCTAssertEqual(token.email, "user@example.com")
    }

    private static func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: ISO-8601 parsing (microsecond precision + offset)

    func testISO8601Microseconds() {
        let d = ISO8601.parse("2026-06-15T05:59:59.553366+00:00")
        XCTAssertNotNil(d)
        // 2026-06-15T05:59:59Z ≈ epoch
        XCTAssertEqual(d!.timeIntervalSince1970, 1781503199.553, accuracy: 1.0)
    }

    func testISO8601NoFraction() {
        XCTAssertNotNil(ISO8601.parse("2026-06-17T10:59:59+00:00"))
    }

    func testNormalizeFractionalSeconds() {
        XCTAssertEqual(
            ISO8601.normalizeFractionalSeconds("2026-06-15T05:59:59.553366+00:00"),
            "2026-06-15T05:59:59.553+00:00"
        )
        XCTAssertEqual(
            ISO8601.normalizeFractionalSeconds("2026-06-15T05:59:59.5+00:00"),
            "2026-06-15T05:59:59.500+00:00"
        )
    }

    // MARK: Usage response decoding (real captured shape)

    func testUsageResponseDecoding() throws {
        let json = """
        {
          "five_hour": { "utilization": 7.0, "resets_at": "2026-06-15T05:59:59.553366+00:00" },
          "seven_day": { "utilization": 11.0, "resets_at": "2026-06-17T10:59:59.553386+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": {
            "is_enabled": true, "monthly_limit": 2000, "used_credits": 0.0,
            "utilization": null, "currency": "USD", "disabled_reason": null
          }
        }
        """.data(using: .utf8)!
        let usage = try UsageAPIClient.makeDecoder().decode(UsageResponse.self, from: json)
        XCTAssertEqual(usage.fiveHour?.utilization, 7.0)
        XCTAssertNotNil(usage.fiveHour?.resetsAt)
        XCTAssertEqual(usage.sevenDay?.utilization, 11.0)
        XCTAssertNil(usage.sevenDayOpus)                 // bucket entirely null
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 0.0)
        XCTAssertNil(usage.sevenDaySonnet?.resetsAt)     // used but never reset
        XCTAssertEqual(usage.extraUsage?.isEnabled, true)
        XCTAssertEqual(usage.extraUsage?.monthlyLimit, 2000)
    }

    func testSnapshotMappingFromUsage() throws {
        let json = """
        { "five_hour": { "utilization": 42.5, "resets_at": null },
          "seven_day": { "utilization": 80.0, "resets_at": null },
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": { "is_enabled": false } }
        """.data(using: .utf8)!
        let usage = try UsageAPIClient.makeDecoder().decode(UsageResponse.self, from: json)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = UsageSnapshot(usage: usage, planLabel: "Max (20x)", fetchedAt: now)
        XCTAssertEqual(snap.session.utilization, 42.5)
        XCTAssertEqual(snap.session.fraction, 0.425, accuracy: 0.0001)
        XCTAssertEqual(snap.weeklyAll.utilization, 80.0)
        XCTAssertEqual(snap.weeklySonnet?.utilization, 0.0)
        XCTAssertNil(snap.weeklyOpus)
        XCTAssertNil(snap.extra)                          // disabled → dropped
        XCTAssertEqual(snap.fetchedAt, now)
    }

    // MARK: Codex usage endpoint (wham/usage — same source as TUI /status)

    func testCodexWhamUsageParsing() throws {
        let json = """
        {
          "plan_type": "prolite",
          "rate_limit": {
            "allowed": true,
            "limit_reached": false,
            "primary_window":   { "used_percent": 5, "limit_window_seconds": 18000,  "reset_after_seconds": 11744, "reset_at": 1781785217 },
            "secondary_window": { "used_percent": 3, "limit_window_seconds": 604800, "reset_after_seconds": 562543, "reset_at": 1782336016 }
          },
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "metered_feature": "codex_bengalfox",
              "rate_limit": {
                "primary_window":   { "used_percent": 7, "limit_window_seconds": 18000,  "reset_at": 1781791473 },
                "secondary_window": { "used_percent": 0, "limit_window_seconds": 604800, "reset_at": 1782378273 }
              }
            }
          ],
          "credits": { "has_credits": false, "unlimited": false, "balance": "0" }
        }
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 1_781_770_000)

        let summary = try CodexUsageAPIClient.parseUsagePayload(data: json, accountID: "acct_1", now: now)
        XCTAssertEqual(summary.source, "Codex /status")
        XCTAssertEqual(summary.workspaceID, "acct_1")
        XCTAssertEqual(summary.rateLimitPlanType, "prolite")
        XCTAssertEqual(summary.primaryRateLimit?.usedPercent, 5)
        XCTAssertEqual(summary.primaryRateLimit?.windowMinutes, 300)        // 18000s → 300m
        XCTAssertEqual(summary.primaryRateLimit?.resetsAt?.timeIntervalSince1970, 1_781_785_217)
        XCTAssertEqual(summary.secondaryRateLimit?.usedPercent, 3)
        XCTAssertEqual(summary.secondaryRateLimit?.windowMinutes, 10_080)   // 604800s → 10080m
        let additional = try XCTUnwrap(summary.additionalRateLimits.first)
        XCTAssertEqual(additional.name, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(additional.primary?.usedPercent, 7)
        XCTAssertEqual(additional.primary?.windowMinutes, 300)
        XCTAssertEqual(additional.secondary?.usedPercent, 0)
        XCTAssertNil(summary.credits)                                       // has_credits=false → hidden
        XCTAssertEqual(summary.periodEnd, now)
    }

    func testCodexWhamUsageSurfacesPurchasedCredits() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": { "primary_window": { "used_percent": 10, "limit_window_seconds": 18000, "reset_at": 1781785217 } },
          "credits": { "has_credits": true, "unlimited": false, "balance": "820.69" }
        }
        """.data(using: .utf8)!

        let summary = try CodexUsageAPIClient.parseUsagePayload(data: json, accountID: nil, now: Date())
        XCTAssertEqual(summary.credits ?? 0, 820.69, accuracy: 0.001)
    }

    func testCodexWhamUsageRejectsEmptyPayload() {
        let json = #"{ "plan_type": "plus" }"#.data(using: .utf8)!
        XCTAssertThrowsError(try CodexUsageAPIClient.parseUsagePayload(data: json, accountID: nil, now: Date()))
    }

    func testFractionClamping() {
        XCTAssertEqual(Metric(utilization: 150, resetsAt: nil).fraction, 1.0)
        XCTAssertEqual(Metric(utilization: -5, resetsAt: nil).fraction, 0.0)
    }

    // MARK: Plan label

    func testPlanLabel() {
        XCTAssertEqual(PlanLabel.from(rateLimitTier: "default_claude_max_20x"), "Max (20x)")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: "default_claude_max_5x"), "Max (5x)")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: "claude_pro"), "Pro")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: nil, subscriptionType: "max"), "Max")
        XCTAssertEqual(PlanLabel.from(rateLimitTier: nil, subscriptionType: nil), "Claude")
    }

    // MARK: Reset formatting

    func testRelativeReset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let in3h58m = now.addingTimeInterval(3 * 3600 + 58 * 60)
        XCTAssertEqual(ResetFormatter.relative(in3h58m, now: now), "3시간 58분 후 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(45 * 60), now: now), "45분 후 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(-10), now: now), "곧 재설정")
        // Sub-60s remaining must read "곧 재설정", never a misleading "0분 후 재설정".
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(30), now: now), "곧 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(59), now: now), "곧 재설정")
        XCTAssertEqual(ResetFormatter.relative(now.addingTimeInterval(60), now: now), "1분 후 재설정")
        XCTAssertEqual(ResetFormatter.relative(nil), "")
    }

    func testAge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(ResetFormatter.age(now.addingTimeInterval(-90), now: now), "1분 전")
        XCTAssertEqual(ResetFormatter.age(now.addingTimeInterval(-5), now: now), "방금")
    }

    // MARK: Retry-After parsing (429 backoff)

    func testRetryAfterSecondsNumeric() throws {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                   headerFields: ["Retry-After": "90"])!
        XCTAssertEqual(UsageAPIClient.retryAfterSeconds(from: resp), 90)
    }

    func testRetryAfterSecondsHTTPDate() throws {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                   headerFields: ["Retry-After": "Tue, 14 Nov 2023 22:18:20 GMT"])!
        let secs = UsageAPIClient.retryAfterSeconds(from: resp, now: now)
        XCTAssertNotNil(secs)
        XCTAssertEqual(secs!, 1_700_000_300 - 1_700_000_000, accuracy: 1.0)
    }

    func testRetryAfterAbsent() throws {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: [:])!
        XCTAssertNil(UsageAPIClient.retryAfterSeconds(from: resp))
    }

    // MARK: Snapshot codec round-trip (widget read path)

    func testSnapshotRoundTrip() throws {
        let snap = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            planLabel: "Max (20x)",
            session: Metric(utilization: 7, resetsAt: Date(timeIntervalSince1970: 1_700_010_000)),
            weeklyAll: Metric(utilization: 11, resetsAt: nil),
            weeklySonnet: Metric(utilization: 0, resetsAt: nil),
            weeklyOpus: nil,
            extra: ExtraInfo(isEnabled: true, monthlyLimit: 2000, usedCredits: 3.5, currency: "USD"),
            errorMessage: nil
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(snap)
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded.session.utilization, 7)
        XCTAssertEqual(decoded.weeklyAll.utilization, 11)
        XCTAssertEqual(decoded.extra?.usedCredits, 3.5)
        XCTAssertEqual(decoded.planLabel, "Max (20x)")
    }
}
