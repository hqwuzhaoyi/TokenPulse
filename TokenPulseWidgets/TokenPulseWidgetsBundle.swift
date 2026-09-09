import SwiftUI
import WidgetKit

@main
struct TokenPulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PhoneQuotaWidget()
    }
}

struct PhoneQuotaWidget: Widget {
    let kind = "TokenPulsePhoneQuota"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: QuotaWidgetIntent.self, provider: QuotaTimelineProvider()) {
            QuotaWidgetView(entry: $0)
        }
        .configurationDisplayName("TokenPulse 环形额度")
        .description("从主屏幕账号列表选择要显示的账号；小/中/大组件最多选择 1/2/4 个。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
