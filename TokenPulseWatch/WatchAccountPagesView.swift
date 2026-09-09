import SwiftUI

struct WatchAccountPagesView: View {
    @Environment(\.scenePhase) private var scenePhase
    let runtime: AppRuntime
    @ObservedObject var monitor: QuotaMonitor
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if displayedStates.isEmpty {
                    ContentUnavailableView(
                        "没有账号",
                        systemImage: "applewatch",
                        description: Text("等待 iCloud 同步账号配置")
                    )
                } else {
                    TabView(selection: $selection) {
                        ForEach(displayedStates) { state in
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                WatchAccountPage(
                                    state: state,
                                    date: context.date,
                                    isRefreshing: monitor.refreshingAccountIDs.contains(state.id)
                                ) {
                                    await monitor.refresh(accountID: state.id)
                                }
                            }
                            .tag(Optional(state.id))
                        }
                    }
                    .tabViewStyle(.page)
                }
            }
            .navigationTitle("TokenPulse")
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await runtime.refresh() }
            }
            .onOpenURL { url in
                guard url.scheme == PlatformConstants.accountDeepLinkScheme,
                      url.host == "account",
                      let id = UUID(uuidString: url.lastPathComponent),
                      monitor.states.contains(where: { $0.id == id })
                else { return }
                selection = id
            }
            .toolbar {
                ToolbarItem {
                    NavigationLink {
                        WatchWidgetSettingsView(accounts: displayedStates.map(\.account))
                    } label: {
                        Label("表盘设置", systemImage: "gearshape")
                    }
                    .accessibilityLabel("表盘设置")
                }
            }
        }
    }

    private var displayedStates: [AccountQuotaState] {
        monitor.states
    }
}

private struct WatchWidgetSettingsView: View {
    let accounts: [SubscriptionAccount]
    @State private var selectedAccountID: UUID?
    private let store = WatchWidgetSelectionStore()

    var body: some View {
        Group {
            if accounts.isEmpty {
                ContentUnavailableView(
                    "没有账号",
                    systemImage: "applewatch",
                    description: Text("等待 iCloud 同步账号配置")
                )
            } else {
                Form {
                    Picker("表盘显示账号", selection: $selectedAccountID) {
                        ForEach(accounts) { account in
                            HStack(spacing: 6) {
                                ProviderIcon(provider: account.provider, size: 14)
                                VStack(alignment: .leading) {
                                    Text(account.name)
                                    Text(account.provider.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(Optional(account.id))
                        }
                    }
                }
            }
        }
        .navigationTitle("表盘设置")
        .task {
            let saved = await store.load()
            selectedAccountID = saved.flatMap { id in accounts.contains { $0.id == id } ? id : nil }
                ?? accounts.first?.id
        }
        .onChange(of: selectedAccountID) { _, accountID in
            Task {
                await store.save(accountID)
            }
        }
    }
}

private struct WatchAccountPage: View {
    let state: AccountQuotaState
    let date: Date
    let isRefreshing: Bool
    let refresh: () async -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ProviderIcon(provider: state.account.provider, size: 24)
                Text(state.account.name).font(.headline).lineLimit(1)
                Text(providerDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let snapshot = state.snapshot {
                    ForEach(snapshot.windows(for: state.account.provider, surface: .detail)) { window in
                        if window.scope == nil {
                            VStack(alignment: .leading, spacing: 3) {
                                if let percentage = QuotaFormatting.effectiveUsedPercentage(window) {
                                    Gauge(value: min(max(percentage, 0), 100), in: 0...100) {
                                    Text(window.name)
                                } currentValueLabel: {
                                    Text(window.isExhausted == true
                                         ? "已用尽"
                                         : "\(percentage.formatted(.number.precision(.fractionLength(0...1))))%")
                                }
                                    .gaugeStyle(.accessoryCircular)
                                } else {
                                    LabeledContent(window.name, value: window.isUnlimited ? "无限" : "未提供")
                                        .font(.caption)
                                }
                                LabeledContent("重置", value: QuotaFormatting.resetDate(window.resetsAt))
                                    .font(.caption2)
                                if window.needsUpdate(at: date) {
                                    Label("待更新", systemImage: "clock.badge.exclamationmark")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            LabeledContent(
                                window.displayName,
                                value: QuotaFormatting.usage(window)
                            )
                            .font(.caption2)
                        }
                    }
                    if state.account.provider == .codex {
                        LabeledContent("可手动重置", value: QuotaFormatting.remainingResets(snapshot.remainingResetCount))
                            .font(.caption2)
                    }
                    Text("采集于 \(snapshot.collectedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚无成功采集数据").font(.caption).foregroundStyle(.secondary)
                }

                if let failure = state.lastFailure {
                    Label(
                        failure == .invalidCredential ? "凭证尚未同步或已失效" : failure.displayName,
                        systemImage: failure == .invalidCredential ? "key.slash" : "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }

                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
    }

    private var providerDescription: String {
        guard state.account.provider == .codex,
              let plan = state.snapshot?.subscriptionPlan else { return state.account.provider.displayName }
        return "\(state.account.provider.displayName) · \(plan.displayName)"
    }
}
