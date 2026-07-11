import SwiftUI
import WidgetKit
import ClaudeUsageCore
import ClaudeUsageUI

/// Root view that switches layout by widget family.
struct ClaudeUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallUsageView(entry: entry)
            default: MediumUsageView(entry: entry)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Small

private struct SmallUsageView: View {
    let entry: UsageEntry
    private var snap: UsageSnapshot { entry.snapshot }
    private var isStale: Bool { !entry.needsApp && snap.errorMessage != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(snap.provider.displayName)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help("오래된 데이터")
                } else {
                    Text(snap.planLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if entry.needsApp {
                appPrompt
            } else {
                if snap.provider == .codex {
                    codexCompactRows(snap)
                } else {
                    compactMetric("세션", snap.session)
                    compactMetric("주간", snap.weeklyAll)
                }
                Spacer(minLength: 0)
                if let resets = snap.session.resetsAt {
                    Text(ResetFormatter.relative(resets))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    private func compactMetric(_ title: String, _ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(Int(metric.utilization.rounded()))%")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            MeterBar(fraction: metric.fraction, utilization: metric.utilization, height: 5)
        }
    }

    private var appPrompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
            Image(systemName: "menubar.arrow.up.rectangle").foregroundStyle(.secondary)
            Text("메뉴바 앱을\n실행하세요")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func codexCompactRows(_ snap: UsageSnapshot) -> some View {
        if snap.codex?.primaryRateLimit != nil || snap.codex?.secondaryRateLimit != nil {
            compactMetric("5시간", snap.session)
            compactMetric("주간", snap.weeklyAll)
            if let firstAdditional = snap.codex?.additionalRateLimits.first,
               let primary = firstAdditional.primary {
                compactMetric(firstAdditional.name, primary.metric)
            }
        } else if let metric = snap.codex?.creditMetric {
            compactMetric("크레딧", metric)
        } else if let credits = snap.codex?.credits {
            compactValue("크레딧", String(format: "%.1f", credits))
        } else if let total = snap.codex?.totalTokens {
            compactValue("토큰", NumberFormatter.localizedString(from: NSNumber(value: total), number: .decimal))
        } else {
            compactValue("토큰", "–")
        }
    }

    private func compactValue(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - Medium

private struct MediumUsageView: View {
    let entry: UsageEntry
    private var snap: UsageSnapshot { entry.snapshot }
    private var isStale: Bool { !entry.needsApp && snap.errorMessage != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(snap.provider.title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(snap.planLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            if entry.needsApp {
                Spacer()
                Label("메뉴바 앱을 실행하면 사용량이 표시됩니다", systemImage: "menubar.arrow.up.rectangle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            } else {
                if snap.provider == .codex {
                    codexRows(snap)
                } else {
                    row("현재 세션", snap.session,
                        caption: ResetFormatter.relative(snap.session.resetsAt))
                    row("주간 · 모든 모델", snap.weeklyAll,
                        caption: ResetFormatter.absolute(snap.weeklyAll.resetsAt))
                    if let sonnet = snap.weeklySonnet, sonnet.utilization > 0 {
                        row("주간 · Sonnet", sonnet, caption: "")
                    }
                }
                if isStale {
                    Label("오래된 데이터 — 새로고침 실패", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
    }

    private func row(_ title: String, _ metric: Metric, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(metric.utilization.rounded()))%")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MeterBar(fraction: metric.fraction, utilization: metric.utilization, height: 6)
            if !caption.isEmpty {
                Text(caption).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func codexRows(_ snap: UsageSnapshot) -> some View {
        let hasRateLimit = snap.codex?.primaryRateLimit != nil || snap.codex?.secondaryRateLimit != nil
        if let primary = snap.codex?.primaryRateLimit {
            row("5시간 한도", primary.metric, caption: ResetFormatter.relative(primary.resetsAt))
        }
        if let secondary = snap.codex?.secondaryRateLimit {
            row("주간 한도", secondary.metric, caption: ResetFormatter.absolute(secondary.resetsAt))
        }
        ForEach(snap.codex?.additionalRateLimits ?? []) { limit in
            if let primary = limit.primary {
                row("\(limit.name) · 5시간", primary.metric, caption: ResetFormatter.relative(primary.resetsAt))
            }
            if let secondary = limit.secondary {
                row("\(limit.name) · 주간", secondary.metric, caption: ResetFormatter.absolute(secondary.resetsAt))
            }
        }
        if !hasRateLimit {
            if let metric = snap.codex?.creditMetric {
                row("크레딧", metric, caption: ResetFormatter.absolute(metric.resetsAt))
            } else {
                valueRow("크레딧", snap.codex?.credits.map { String(format: "%.2f", $0) } ?? "–")
            }
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
