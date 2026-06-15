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
                Text("Claude")
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
                compactMetric("세션", snap.session)
                compactMetric("주간", snap.weeklyAll)
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
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
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
                Text("Claude 사용량")
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
                row("현재 세션", snap.session,
                    caption: ResetFormatter.relative(snap.session.resetsAt))
                row("주간 · 모든 모델", snap.weeklyAll,
                    caption: ResetFormatter.absolute(snap.weeklyAll.resetsAt))
                if let sonnet = snap.weeklySonnet, sonnet.utilization > 0 {
                    row("주간 · Sonnet", sonnet, caption: "")
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
}
