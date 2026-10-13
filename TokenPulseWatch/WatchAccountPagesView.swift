import SwiftUI

struct WatchAccountPagesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var runtime: AppRuntime
    @ObservedObject var monitor: QuotaMonitor
    var selectionStore = WatchWidgetSelectionStore()
    var automaticallyRefresh = true
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if displayedStates.isEmpty {
                    ScrollView {
                        ContentUnavailableView {
                            Label("没有账号", systemImage: "applewatch")
                        } description: {
                            Text("等待 iCloud 同步账号配置，或体验示例数据。")
                        } actions: {
                            Button("体验演示") { Task { await runtime.setDemoMode(true) } }
                                .disabled(runtime.isSwitchingMode)
                        }
                    }
                } else {
                    TabView(selection: $selection) {
                        ForEach(displayedStates) { state in
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                WatchAccountPage(
                                    state: state,
                                    monitor: monitor,
                                    isDemoMode: runtime.isDemoMode,
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
            .navigationTitle(runtime.isDemoMode ? L10n.text("演示 · TokenPulse") : "TokenPulse")
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, automaticallyRefresh else { return }
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchWidgetSettingsView(accounts: displayedStates.map(\.account), runtime: runtime, store: selectionStore)
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
    let store: WatchWidgetSelectionStore

    var body: some View {
        Form {
            Section {
                Button(runtime.isDemoMode ? L10n.text("退出演示") : L10n.text("体验演示")) {
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
                        selectedAccountID: $selectedAccountID, store: store
                    )
                } label: {
                    LabeledContent("表盘显示账号", value: selectedAccount.map { L10n.demoAccountName($0) } ?? L10n.text("未选择"))
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
    let store: WatchWidgetSelectionStore

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
                        Text(L10n.demoAccountName(account))
                        Text(account.provider.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedAccountID == account.id {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(selectedAccountID == account.id ? L10n.text("已选择") : L10n.text("未选择"))
        }
        .navigationTitle("选择账号")
    }
}

private struct WatchAccountPage: View {
    let state: AccountQuotaState
    @ObservedObject var monitor: QuotaMonitor
    let isDemoMode: Bool
    @State private var showingNousAuthorization = false
    @State private var showingJetBrainsImport = false
    let date: Date
    let isRefreshing: Bool
    let refresh: () async -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ProviderIcon(provider: state.account.provider, size: 24)
                Text(L10n.demoAccountName(state.account)).font(.headline)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(providerDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let snapshot = state.snapshot {
                    if let status = QuotaFormatting.quotaStatus(snapshot.quotaStatusText, provider: state.account.provider) {
                        Text(status).font(.caption2).foregroundStyle(.secondary)
                    } else if snapshot.isNoPlan == true {
                        Text("按量计费，无套餐或 Key 上限").font(.caption2)
                    }
                    if state.account.provider == .v0, !snapshot.windows.contains(where: { $0.id == "v0.billing" }) {
                        Text("账期 credits：未提供").font(.caption2).foregroundStyle(.secondary)
                    }
                    if state.account.provider == .v0, !snapshot.windows.contains(where: { $0.id == "v0.rate_limit" }) {
                        Text("消息限流：未提供").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.windows(for: state.account.provider, surface: .detail)) { window in
                        if let wallet = window.wallet {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(QuotaFormatting.balanceUnit(wallet)).font(.caption.bold())
                                LabeledContent(wallet.isMonetary ? L10n.text("总可用") : L10n.format("剩余 %@", QuotaFormatting.balanceUnit(wallet)),
                                               value: QuotaFormatting.balance(wallet.total, wallet: wallet))
                                if wallet.isMonetary {
                                    LabeledContent("赠送", value: QuotaFormatting.balance(wallet.granted, wallet: wallet))
                                    LabeledContent("充值", value: QuotaFormatting.balance(wallet.toppedUp, wallet: wallet))
                                }
                            }
                            .font(.caption2)
                        } else if window.scope == nil || window.hasDetailValues {
                            VStack(alignment: .leading, spacing: 3) {
                                if let percentage = QuotaFormatting.effectiveUsedPercentage(window) {
                                    Text(L10n.windowDisplayName(window, provider: state.account.provider))
                                        .font(.caption2).fixedSize(horizontal: false, vertical: true)
                                        .accessibilityHidden(true)
                                    Gauge(value: min(max(percentage, 0), 100), in: 0...100) {
                                        EmptyView()
                                    } currentValueLabel: {
                                        Text(window.isExhausted == true
                                             ? L10n.text("已用尽")
                                             : (percentage / 100).formatted(.percent.precision(.fractionLength(0...1))))
                                    }
                                    .gaugeStyle(.accessoryCircular)
                                    .accessibilityLabel(L10n.windowDisplayName(window, provider: state.account.provider))
                                    .accessibilityValue(QuotaFormatting.usage(window))
                                } else {
                                    LabeledContent(L10n.windowDisplayName(window, provider: state.account.provider), value: QuotaFormatting.usage(window))
                                        .font(.caption)
                                }
                                if let overage = QuotaFormatting.overageDescription(window) {
                                    Text(overage).font(.caption2)
                                }
                                if !window.isUnlimited, let counts = window.exactCounts {
                                    if let used = counts.used { LabeledContent("已用", value: QuotaFormatting.count(used, window: window)).font(.caption2) }
                                    if let remaining = counts.remaining { LabeledContent("剩余", value: QuotaFormatting.count(remaining, window: window)).font(.caption2) }
                                    if let total = counts.total { LabeledContent(QuotaFormatting.totalLabel(window), value: QuotaFormatting.count(total, window: window)).font(.caption2) }
                                } else if !window.isUnlimited, let remaining = window.remainingCount {
                                    LabeledContent("剩余", value: QuotaFormatting.count(remaining, window: window))
                                        .font(.caption2)
                                }
                                LabeledContent(
                                    QuotaFormatting.nextEventLabel(window),
                                    value: QuotaFormatting.nextEventValue(window)
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
                                L10n.windowDisplayName(window, provider: state.account.provider),
                                value: QuotaFormatting.usage(window)
                            )
                            .font(.caption2)
                        }
                    }
                    if state.account.provider == .codex {
                        LabeledContent("可手动重置", value: QuotaFormatting.remainingResets(snapshot.remainingResetCount))
                            .font(.caption2)
                    }
                    if let status = QuotaFormatting.walletCollectionStatus(failure: snapshot.walletFailure, collectedAt: snapshot.walletCollectedAt) {
                        Text(status).font(.caption2).foregroundStyle(snapshot.walletFailure == nil ? Color.secondary : Color.orange)
                    }
                    if snapshot.walletAvailable == false {
                        Label(QuotaFormatting.walletUnavailableBadge, systemImage: "exclamationmark.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if snapshot.quotaExceeded == true {
                        Label(QuotaFormatting.quotaExceededBadge, systemImage: "exclamationmark.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    Text(L10n.format("采集于 %@", snapshot.collectedAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚无成功采集数据").font(.caption).foregroundStyle(.secondary)
                }

                if let failure = state.lastFailure {
                    Label(
                        failure == .invalidCredential ? L10n.text("凭证尚未同步或已失效") : failure.displayName,
                        systemImage: failure == .invalidCredential ? "key.slash" : "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .id("watch-error-\(state.id.uuidString)")
                }

                if state.account.provider == .jetBrainsAI, !isDemoMode {
                    Button("在此 Watch 导入授权") { showingJetBrainsImport = true }
                        .disabled(monitor.configuration(for: state.id)?.credentialIdentity == nil)
                }
                if state.account.provider == .nousPortal, !isDemoMode {
                    Button("连接此 Watch") { showingNousAuthorization = true }
                        .disabled(monitor.configuration(for: state.id)?.credentialIdentity == nil)
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
                .accessibilityLabel("刷新")
                .accessibilityValue(isRefreshing ? L10n.text("正在刷新") : "")
                .accessibilityHint("独立查询此账号的最新额度")
            }
            .padding(.horizontal, 8)
        }
        .sheet(isPresented: $showingJetBrainsImport) {
            if let identity = monitor.configuration(for: state.id)?.credentialIdentity {
                JetBrainsImportView(accountID: state.id, expectedIdentity: identity, bindCredential: { value in
                    guard monitor.configuration(for: state.id)?.credentialIdentity == identity else { return false }
                    await monitor.replaceCredential(value, accountID: state.id, expectedIdentity: identity)
                    guard monitor.configuration(for: state.id)?.credentialIdentity == identity,
                          let version = try? await DeviceOAuthCredentialVault.shared.version(for: state.id),
                          let stored = version.credential,
                          let active = try? ProviderCredentialEnvelope.decode(stored, expectedProvider: .jetBrainsAI),
                          let receipt = try? ProviderCredentialEnvelope.decode(value, expectedProvider: .jetBrainsAI),
                          active.metadata["candidateRecordID"] == nil,
                          active.metadata["grantMarker"] == receipt.metadata["grantMarker"],
                          (try? JetBrainsCredential.fingerprint(active)) == identity else { return false }
                    return true
                }, completion: { _ in })
            }
        }
        .sheet(isPresented: $showingNousAuthorization) {
            if let identity = monitor.configuration(for: state.id)?.credentialIdentity {
                WatchNousAuthorizationView(accountID: state.id, expectedIdentity: identity) { value in
                    Task { await monitor.replaceCredential(value, accountID: state.id, expectedIdentity: identity) }
                }
            }
        }
    }

    private var providerDescription: String {
        if let snapshot = state.snapshot, let plan = QuotaFormatting.providerPlanName(snapshot.providerPlanName, presentation: snapshot.providerPlanPresentation) { return L10n.format("%@ · %@", state.account.provider.displayName, plan) }
        guard state.account.provider == .codex,
              let plan = state.snapshot?.subscriptionPlan else { return state.account.provider.displayName }
        return L10n.format("%@ · %@", state.account.provider.displayName, plan.displayName)
    }
}

#if DEBUG
extension WatchAccountPagesView {
    /// Reuses the production account page without the paging host for fixture viewport checks.
    static func accountFixture(state: AccountQuotaState, monitor: QuotaMonitor) -> some View {
        WatchAccountPage(state: state, monitor: monitor, isDemoMode: true, date: Date(),
                         isRefreshing: monitor.refreshingAccountIDs.contains(state.id)) {
            await monitor.refresh(accountID: state.id)
        }
    }
}
#endif
