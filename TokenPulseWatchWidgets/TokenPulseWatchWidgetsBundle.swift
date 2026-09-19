import SwiftUI
import WidgetKit

@main
struct TokenPulseWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchQuotaWidget()
    }
}

struct WatchQuotaWidget: Widget {
    let kind = PlatformConstants.watchWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WatchQuotaWidgetIntent.self,
            provider: WatchQuotaTimelineProvider()
        ) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("TokenPulse 额度")
        .description("显示在 TokenPulse Watch App 设置中选择的账号额度。")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
