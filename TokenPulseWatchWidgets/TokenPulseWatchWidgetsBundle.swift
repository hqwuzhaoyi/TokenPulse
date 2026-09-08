import SwiftUI
import WidgetKit

@main
struct TokenPulseWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchQuotaWidget()
    }
}

struct WatchQuotaWidget: Widget {
    let kind = "TokenPulseWatchQuota"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuotaWidgetIntent.self, provider: QuotaTimelineProvider()) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("TokenPulse 额度")
        .description("在表盘或智能叠放显示指定账号额度。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
