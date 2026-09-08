import AppIntents
import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let account: WidgetAccountSnapshot?
    let accountSelectionMissing: Bool
}

struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<QuotaWidgetIntent>] {
        [AppIntentRecommendation(intent: QuotaWidgetIntent(), description: "选择 TokenPulse 账号")]
    }

    func placeholder(in context: Context) -> QuotaWidgetEntry {
        QuotaWidgetEntry(date: Date(), account: nil, accountSelectionMissing: false)
    }

    func snapshot(for configuration: QuotaWidgetIntent, in context: Context) async -> QuotaWidgetEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: QuotaWidgetIntent, in context: Context) async -> Timeline<QuotaWidgetEntry> {
        let entry = await entry(for: configuration)
        let dates = Set((entry.account?.windows ?? []).compactMap(\.resetsAt))
            .filter { $0 > entry.date }.sorted()
        return Timeline(
            entries: [entry] + dates.map {
                QuotaWidgetEntry(date: $0, account: entry.account, accountSelectionMissing: entry.accountSelectionMissing)
            },
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
    }

    private func entry(for configuration: QuotaWidgetIntent) async -> QuotaWidgetEntry {
        let snapshots = await WidgetSnapshotStore().load()
        let selectedID = configuration.account?.id
        let account = selectedID.flatMap { id in snapshots.first { $0.id.uuidString == id } }
            ?? (selectedID == nil ? snapshots.first : nil)
        return QuotaWidgetEntry(
            date: Date(), account: account,
            accountSelectionMissing: selectedID != nil && account == nil
        )
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaWidgetEntry

    var body: some View {
        Group {
            if let account = entry.account {
                content(account)
            } else {
                Text(entry.accountSelectionMissing ? "账号尚未同步" : "请选择账号")
                    .font(.caption)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(entry.account.flatMap {
            URL(string: "\(PlatformConstants.accountDeepLinkScheme)://account/\($0.id.uuidString)")
        })
    }

    @ViewBuilder
    private func content(_ account: WidgetAccountSnapshot) -> some View {
        if family == .accessoryInline {
            Text("\(account.account.name) \(account.displayMetrics.map { "\($0.title) \(percentage($0.window))" }.joined(separator: " · "))\(account.remainingResetCount.map { " · 可重置 \($0) 次" } ?? "")")
        } else if family == .accessoryCircular {
            VStack(spacing: 2) {
                ProviderIcon(provider: account.account.provider, size: 12)
                ForEach(account.displayMetrics.prefix(2)) { metric in
                    Text("\(metric.id == "fiveHour" ? "5h" : "周") \(percentage(metric.window))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.8).lineLimit(1)
                }
                if let count = account.remainingResetCount {
                    Text("可重置 \(count) 次").font(.system(size: 8))
                }
                if isStale(account) { Text("待更新").font(.system(size: 8)) }
            }
            .accessibilityLabel(account.account.name)
        } else {
            VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 3 : 8) {
                HStack(spacing: 5) {
                    ProviderIcon(provider: account.account.provider, size: 14)
                    Text(account.account.name).font(.caption.bold()).lineLimit(1)
                    Spacer(minLength: 0)
                    if isStale(account) {
                        Text("待更新").font(.caption2).foregroundStyle(.orange)
                    }
                }
                ForEach(metrics(for: account).prefix(4)) { metric in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(metric.title).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 3)
                            Text(percentage(metric.window))
                                .font(.system(size: family == .accessoryRectangular ? 14 : 24, weight: .semibold, design: .rounded))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                        }
                        if metric.showsReset {
                            Text("重置 \(QuotaFormatting.resetDate(metric.window?.resetsAt))")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                if metrics(for: account).count > 4 {
                    Text("另有 \(metrics(for: account).count - 4) 项，打开查看").font(.caption2)
                }
                if account.account.provider == .codex || account.account.provider == .superGrok {
                    HStack {
                        Text("可手动重置")
                        Spacer(minLength: 3)
                        Text(QuotaFormatting.remainingResets(account.remainingResetCount)).monospacedDigit()
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                if account.lastFailure != nil {
                    Text("最近刷新失败").font(.caption2).foregroundStyle(.orange)
                }
                #if os(iOS)
                if family == .systemLarge, let collectedAt = account.collectedAt {
                    Text("更新于 \(QuotaFormatting.resetDate(collectedAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                #endif
            }
        }
    }

    private func percentage(_ window: QuotaWindow?) -> String {
        if window?.isUnlimited == true { return "无限" }
        guard let value = window?.usedPercentage, value.isFinite else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private func isStale(_ account: WidgetAccountSnapshot) -> Bool {
        metrics(for: account).contains { $0.window?.needsUpdate(at: entry.date) == true }
    }

    private func metrics(for account: WidgetAccountSnapshot) -> [WidgetQuotaMetric] {
        #if os(iOS)
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            return account.homeScreenMetrics
        default: break
        }
        #endif
        return account.displayMetrics
    }
}
