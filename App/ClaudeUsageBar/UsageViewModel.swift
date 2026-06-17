import Foundation
import Combine
import WidgetKit
import ServiceManagement
import ClaudeUsageCore

/// Owns the refresh loop for the menu-bar app. Fetches usage on a timer, caches
/// the result for the widget via the App Group, and publishes state to the UI.
@MainActor
final class UsageViewModel: ObservableObject {

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var statusError: String?
    @Published private(set) var isRefreshing = false
    /// Ticks so relative captions ("방금", "3시간 45분 후") stay current between fetches.
    @Published private(set) var now = Date()
    @Published var selectedProvider: UsageProvider {
        didSet {
            guard oldValue != selectedProvider else { return }
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerDefaultsKey)
            snapshot = store.load(provider: selectedProvider)
            statusError = nil
            backoffUntil = nil
            lastAttempt = .distantPast
            WidgetCenter.shared.reloadAllTimelines()
            Task { await refresh(force: true) }
        }
    }

    private let claudeClient = UsageAPIClient()
    private let codexClient = CodexUsageAPIClient()
    private let store = SharedStore()
    private var refreshTimer: Timer?
    private var uiTimer: Timer?

    /// Regular polling cadence. The 5-hour/7-day windows move slowly, so a long
    /// interval keeps us well under the endpoint's rate limit.
    private let refreshInterval: TimeInterval = 300        // 5 minutes
    /// Minimum spacing for *automatic* refreshes (timer/popover-open/wake). The
    /// manual ↻ button bypasses this (but still honors a 429 backoff).
    private let minAutoGap: TimeInterval = 45
    /// Default cool-down when a 429 arrives without a Retry-After header.
    private let defaultBackoff: TimeInterval = 120

    private var lastAttempt: Date = .distantPast
    /// When set, no requests are made until this time (server asked us to wait).
    private var backoffUntil: Date?
    private static let providerDefaultsKey = "SelectedUsageProvider"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
        selectedProvider = UsageProvider(rawValue: raw ?? "") ?? .claude
        // Show last-known data instantly (also what the widget last saw).
        snapshot = store.load(provider: selectedProvider)
    }

    func start() {
        Task { await refresh() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // Lightweight 30s tick to keep captions fresh without refetching.
        uiTimer?.invalidate()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    func stop() {
        refreshTimer?.invalidate(); refreshTimer = nil
        uiTimer?.invalidate(); uiTimer = nil
    }

    /// Fetches fresh usage. On failure, keeps the last good snapshot and records
    /// the error so the UI can show a reason without losing the numbers.
    ///
    /// - Parameter force: when true (the manual ↻ button), skips the automatic
    ///   debounce. A server-requested 429 backoff is always honored.
    func refresh(force: Bool = false) async {
        if isRefreshing { return }
        let nowDate = Date()

        // Honor a server-requested cool-down (429) even for manual refreshes.
        if let until = backoffUntil, nowDate < until {
            now = nowDate
            return
        }
        // Debounce automatic refreshes so opening the popover / waking doesn't
        // pile up requests on top of the timer.
        if !force, nowDate.timeIntervalSince(lastAttempt) < minAutoGap {
            return
        }

        isRefreshing = true
        lastAttempt = nowDate
        defer { isRefreshing = false }
        now = nowDate
        do {
            let fresh = try await fetchSelectedSnapshot(now: Date())
            snapshot = fresh
            statusError = nil
            backoffUntil = nil
            let saved = store.save(fresh)
            WidgetCenter.shared.reloadAllTimelines()
            // Pass dynamic values as arguments, never as the format string (they
            // contain '%', e.g. "12% · 12%").
            NSLog("[ClaudeUsageBar] refresh ok — menubar=%@ plan=%@ savedToAppGroup=%@",
                  menuBarTitle, fresh.planLabel, saved ? "true" : "false")
        } catch {
            // On 429, back off until the server-specified time (or a default).
            if case UsageError.rateLimited(let retryAfter) = error {
                let wait = retryAfter ?? defaultBackoff
                backoffUntil = Date().addingTimeInterval(wait)
                NSLog("[ClaudeUsageBar] rate limited (429) — backing off %.0fs", wait)
            } else {
                NSLog("[ClaudeUsageBar] refresh failed — %@",
                      (error as? UsageError)?.errorDescription ?? error.localizedDescription)
            }
            let message = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            statusError = message
            // Preserve prior numbers; annotate them with the error for the widget.
            if let prior = snapshot {
                let annotated = prior.withError(message)
                snapshot = annotated
                store.save(annotated)
            } else {
                let placeholder = UsageSnapshot.placeholder(provider: selectedProvider, error: message)
                snapshot = placeholder
                store.save(placeholder)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func fetchSelectedSnapshot(now: Date) async throws -> UsageSnapshot {
        switch selectedProvider {
        case .claude:
            return try await claudeClient.fetchSnapshot(now: now)
        case .codex:
            return try await codexClient.fetchSnapshot(now: now)
        }
    }

    // MARK: Menu-bar title

    /// Compact title shown in the menu bar, e.g. "9% · 11%".
    var menuBarTitle: String {
        guard let snap = snapshot, snap.fetchedAt.timeIntervalSince1970 > 0 else { return "––" }
        if snap.provider == .codex, let codex = snap.codex {
            if codex.primaryRateLimit != nil || codex.secondaryRateLimit != nil {
                return "\(Int(snap.session.utilization.rounded()))% · \(Int(snap.weeklyAll.utilization.rounded()))%"
            }
            if let credits = codex.credits {
                return String(format: "%.1f cr", credits)
            }
            if let turns = codex.turns {
                return "\(turns)t"
            }
            if let tokens = codex.totalTokens {
                return "\(tokens / 1000)k"
            }
            return "––"
        }
        return "\(Int(snap.session.utilization.rounded()))% · \(Int(snap.weeklyAll.utilization.rounded()))%"
    }

    /// Highest utilization across session + weekly, used to tint the menu-bar icon.
    var peakUtilization: Double {
        guard let snap = snapshot else { return 0 }
        if snap.provider == .codex {
            return max(snap.session.utilization, snap.weeklyAll.utilization)
        }
        return max(snap.session.utilization, snap.weeklyAll.utilization)
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                objectWillChange.send()
            } catch {
                statusError = "로그인 항목 설정 실패: \(error.localizedDescription)"
            }
        }
    }
}
