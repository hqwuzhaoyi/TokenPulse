import SwiftUI

struct WatchAccountPagesView: View {
    @Environment(\.scenePhase) private var scenePhase
    let runtime: AppRuntime
    @ObservedObject var monitor: QuotaMonitor
    @State private var selection: UUID?
    @State private var requestingNotificationPermission = false
    @State private var notificationFeedback: NotificationPermissionFeedback?

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
                    Button {
                        requestingNotificationPermission = true
                        Task {
                            let feedback = await runtime.notifications.requestAuthorization()
                            notificationFeedback = feedback
                            requestingNotificationPermission = false
                            if feedback == .enabled { await runtime.publish() }
                        }
                    } label: {
                        if requestingNotificationPermission {
                            ProgressView("处理中")
                        } else {
                            Label("开启通知", systemImage: "bell.badge")
                        }
                    }
                    .disabled(requestingNotificationPermission)
                    .accessibilityLabel("开启额度通知")
                }
            }
            .alert("通知设置", isPresented: Binding(
                get: { notificationFeedback != nil },
                set: { if !$0 { notificationFeedback = nil } }
            )) {
                Button("好") { notificationFeedback = nil }
            } message: {
                Text(notificationFeedback?.message ?? "")
            }
        }
    }

    private var displayedStates: [AccountQuotaState] {
        monitor.states
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
                Text(state.account.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let snapshot = state.snapshot {
                    ForEach(snapshot.windows) { window in
                        VStack(alignment: .leading, spacing: 3) {
                            if let percentage = window.usedPercentage, !window.isUnlimited {
                                Gauge(value: min(max(percentage, 0), 100), in: 0...100) {
                                    Text(window.name)
                                } currentValueLabel: {
                                    Text("\(percentage.formatted(.number.precision(.fractionLength(0...1))))%")
                                }
                                .gaugeStyle(.accessoryCircular)
                            } else {
                                LabeledContent(window.name, value: window.isUnlimited ? "无限" : "未提供")
                                    .font(.caption)
                            }
                            if let scope = window.scope {
                                Text(scope).font(.caption2).foregroundStyle(.secondary)
                            }
                            LabeledContent("重置", value: QuotaFormatting.resetDate(window.resetsAt))
                            .font(.caption2)
                            if window.needsUpdate(at: date) {
                                Label("待更新", systemImage: "clock.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
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

}
