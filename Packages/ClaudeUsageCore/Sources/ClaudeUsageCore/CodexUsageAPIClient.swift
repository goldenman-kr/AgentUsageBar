import Foundation

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
        try? await CodexStatusCommand.refresh()
        if let status = try? CodexLocalUsageStore.loadStatusSummary(now: now) {
            return UsageSnapshot(codex: status, planLabel: CodexPlanLabel.from(planType: token.planType), fetchedAt: now)
        }
        guard let workspaceID = token.workspaceID, !workspaceID.isEmpty else {
            return try localSnapshot(planType: token.planType, now: now)
        }

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        var components = URLComponents(url: CodexAuth.analyticsUsageURL(workspaceID: workspaceID), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "group_by", value: "day"),
            URLQueryItem(name: "group", value: "workspace"),
            URLQueryItem(name: "limit", value: "90")
        ]
        guard let url = components.url else {
            throw UsageError.network("Codex Analytics URL 생성 실패")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(CodexAuth.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataAllowingNilBody(req)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("HTTP 응답이 아님")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 { throw UsageError.tokenExpired(token.expiresAt ?? now) }
            if http.statusCode == 429 {
                throw UsageError.rateLimited(retryAfter: UsageAPIClient.retryAfterSeconds(from: http))
            }
            if http.statusCode == 400 || http.statusCode == 403 {
                return try localSnapshot(planType: token.planType, now: now)
            }
            throw UsageError.httpStatus(http.statusCode, String(body.prefix(200)))
        }

        let summary = try Self.summarizeAnalytics(data: data, workspaceID: workspaceID, start: start, end: now)
        return UsageSnapshot(codex: summary, planLabel: CodexPlanLabel.from(planType: token.planType), fetchedAt: now)
    }

    private func localSnapshot(planType: String?, now: Date) throws -> UsageSnapshot {
        let summary = try CodexLocalUsageStore.loadSummary(now: now)
        return UsageSnapshot(codex: summary, planLabel: CodexPlanLabel.from(planType: planType), fetchedAt: now)
    }

    private func dataAllowingNilBody(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
    }

    static func summarizeAnalytics(data: Data, workspaceID: String?, start: Date?, end: Date?) throws -> CodexUsageSummary {
        let object = try JSONSerialization.jsonObject(with: data)
        var totals = AnalyticsTotals()
        collectNumbers(object, keyPath: [], totals: &totals)
        return CodexUsageSummary(
            source: "Codex Analytics API",
            workspaceID: workspaceID,
            periodStart: start,
            periodEnd: end,
            credits: totals.credits,
            threads: totals.threads.map(Int.init),
            turns: totals.turns.map(Int.init),
            inputTokens: totals.inputTokens.map(Int.init),
            cachedInputTokens: totals.cachedInputTokens.map(Int.init),
            outputTokens: totals.outputTokens.map(Int.init)
        )
    }

    private struct AnalyticsTotals {
        var credits: Double?
        var threads: Double?
        var turns: Double?
        var inputTokens: Double?
        var cachedInputTokens: Double?
        var outputTokens: Double?

        mutating func add(_ value: Double, for key: String) {
            let k = key.lowercased()
            if k.contains("credit") {
                credits = (credits ?? 0) + value
            } else if k.contains("thread") {
                threads = (threads ?? 0) + value
            } else if k.contains("turn") {
                turns = (turns ?? 0) + value
            } else if k.contains("cached") && k.contains("input") && k.contains("token") {
                cachedInputTokens = (cachedInputTokens ?? 0) + value
            } else if k.contains("input") && k.contains("token") {
                inputTokens = (inputTokens ?? 0) + value
            } else if k.contains("output") && k.contains("token") {
                outputTokens = (outputTokens ?? 0) + value
            }
        }
    }

    private static func collectNumbers(_ object: Any, keyPath: [String], totals: inout AnalyticsTotals) {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                collectNumbers(value, keyPath: keyPath + [key], totals: &totals)
            }
            return
        }
        if let array = object as? [Any] {
            for value in array {
                collectNumbers(value, keyPath: keyPath, totals: &totals)
            }
            return
        }
        let value: Double?
        if let n = object as? Double {
            value = n
        } else if let n = object as? Int {
            value = Double(n)
        } else if let n = object as? NSNumber {
            value = n.doubleValue
        } else {
            value = nil
        }
        guard let value, let key = keyPath.last else { return }
        totals.add(value, for: key)
    }
}
