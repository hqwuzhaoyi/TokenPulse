import SwiftUI
#if DEBUG
import WidgetKit
#endif

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var monitor: QuotaMonitor
    @ObservedObject var runtime: AppRuntime
    @State private var showingAddAccount = false
    @State private var accountsToDelete: [SubscriptionAccount] = []
    @State private var linkedAccount: UUID?
    @State private var selectedTab = AppTab.home
    @State private var resetPreviewDate = Date()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if monitor.states.isEmpty {
                        ContentUnavailableView {
                            Label("添加服务账号", systemImage: "waveform.path.ecg")
                        } description: {
                            Text("集中查看 AI 服务的套餐额度与 API 钱包余额。")
                        } actions: {
                            AddAccountButton { showingAddAccount = true }
                            if !runtime.isDemoMode {
                                Button("体验演示 / Try Demo") {
                                    Task { await runtime.setDemoMode(true) }
                                }
                                .disabled(runtime.isSwitchingMode)
                            }
                            if monitor.hasPendingCredentialCleanup {
                                Button("重试凭证清理") { Task { await monitor.retryPendingCredentialCleanup() } }
                            }
                        }
                    } else {
                        List {
                            if !runtime.isDemoMode, monitor.states.contains(where: { $0.account.provider == .codex }),
                               let status = monitor.codexResetStatus,
                               status.hasVisiblePreview(at: resetPreviewDate) {
                                CodexResetSection(status: status, unavailable: monitor.codexResetUnavailable, now: resetPreviewDate)
                            }
                            if monitor.hasPendingCredentialCleanup {
                                Section {
                                    Button("重试凭证清理", systemImage: "arrow.clockwise.circle") {
                                        Task { await monitor.retryPendingCredentialCleanup() }
                                    }
                                } footer: {
                                    Text("已移除账号的凭证未能清理，请重试。")
                                }
                            }
                            Section {
                                ForEach(monitor.states) { state in
                                    AccountQuotaView(
                                        state: state,
                                        walletCurrency: monitor.configuration(for: state.id)?.reminders.walletCurrency,
                                        isRefreshing: monitor.refreshingAccountIDs.contains(state.id),
                                        refresh: { await monitor.refresh(accountID: state.id) }
                                    )
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("删除", systemImage: "trash") {
                                            accountsToDelete = [state.account]
                                        }
                                        .tint(.red)
                                    }
                                }
                                .onMove { from, to in
                                    monitor.reorderAccounts(from: from, to: to)
                                    Task { await monitor.persistAccountOrder() }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .listRowSpacing(16)
                        .contentMargins(.top, 8, for: .scrollContent)
                        .refreshable { await monitor.refreshAll() }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if runtime.isDemoMode {
                        HStack {
                            Label("演示模式 · 示例数据", systemImage: "play.circle")
                                .font(.caption)
                            Spacer()
                            Button("退出演示") { Task { await runtime.setDemoMode(false) } }
                                .font(.caption.bold())
                                .disabled(runtime.isSwitchingMode)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .modifier(FloatingGlassSurface())
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("添加账号", systemImage: "plus") { showingAddAccount = true }
                    }
                }
                .sheet(isPresented: $showingAddAccount) {
                    AddAccountView(isDemoMode: runtime.isDemoMode, existingProviders: Set(monitor.states.map { $0.account.provider })) { name, key, provider, accountID in
                        let previousCount = monitor.states.count
                        await monitor.addAccount(name: name, credential: key, provider: provider, accountID: accountID)
                        return monitor.states.count > previousCount
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .tabItem {
                Label("主屏幕", systemImage: "house")
            }
            .tag(AppTab.home)

            AccountSettingsView(monitor: monitor, runtime: runtime, initialAccountID: linkedAccount)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .disabled(runtime.isSwitchingMode)
        .overlay {
            if runtime.isSwitchingMode {
                ProgressView("正在切换模式")
                    .padding(24)
                    .modifier(FloatingGlassSurface())
            }
        }
        .confirmationDialog("删除账号？", isPresented: Binding(
            get: { !accountsToDelete.isEmpty },
            set: { if !$0 { accountsToDelete = [] } }
        ), titleVisibility: .visible) {
            Button("删除账号", role: .destructive) {
                let accountIDs = accountsToDelete.map(\.id)
                accountsToDelete = []
                Task { for id in accountIDs { await monitor.deleteAccount(accountID: id) } }
            }
            Button("取消", role: .cancel) { accountsToDelete = [] }
        } message: {
            Text(runtime.isDemoMode
                 ? "将移除选中的演示账号及其示例数据。真实账号不受影响。"
                 : "将移除“\(accountsToDelete.map(\.name).joined(separator: "、"))”的凭证、额度数据和提醒；开启 iCloud 同步后也会从其他设备移除。")
        }
        .alert("本地存储错误", isPresented: Binding(
            get: { monitor.storageMessage != nil },
            set: { if !$0 { monitor.dismissStorageMessage() } }
        )) {
            Button("好") { monitor.dismissStorageMessage() }
        } message: {
            Text(monitor.storageMessage ?? "")
        }
        .onOpenURL { url in
            guard url.scheme == PlatformConstants.accountDeepLinkScheme else { return }
            if url.host == "account", let id = UUID(uuidString: url.lastPathComponent) {
                linkedAccount = id
                selectedTab = .settings
            } else if url.host == "accounts" {
                linkedAccount = nil
                selectedTab = .home
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            resetPreviewDate = date
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            resetPreviewDate = Date()
            Task { await monitor.applicationDidBecomeActive() }
        }
        .modifier(AuthorizationFixturePresentation())
    }
}

private enum AppTab: Hashable {
    case home
    case settings
}

private struct AddAccountButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button("添加账号", systemImage: "plus", action: action)
                .buttonStyle(.glassProminent)
        } else {
            Button("添加账号", systemImage: "plus", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Glass belongs to the floating controls; data surfaces remain opaque and legible.
private struct FloatingGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(uiColor: .secondarySystemBackground),
                               in: RoundedRectangle(cornerRadius: 20))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

private struct CodexResetSection: View {
    let status: CodexResetStatus?
    let unavailable: Bool
    var now: Date = Date()

    var body: some View {
        if let status, status.hasVisiblePreview(at: now) {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let reset = status.data.scheduledReset {
                        Label(L10n.text(reset.resetType == "banked" ? "重置次数发放预告" : "已公告 · 等待执行"), systemImage: "calendar.badge.clock")
                            .font(.subheadline.weight(.semibold))
                        if let date = reset.scheduledFor {
                            Text(L10n.format("预定时间：%@", CodexResetStatus.dateText(date)))
                            if date <= now {
                                Text("预定时间已过，尚未确认执行。")
                                    .foregroundStyle(Color.secondary)
                            }
                        } else {
                            Text("重置时间待定")
                        }
                        Text(reset.text).font(.subheadline)
                    } else if let watch = status.activeWatch(at: now) {
                        Label("AI 重置预测 · 非官方承诺", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.format("预测时段：%@", watch.forecastWindow))
                        if let chance = CodexResetStatus.chanceText(watch.resetChancePercent) {
                            Text(L10n.format("预测概率 %@", chance))
                        }
                        Text(watch.text).font(.subheadline)
                        Text(L10n.format("有效至 %@", CodexResetStatus.dateText(watch.expiresAt)))
                            .font(.caption).foregroundStyle(Color.secondary)
                    }
                    if let latest = status.data.latestReset {
                        Text(L10n.format(latest.resetType == "banked" ? "来源最近报告发放重置次数：%@" : "来源最近报告重置：%@",
                                         CodexResetStatus.dateText(latest.announcedAt)))
                            .font(.caption).foregroundStyle(Color.secondary)
                    }
                    Text(L10n.format("数据更新于 %@", CodexResetStatus.dateText(status.meta.generatedAt)))
                        .font(.caption).foregroundStyle(Color.secondary)
                    if unavailable {
                        Text("重置预告暂时无法更新，当前显示上次数据")
                            .font(.caption).foregroundStyle(Color.secondary)
                    }
                }
            } header: {
                Text("Codex 重置预告")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开启通知及 Codex 账号的重置提醒后，刷新发现新预告时提醒。后台检查时间由系统安排。")
                    Text("公告与预测来自第三方来源，不代表 OpenAI 官方承诺；实际额度以账号刷新结果为准。")
                    Link("数据来源：Codex Resets", destination: CodexResetStatus.sourceURL)
                        .foregroundStyle(Color.secondary)
                        .accessibilityHint(L10n.format("打开数据来源 %@", CodexResetStatus.sourceURL.absoluteString))
                }
            }
        }
    }
}

#if DEBUG
/// Launch-only fixture routing for the isolated UI acceptance harness.
/// Release builds contain no authorization fixture routes or transports.
private struct AuthorizationFixturePresentation: ViewModifier {
    @Environment(\.acceptanceRoutesDisabled) private var acceptanceRoutesDisabled
    @State private var fixture: AuthorizationFixture?
    @State private var checkedArguments = false
    @State private var quotaFixture: QuotaAcceptanceFixture?
    @State private var widgetFixture: WidgetAcceptanceFixture?
    @State private var accountFixture = false
    @State private var codexFixture: CodexAcceptanceScenario?

    func body(content: Content) -> some View {
        content
            .sheet(item: $fixture) { fixture in
                ProviderSignInView(
                    provider: fixture.provider,
                    accountID: UUID(uuidString: "FA000000-0000-0000-0000-000000000003")!,
                    loginModel: fixture.isDevice
                        ? DeviceLoginModel.authorizationFixture(failingInitially: fixture == .deviceRecovery)
                        : nil,
                    completion: { _ in }
                )
                .environment(\.openURL, OpenURLAction { _ in .handled })
            }
            .sheet(item: $quotaFixture) { fixture in
                QuotaAcceptanceFixtureView(fixture: fixture)
            }
            .sheet(item: $widgetFixture) { fixture in
                WidgetAcceptanceFixtureView(fixture: fixture)
            }
            .sheet(isPresented: $accountFixture) { AccountAcceptanceFixtureView() }
            .sheet(item: $codexFixture) { CodexAcceptanceFixtureView(scenario: $0).interactiveDismissDisabled() }
            .onAppear {
                guard !acceptanceRoutesDisabled, !checkedArguments else { return }
                checkedArguments = true
                let arguments = ProcessInfo.processInfo.arguments
                if let marker = arguments.firstIndex(of: "-TokenPulseCodexFixture"),
                   arguments.indices.contains(marker + 1) {
                    codexFixture = CodexAcceptanceScenario(rawValue: arguments[marker + 1])
                } else if arguments.contains("-TokenPulseAccountFixture") {
                    accountFixture = true
                } else if let marker = arguments.firstIndex(of: "-TokenPulseAuthorizationFixture"),
                   arguments.indices.contains(marker + 1) {
                    fixture = AuthorizationFixture(rawValue: arguments[marker + 1])
                } else if let marker = arguments.firstIndex(of: "-TokenPulseQuotaFixture"),
                          arguments.indices.contains(marker + 1) {
                    quotaFixture = QuotaAcceptanceFixture(rawValue: arguments[marker + 1])
                } else if let marker = arguments.firstIndex(of: "-TokenPulseWidgetFixture"),
                          arguments.indices.contains(marker + 1),
                          WidgetDebugFixture.supportedScenarios.contains(arguments[marker + 1]) {
                    let familyMarker = arguments.firstIndex(of: "-TokenPulseWidgetFamily")
                    let familyName = familyMarker.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "small"
                    widgetFixture = WidgetAcceptanceFixture(scenario: arguments[marker + 1], familyName: familyName)
                }
            }
    }
}

private enum AuthorizationFixture: String, Identifiable {
    case google, jetbrains, device, deviceRecovery
    var id: String { rawValue }
    var isDevice: Bool { self == .device || self == .deviceRecovery }
    var provider: Provider {
        switch self {
        case .google: .gemini
        case .jetbrains: .jetBrainsAI
        case .device, .deviceRecovery: .copilot
        }
    }
}

private enum QuotaAcceptanceFixture: String, Identifiable {
    case wallet, budget, credits, gpu, hybrid, dateOnly, legacy
    case characters, hours, unknownUnits, modelNames, manusRefill, ownedScope, payAsYouGo, teamPlan
    var id: String { rawValue }
    var provider: Provider {
        switch self {
        case .wallet: .deepSeek
        case .budget: .chutes
        case .credits: .poe
        case .gpu: .huggingFace
        case .hybrid: .xiaomiCodingPlan
        case .dateOnly: .copilot
        case .legacy: .miniMaxChina
        case .characters: .elevenLabs
        case .hours: .amp
        case .unknownUnits, .modelNames: .antigravity
        case .manusRefill: .manus
        case .ownedScope: .aixy
        case .payAsYouGo: .devPass
        case .teamPlan: .xaiAPI
        }
    }
}

private struct QuotaAcceptanceFixtureView: View {
    let fixture: QuotaAcceptanceFixture
    @Environment(\.dismiss) private var dismiss

    private var supplementalSnapshot: QuotaSnapshot? {
        let id = UUID(uuidString: "FA000000-0000-0000-0000-000000000004")!
        let now = Date(timeIntervalSince1970: 1_791_691_200)
        switch fixture {
        case .characters:
            return .init(accountID: id, windows: try! ElevenLabsProviderClient.windows(Data(#"{"character_count":1,"character_limit":3}"#.utf8)), collectedAt: now)
        case .hours:
            let text = "Amp Megawatt Tier: agent usage $18.57 of $20 remaining (93%), orb usage 1h of 3h a1.small orb hours remaining (33%) - period 2026-09-13 to 2026-10-13, resets upon renewal in 27 days"
            return try! AmpProviderClient.snapshot(JSONSerialization.data(withJSONObject: ["ok": true, "result": ["displayText": text]]), accountID: id, collectedAt: now)
        case .unknownUnits:
            return try! AntigravityProviderClient.snapshot(Data(#"{"groups":[{"buckets":[{"bucketId":"amount","displayName":"Original model 原文","remainingAmount":"1"}]}]}"#.utf8), accountID: id, collectedAt: now)
        case .modelNames:
            return try! AntigravityProviderClient.snapshot(Data(#"{"groups":[{"buckets":[{"bucketId":"enabled","displayName":"原始模型（未启用）","remainingFraction":0.5},{"bucketId":"disabled","displayName":"原始模型（未启用）","disabled":true,"remainingFraction":0.5}]}]}"#.utf8), accountID: id, collectedAt: now)
        case .manusRefill:
            return try! ManusProviderClient.snapshot(Data(#"{"refreshCredits":1,"maxRefreshCredits":3,"refreshInterval":"weekly"}"#.utf8), accountID: id, collectedAt: now)
        case .ownedScope:
            let budget: [String: Any] = ["id": "a", "scope": "team", "target_name": "Original target 原文", "shared": true,
                "interval": "monthly", "enforcement": "monitor", "limit_usd": "10",
                "applies_to": [["api_key_id": "key-a", "project_id": "project-a"]],
                "spend_status": "available", "spend_usd": "1"]
            let data = try! JSONSerialization.data(withJSONObject: ["object": "key.usage", "currency": "USD",
                "key": ["id": "key-a", "project_id": "project-a"], "budgets": [budget]])
            return try! AixyProviderClient.snapshot(data, accountID: id, collectedAt: now)
        case .payAsYouGo:
            return try! DevPassProviderClient.snapshot(Data(#"{"data":{"devPlan":"none","usage":"1","limit":"10"}}"#.utf8), accountID: id, collectedAt: now)
        case .teamPlan:
            return try! XAIAPIProviderClient.snapshot(Data(#"{"total":{"val":"-1234"}}"#.utf8), accountID: id, teamID: "original-team-原文", collectedAt: now)
        default: return nil
        }
    }

    private var windows: [QuotaWindow] {
        if let supplementalSnapshot { return supplementalSnapshot.windows }
        let time = Date(timeIntervalSince1970: 1_791_691_200)
        var windows = DemoMode.snapshot(
            accountID: UUID(uuidString: "FA000000-0000-0000-0000-000000000004")!,
            provider: fixture.provider, now: time
        ).windows
        if fixture == .dateOnly {
            windows = [QuotaWindow(
                id: "copilot.premium_interactions", name: "Premium requests", scope: nil,
                period: .monthly, usedPercentage: 25, remainingCount: nil, totalCount: nil,
                resetsAt: time.addingTimeInterval(12 * 86_400), unit: "次",
                exactCounts: DecimalQuotaCounts(used: 25, remaining: 75, total: 100),
                resetDatePrecision: .day
            )]
        } else if fixture == .legacy {
            windows = [QuotaWindow(id: "MiniMax-M2.5.interval", name: "5 小时额度", scope: "MiniMax-M2.5",
                                   period: .fiveHour, usedPercentage: 36, remainingCount: nil,
                                   totalCount: nil, resetsAt: time)]
        }
        return windows
    }

    var body: some View {
        NavigationStack {
            List {
                if [.payAsYouGo, .teamPlan].contains(fixture), let snapshot = supplementalSnapshot {
                    AccountQuotaView(state: .init(account: .init(id: snapshot.accountID, name: "Original account 原文", provider: fixture.provider), snapshot: snapshot),
                                     walletCurrency: nil, isRefreshing: false, refresh: {})
                } else {
                    ForEach(windows) { window in
                        QuotaWindowView(window: window, provider: fixture.provider)
                    }
                }
            }
            .navigationTitle(fixture.provider.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct WidgetAcceptanceFixture: Identifiable {
    let scenario: String
    let familyName: String
    var id: String { scenario + "." + familyName }
    var family: WidgetFamily {
        switch familyName {
        case "medium": .systemMedium
        case "large": .systemLarge
        case "rectangular": .accessoryRectangular
        case "circular": .accessoryCircular
        case "inline": .accessoryInline
        default: .systemSmall
        }
    }
    var presentationFamily: WidgetPresentationFamily {
        family == .systemLarge ? .large : family == .systemMedium ? .medium : .single
    }
    var size: CGSize {
        switch familyName {
        case "medium": CGSize(width: 338, height: 158)
        case "large": CGSize(width: 338, height: 354)
        case "rectangular": CGSize(width: 160, height: 72)
        case "circular": CGSize(width: 76, height: 76)
        case "inline": CGSize(width: 260, height: 30)
        default: CGSize(width: 158, height: 158)
        }
    }
}

private struct WidgetAcceptanceFixtureView: View {
    let fixture: WidgetAcceptanceFixture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuotaWidgetView(entry: WidgetDebugFixture.entry(scenario: fixture.scenario, family: fixture.presentationFamily), familyOverride: fixture.family)
                // WidgetKit supplies standard home-screen content margins in its real host.
                .padding(["small", "medium", "large"].contains(fixture.familyName) ? 16 : 0)
                .frame(width: fixture.size.width, height: fixture.size.height)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()
                .navigationTitle("TokenPulse")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                }
        }
    }
}

private struct AccountAcceptanceFixtureView: View {
    @StateObject private var monitor = DemoMode.makeMonitor(suiteName: "com.tokenpulse.i18n.account.\(UUID().uuidString)")
    @State private var showingForm = true
    @State private var savedAccountID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let id = savedAccountID, let state = monitor.states.first(where: { $0.id == id }) {
                    AccountQuotaView(state: state, walletCurrency: nil, isRefreshing: false,
                                     refresh: { await monitor.refresh(accountID: id) })
                }
            }
            .navigationTitle("TokenPulse")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .sheet(isPresented: $showingForm) {
                AddAccountView(isDemoMode: false, existingProviders: []) { name, credential, provider, id in
                    await monitor.addAccount(name: name, credential: credential, provider: provider, accountID: id)
                    let saved = monitor.states.contains { $0.id == id }
                    if saved { savedAccountID = id }
                    return saved
                }
            }
            .task { await monitor.start(refresh: false) }
        }
    }
}
private struct AcceptanceRoutesDisabledKey: EnvironmentKey {
    nonisolated static let defaultValue = false
}

private extension EnvironmentValues {
    var acceptanceRoutesDisabled: Bool {
        get { self[AcceptanceRoutesDisabledKey.self] }
        set { self[AcceptanceRoutesDisabledKey.self] = newValue }
    }
}

private enum CodexAcceptanceScenario: String, Identifiable {
    case scheduled, forecast, empty, historyOnly, expired, canceled, retainedFailure
    var id: String { rawValue }
}

@MainActor
private final class CodexAcceptanceSequence {
    let scenario: CodexAcceptanceScenario
    let now = Date()
    private var calls = 0

    init(scenario: CodexAcceptanceScenario) { self.scenario = scenario }

    func next() throws -> CodexResetStatus {
        calls += 1
        if scenario == .retainedFailure, calls > 1 { throw URLError(.notConnectedToInternet) }
        let announcement = CodexResetStatus.Announcement(
            id: "fixture-announcement", resetType: "usage", announcedAt: now.addingTimeInterval(-120),
            scheduledFor: now.addingTimeInterval(-60), text: "Original announcement 原文")
        let watch = CodexResetStatus.Watch(
            level: "high", resetChancePercent: 75, forecastWindow: "Original window 原文",
            observedAt: now, expiresAt: now.addingTimeInterval(scenario == .expired ? -60 : 900),
            text: "Original prediction 原文")
        let empty = scenario == .empty || (scenario == .canceled && calls > 1)
        return CodexResetStatus(
            data: .init(latestReset: scenario == .historyOnly ? announcement : nil,
                        scheduledReset: scenario == .scheduled ? announcement : nil,
                        activeWatch: !empty && [.forecast, .expired, .canceled, .retainedFailure].contains(scenario) ? watch : nil),
            meta: .init(generatedAt: now))
    }
}

private struct CodexAcceptanceFixtureView: View {
    @StateObject private var monitor: QuotaMonitor
    @StateObject private var runtime: AppRuntime
    @State private var ready = false
    private let sequence: CodexAcceptanceSequence

    init(scenario: CodexAcceptanceScenario) {
        let suite = "com.tokenpulse.i18n.codex.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "cloudSyncEnabled")
        let account = DemoMode.accounts().first { $0.provider == .codex }!
        let state = AccountQuotaState(account: account, snapshot: DemoMode.snapshot(accountID: account.id, provider: .codex))
        defaults.set(try? JSONEncoder().encode([state]), forKey: "accountQuotaStates")
        defaults.set(try? JSONEncoder().encode([AccountConfiguration(account: account)]), forKey: "accountConfigurations")
        _monitor = StateObject(wrappedValue: DemoMode.makeMonitor(suiteName: suite))
        let runtimeDefaults = UserDefaults(suiteName: suite + ".runtime")!
        runtimeDefaults.set(false, forKey: "cloudSyncEnabled")
        _runtime = StateObject(wrappedValue: AppRuntime(defaultsSuiteName: suite + ".runtime",
                                                       demoSuiteName: suite + ".demo",
                                                       widgetStore: WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite + ".widgets"))))
        sequence = CodexAcceptanceSequence(scenario: scenario)
    }

    var body: some View {
        Group {
            if ready {
                ContentView(monitor: monitor, runtime: runtime)
                    .environment(\.acceptanceRoutesDisabled, true)
                    .environment(\.openURL, OpenURLAction { _ in .handled })
            } else { ProgressView() }
        }
        .task {
            guard !ready else { return }
            await monitor.start(refresh: false)
            monitor.fetchCodexResets = { try sequence.next() }
            if let accountID = monitor.states.first?.id { await monitor.refresh(accountID: accountID) }
            ready = true
        }
    }
}

#else
private struct AuthorizationFixturePresentation: ViewModifier {
    func body(content: Content) -> some View { content }
}
#endif
