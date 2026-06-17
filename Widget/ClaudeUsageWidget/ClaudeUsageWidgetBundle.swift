import WidgetKit
import SwiftUI
import ClaudeUsageCore

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.widgetKind, provider: Provider()) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("AgentUsageBar")
        .description("Claude와 Codex 사용량을 표시합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
