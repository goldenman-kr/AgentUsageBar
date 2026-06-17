import SwiftUI
import AppKit
import ClaudeUsageCore
import ClaudeUsageUI

/// The popover shown when the menu-bar item is clicked. Mirrors the layout of
/// the Claude desktop app's "사용량" settings page.
struct PopoverView: View {
    @ObservedObject var model: UsageViewModel

    private var snapshot: UsageSnapshot? { model.snapshot }
    private var hasData: Bool { (snapshot?.fetchedAt.timeIntervalSince1970 ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            providerPicker

            if let snap = snapshot, hasData {
                planRow(snap)
                Divider()
                switch snap.provider {
                case .claude:
                    sessionSection(snap)
                    weeklySection(snap)
                    if let extra = snap.extra { extraSection(extra) }
                case .codex:
                    codexSection(snap)
                }
            } else {
                placeholder
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
            Text(model.selectedProvider.title)
                .font(.system(size: 15, weight: .bold))
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var providerPicker: some View {
        Picker("조회 대상", selection: $model.selectedProvider) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func planRow(_ snap: UsageSnapshot) -> some View {
        HStack {
            Text("플랜 사용량 한도")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(snap.planLabel)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())
        }
    }

    // MARK: Sections

    private func sessionSection(_ snap: UsageSnapshot) -> some View {
        MetricRow(
            title: "현재 세션",
            metric: snap.session,
            caption: ResetFormatter.relative(snap.session.resetsAt, now: model.now)
        )
    }

    private func weeklySection(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("주간 한도")
                .font(.system(size: 13, weight: .bold))
                .padding(.top, 2)

            MetricRow(
                title: "모든 모델",
                metric: snap.weeklyAll,
                caption: ResetFormatter.absolute(snap.weeklyAll.resetsAt)
            )

            if let sonnet = snap.weeklySonnet {
                MetricRow(
                    title: "Sonnet 전용",
                    metric: sonnet,
                    caption: sonnet.utilization <= 0 ? "아직 Sonnet을 사용하지 않았습니다"
                                                      : ResetFormatter.absolute(sonnet.resetsAt)
                )
            }
            if let opus = snap.weeklyOpus {
                MetricRow(
                    title: "Opus 전용",
                    metric: opus,
                    caption: opus.utilization <= 0 ? "아직 Opus를 사용하지 않았습니다"
                                                    : ResetFormatter.absolute(opus.resetsAt)
                )
            }
        }
    }

    private func extraSection(_ extra: ExtraInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Text("추가 사용 크레딧")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "$%.2f / $%.0f", extra.usedCredits, extra.monthlyLimit))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func codexSection(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let codex = snap.codex {
                if let primary = codex.primaryRateLimit {
                    MetricRow(
                        title: "5시간 한도",
                        metric: primary.metric,
                        caption: ResetFormatter.relative(primary.resetsAt)
                    )
                }
                if let secondary = codex.secondaryRateLimit {
                    MetricRow(
                        title: "주간 한도",
                        metric: secondary.metric,
                        caption: ResetFormatter.absolute(secondary.resetsAt)
                    )
                }
                ForEach(codex.additionalRateLimits) { limit in
                    if let primary = limit.primary {
                        MetricRow(
                            title: "\(limit.name) · 5시간",
                            metric: primary.metric,
                            caption: ResetFormatter.relative(primary.resetsAt)
                        )
                    }
                    if let secondary = limit.secondary {
                        MetricRow(
                            title: "\(limit.name) · 주간",
                            metric: secondary.metric,
                            caption: ResetFormatter.absolute(secondary.resetsAt)
                        )
                    }
                }
                if codex.primaryRateLimit == nil, let metric = codex.creditMetric {
                    MetricRow(
                        title: "크레딧",
                        metric: metric,
                        caption: ResetFormatter.absolute(metric.resetsAt)
                    )
                } else if let credits = codex.credits {
                    valueRow("크레딧", String(format: "%.2f", credits))
                }
                Text(sourceCaption(codex.source))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text("Codex 사용량 데이터가 아직 없습니다")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sourceCaption(_ source: String) -> String {
        switch source {
        case "Codex /status":
            return "Codex /status 기준"
        case "Codex rate limit snapshot":
            return "마지막 Codex 실행에서 기록된 서버 한도"
        case "Codex local activity":
            return "로컬 활동량 기준 · 잔량 아님"
        default:
            return source
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = model.statusError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("사용량을 불러오는 중…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasData, let err = model.statusError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            HStack {
                if let snap = snapshot, hasData {
                    Text("마지막 업데이트: \(ResetFormatter.age(snap.fetchedAt, now: model.now))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button { Task { await model.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("새로고침")
                .disabled(model.isRefreshing)
            }

            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            HStack {
                Button("사용량 페이지 열기") {
                    if let url = usagePageURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 12))
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                    .font(.system(size: 12))
            }
            .buttonStyle(.link)
        }
    }

    private var usagePageURL: URL? {
        switch model.selectedProvider {
        case .claude:
            return URL(string: "https://claude.ai/settings/usage")
        case .codex:
            return URL(string: "https://chatgpt.com/codex")
        }
    }
}
