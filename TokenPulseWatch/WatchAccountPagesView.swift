import SwiftUI

struct WatchAccountPagesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var runtime: AppRuntime
    @ObservedObject var monitor: QuotaMonitor
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if displayedStates.isEmpty {
                    ContentUnavailableView {
                        Label("没有账号", systemImage: "applewatch")
                    } description: {
                        Text("等待 iCloud 同步账号配置，或体验示例数据。")
                    } actions: {
                        Button("体验演示 / Try Demo") { Task { await runtime.setDemoMode(true) } }
                            .disabled(runtime.isSwitchingMode)
                    }
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
            .navigationTitle(runtime.isDemoMode ? "演示 · TokenPulse" : "TokenPulse")
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
                        WatchWidgetSettingsView(accounts: displayedStates.map(\.account), runtime: runtime)
                    } label: {
                        Label("表盘设置", systemImage: "gearshape")
                    }
                    .accessibilityLabel("表盘设置")
                }
            }
        }
        .disabled(runtime.isSwitchingMode)
        .overlay {
            if runtime.isSwitchingMode { ProgressView() }
        }
    }

    private var displayedStates: [AccountQuotaState] {
        monitor.states.filter { monitor.configuration(for: $0.id)?.isWatchFavorite != false }
    }
}

private struct WatchWidgetSettingsView: View {
    let accounts: [SubscriptionAccount]
    @ObservedObject var runtime: AppRuntime
    @State private var selectedAccountID: UUID?
    private let store = WatchWidgetSelectionStore()

    var body: some View {
        Form {
            Section {
                Button(runtime.isDemoMode ? "退出演示 / Exit Demo" : "体验演示 / Try Demo") {
                    Task { await runtime.setDemoMode(!runtime.isDemoMode) }
                }
                .disabled(runtime.isSwitchingMode)
                if runtime.isDemoMode {
                    Text("当前为本机示例数据，退出后恢复真实账号。")
                        .font(.footnote)
                }
            }
            if !accounts.isEmpty {
                NavigationLink {
                    WatchWidgetAccountSelectionView(
                        accounts: accounts,
                        selectedAccountID: $selectedAccountID
                    )
                } label: {
                    LabeledContent("表盘显示账号", value: selectedAccount?.name ?? "未选择")
                }
            }
        }
        .navigationTitle("表盘设置")
        .task {
            let saved = await store.load()
            selectedAccountID = saved.flatMap { id in accounts.contains { $0.id == id } ? id : nil }
                ?? accounts.first?.id
        }
    }

    private var selectedAccount: SubscriptionAccount? {
        selectedAccountID.flatMap { id in accounts.first { $0.id == id } }
    }
}

private struct WatchWidgetAccountSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [SubscriptionAccount]
    @Binding var selectedAccountID: UUID?
    private let store = WatchWidgetSelectionStore()

    var body: some View {
        List(accounts) { account in
            Button {
                Task {
                    await store.save(account.id)
                    selectedAccountID = account.id
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    ProviderIcon(provider: account.provider, size: 14)
                    VStack(alignment: .leading) {
                        Text(account.name)
                        Text(account.provider.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedAccountID == account.id {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("选择账号")
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
                        if let wallet = window.wallet {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(wallet.currency).font(.caption.bold())
                                LabeledContent(wallet.isMonetary ? "总可用" : "剩余 \(wallet.currency)",
                                               value: QuotaFormatting.balance(wallet.total, wallet: wallet))
                                if wallet.isMonetary {
                                    LabeledContent("赠送", value: QuotaFormatting.balance(wallet.granted, wallet: wallet))
                                    LabeledContent("充值", value: QuotaFormatting.balance(wallet.toppedUp, wallet: wallet))
                                }
                            }
                            .font(.caption2)
                        } else if window.scope == nil || [.qoderInternational, .zai, .zhipu, .miniMaxChina, .miniMaxInternational].contains(state.account.provider) {
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
                                    LabeledContent(window.displayName, value: QuotaFormatting.usage(window))
                                        .font(.caption)
                                }
                                if let overage = QuotaFormatting.overageDescription(window) {
                                    Text(overage).font(.caption2)
                                }
                                if !window.isUnlimited, let remaining = window.remainingCount {
                                    LabeledContent("剩余", value: QuotaFormatting.count(remaining, unit: window.unit))
                                        .font(.caption2)
                                }
                                LabeledContent(
                                    QuotaFormatting.nextEventLabel(window),
                                    value: QuotaFormatting.resetDate(QuotaFormatting.nextEventDate(window))
                                )
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
                    if snapshot.walletAvailable == false {
                        Label(QuotaFormatting.walletUnavailableBadge, systemImage: "exclamationmark.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if snapshot.quotaExceeded == true {
                        Label(QuotaFormatting.quotaExceededBadge, systemImage: "exclamationmark.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
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
        if let plan = state.snapshot?.providerPlanName { return "\(state.account.provider.displayName) · \(plan)" }
        guard state.account.provider == .codex,
              let plan = state.snapshot?.subscriptionPlan else { return state.account.provider.displayName }
        return "\(state.account.provider.displayName) · \(plan.displayName)"
    }
}
