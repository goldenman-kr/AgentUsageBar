import Foundation
import ClaudeUsageCore

// A tiny CLI that exercises the full data pipeline against the *live* API,
// using the real Keychain token — used to verify the core before wiring up UI.
//
// Usage:  swift run usage-probe

func line(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

do {
    let token = try KeychainTokenStore.loadToken()
    line("✓ Keychain token loaded")
    line("  plan tier   : \(token.rateLimitTier ?? "nil")")
    line("  subscription: \(token.subscriptionType ?? "nil")")
    line("  expires at  : \(token.expiresAt)  (expired=\(token.isExpired))")
    line("  token       : loaded (len=\(token.accessToken.count))")   // never log token contents

    let client = UsageAPIClient()
    let snapshot = try await client.fetchSnapshot()

    line("\n✓ Usage fetched")
    line("  plan        : \(snapshot.planLabel)")
    line("  현재 세션    : \(Int(snapshot.session.utilization))%  \(ResetFormatter.relative(snapshot.session.resetsAt))")
    line("  주간·모든모델 : \(Int(snapshot.weeklyAll.utilization))%  \(ResetFormatter.absolute(snapshot.weeklyAll.resetsAt))")
    if let s = snapshot.weeklySonnet {
        line("  Sonnet 전용  : \(Int(s.utilization))%")
    }
    if let o = snapshot.weeklyOpus {
        line("  Opus 전용    : \(Int(o.utilization))%")
    }
    if let e = snapshot.extra {
        line("  추가 크레딧  : \(e.usedCredits)/\(e.monthlyLimit) \(e.currency) (enabled=\(e.isEnabled))")
    }
    line("  fetched     : \(ResetFormatter.age(snapshot.fetchedAt))")

    // Round-trip through the snapshot codec (validates widget read path).
    let encoded = try JSONEncoder().encode(snapshot)
    line("\n✓ Snapshot encodes to \(encoded.count) bytes")

    // Emit machine-readable JSON to stdout for scripted checks.
    let pretty = JSONEncoder()
    pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
    pretty.dateEncodingStrategy = .iso8601
    if let json = try? pretty.encode(snapshot), let str = String(data: json, encoding: .utf8) {
        print(str)
    }
} catch {
    line("✗ FAILED: \(error.localizedDescription)")
    line("  raw: \(error)")
    exit(1)
}
