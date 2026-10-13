import SwiftUI
import WatchKit

@MainActor
final class TokenPulseWatchDelegate: NSObject, WKApplicationDelegate, ObservableObject {
    let runtime: AppRuntime = {
        #if DEBUG
        if let mode = WatchLocalizationFixture.mode { return WatchLocalizationFixture.runtime(mode: mode) }
        #endif
        return AppRuntime()
    }()

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for backgroundTask in backgroundTasks {
            guard backgroundTask is WKApplicationRefreshBackgroundTask else {
                backgroundTask.setTaskCompletedWithSnapshot(false)
                continue
            }
            let work = Task { @MainActor [runtime] in
                await runtime.refresh()
                await runtime.scheduleBackgroundRefresh()
                backgroundTask.setTaskCompletedWithSnapshot(true)
            }
            backgroundTask.expirationHandler = {
                work.cancel()
                backgroundTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main
struct TokenPulseWatchApp: App {
    @WKApplicationDelegateAdaptor(TokenPulseWatchDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchRootView(runtime: delegate.runtime)
        }
    }
}

private struct WatchRootView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Group {
            #if DEBUG
            if let mode = WatchLocalizationFixture.mode {
                WatchLocalizationFixtureRoot(runtime: runtime, mode: mode)
            } else {
                productionView
            }
            #else
            productionView
            #endif
        }
    }

    private var productionView: some View {
        WatchAccountPagesView(runtime: runtime, monitor: runtime.monitor)
            .id(runtime.isDemoMode)
            .task {
                _ = await runtime.notifications.requestAuthorization()
                await runtime.start()
            }
    }
}

#if DEBUG
/// Explicit launch-argument fixtures use dedicated stores and the existing in-memory demo clients.
@MainActor
private enum WatchLocalizationFixture {
    static var mode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-TokenPulseWatchFixture"), arguments.indices.contains(flag + 1),
              ["demo", "empty", "long", "error", "nous", "nous-waiting", "jetbrains"].contains(arguments[flag + 1]) else { return nil }
        return arguments[flag + 1]
    }

    static func suite(_ mode: String, _ purpose: String) -> String {
        "com.tokenpulse.tests.watch-i18n.\(mode).\(purpose)"
    }

    static func runtime(mode: String) -> AppRuntime {
        let realSuite = suite(mode, "runtime"), demoSuite = suite(mode, "demo"), widgetSuite = suite(mode, "widgets")
        for name in [realSuite, demoSuite, widgetSuite] {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        let defaults = UserDefaults(suiteName: realSuite)!
        defaults.set(false, forKey: "cloudSyncEnabled")
        defaults.set(mode != "empty", forKey: DemoMode.enabledKey)
        let demos = UserDefaults(suiteName: demoSuite)!
        let providers: [Provider] = [.claude, .deepSeek, .codex, .nousPortal, .jetBrainsAI, .huggingFace]
        var accounts = providers.compactMap { provider in DemoMode.accounts().first { $0.provider == provider } }
        if mode == "long", !accounts.isEmpty {
            // This mixed-language user account name is intentional and must remain verbatim.
            accounts[0].name = "我的工作账号 / My very long Claude workspace Ω · 研究团队"
        }
        let states = accounts.map { account in
            AccountQuotaState(account: account, snapshot: DemoMode.snapshot(accountID: account.id, provider: account.provider),
                              lastFailure: mode == "error" ? .invalidCredential : nil)
        }
        demos.set(try? JSONEncoder().encode(states), forKey: "accountQuotaStates")
        demos.set(try? JSONEncoder().encode(accounts.map { AccountConfiguration(account: $0) }), forKey: "accountConfigurations")
        return AppRuntime(defaultsSuiteName: realSuite, demoSuiteName: demoSuite,
                          widgetStore: WidgetSnapshotStore(defaults: UserDefaults(suiteName: widgetSuite)))
    }
}

private struct WatchLocalizationFixtureRoot: View {
    @ObservedObject var runtime: AppRuntime
    let mode: String
    @Environment(\.dynamicTypeSize) private var currentTypeSize
    @State private var showingAuthorization: Bool
    @StateObject private var nousLogin = WatchNousAuthorizationView.authorizationFixture()

    init(runtime: AppRuntime, mode: String) {
        self.runtime = runtime
        self.mode = mode
        _showingAuthorization = State(initialValue: mode == "nous" || mode == "nous-waiting" || mode == "jetbrains")
    }
    private let accountID = UUID(uuidString: "08000000-0000-0000-0000-000000000001")!

    private var fixtureTypeSize: DynamicTypeSize {
        ProcessInfo.processInfo.arguments.contains("-TokenPulseWatchLargeType") ? .accessibility5 : currentTypeSize
    }

    var body: some View {
        Group {
            if mode == "error" {
                WatchLocalizationErrorFixture(monitor: runtime.monitor)
            } else {
                WatchAccountPagesView(runtime: runtime, monitor: runtime.monitor,
                                      selectionStore: WatchWidgetSelectionStore(suiteName: WatchLocalizationFixture.suite(mode, "widgets")),
                                      automaticallyRefresh: false)
                    .task { await runtime.monitor.start(refresh: false) }
            }
        }
        .id(runtime.isDemoMode)
        .sheet(isPresented: $showingAuthorization) {
            Group {
                if mode == "nous" || mode == "nous-waiting" {
                    ScrollViewReader { proxy in
                        WatchNousAuthorizationView(accountID: accountID, expectedIdentity: "visual-fixture",
                                                   loginModel: nousLogin) { _ in }
                            .task {
                                if mode == "nous-waiting" {
                                    nousLogin.start(accountID: accountID, expectedIdentity: "visual-fixture") { _ in }
                                }
                            }
                            .onChange(of: nousLogin.session?.userCode) { _, code in
                                guard mode == "nous-waiting", code != nil else { return }
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(150))
                                    proxy.scrollTo("watch-authorization-code", anchor: .top)
                                }
                            }
                    }
                } else if mode == "jetbrains" {
                    JetBrainsImportView(accountID: accountID, completion: { _ in })
                }
            }
            // A modal has its own environment boundary; override its fixture font size explicitly.
            .environment(\.dynamicTypeSize, fixtureTypeSize)
        }
        .environment(\.openURL, OpenURLAction { _ in .handled })
        .environment(\.dynamicTypeSize, fixtureTypeSize)
    }
}

private struct WatchLocalizationErrorFixture: View {
    @ObservedObject var monitor: QuotaMonitor

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Group {
                    if let state = monitor.states.first {
                        WatchAccountPagesView.accountFixture(state: state, monitor: monitor)
                    } else {
                        ProgressView()
                    }
                }
                .task {
                    await monitor.start(refresh: false)
                    guard let id = monitor.states.first?.id else { return }
                    try? await Task.sleep(for: .milliseconds(150))
                    proxy.scrollTo("watch-error-\(id.uuidString)", anchor: .center)
                }
            }
            .navigationTitle(L10n.text("演示 · TokenPulse"))
        }
    }
}
#endif
