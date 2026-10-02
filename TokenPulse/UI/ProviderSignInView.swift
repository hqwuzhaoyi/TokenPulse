import SwiftUI

struct ProviderSignInView: View {
    let provider: Provider
    var accountID: UUID = UUID()
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var login = DeviceLoginModel()
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            Group {
                if provider == .gemini {
                    GoogleNativeOAuthLoginView(provider: provider, accountID: accountID, complete: { callback, pending, id, project in
                        try await GeminiProviderClient(transport: URLSessionProviderTransport.rejectingRedirects(), now: Date.init)
                            .authorize(callback: callback, session: pending, accountID: id, configuredProject: project)
                    }, onCredential: completion)
                } else if provider == .antigravity {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("需要账号已获得 Antigravity 访问权限；Google 可能拒绝自有客户端的授权或查询。")
                            .font(.footnote).padding(.horizontal)
                        GoogleNativeOAuthLoginView(provider: provider, accountID: accountID, requestedScopes: AntigravityProviderClient.scopes,
                            complete: { callback, session, id, project in
                                try await AntigravityProviderClient(transport: URLSessionProviderTransport.rejectingRedirects(), now: Date.init)
                                    .authorize(callback: callback, session: session, accountID: id, configuredProject: project)
                            }, onCredential: completion)
                    }
                } else if provider == .claude {
                    ClaudeSessionLoginView(accountID: accountID, onCredential: completion)
                } else if provider == .cursor || provider == .grokBot {
                    CursorSessionLoginView(provider: provider, accountID: accountID, onCredential: completion)
                } else if provider == .stepFun {
                    StepFunSessionLoginView(accountID: accountID, onCredential: completion)
                } else if let profile = provider.webLoginProfile {
                    WebProviderSessionLoginView(provider: provider, profile: profile, accountID: accountID, onCredential: completion)
                } else {
                    Form {
                        if let session = login.session {
                            Section {
                                if let code = session.userCode {
                                    LabeledContent("授权码") {
                                        Text(code)
                                            .font(.title2.monospaced())
                                            .bold()
                                            .textSelection(.enabled)
                                    }
                                }
                                Link(destination: session.authorizationURL) {
                                    Label("前往 \(provider.displayName) 授权", systemImage: "safari")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            } header: {
                                Text("在浏览器中继续")
                            } footer: {
                                Text("完成网页授权后返回 TokenPulse，登录结果会自动同步。")
                            }
                            if login.message == nil {
                                Section {
                                    if provider == .copilot {
                                        Text("GitHub 授权页会显示 VS Code / Copilot 客户端。TokenPulse 使用其公开客户端，仅请求 read:user 权限。这是非官方接入，请手动输入本页授权码。")
                                            .font(.footnote)
                                    }
                                    ProgressView(login.reconnecting ? "正在恢复连接，授权码仍然有效" : "正在等待授权结果")
                                }
                            }
                        } else if login.message == nil {
                            Section { ProgressView("正在准备安全登录") }
                        }
                        if let message = login.message {
                            Section {
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Button(login.session == nil ? "重新授权" : "继续等待", systemImage: "arrow.clockwise") {
                                    attempt += 1
                                }
                            }
                        }
                    }
                    .task(id: scenePhase == .active ? attempt : -1) {
                        guard scenePhase == .active else { return }
                        await login.authorize(provider: provider, completion: completion)
                    }
                }
            }
            .navigationTitle("登录 \(provider.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

}

@MainActor
final class DeviceLoginModel: ObservableObject {
    @Published private(set) var session: ProviderLoginSession?
    @Published private(set) var message: String?
    @Published private(set) var reconnecting = false
    private var activeRunID: UUID?
    private var completed = false
    private let controller: ProviderAuthenticationController
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(controller: ProviderAuthenticationController = ProviderAuthenticationController(),
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds(max(1, $0)))
         }) {
        self.controller = controller
        self.sleep = sleep
    }

    func authorize(provider: Provider, completion: (String) -> Void) async {
        guard !completed else { return }
        let runID = UUID()
        activeRunID = runID
        defer { if activeRunID == runID { reconnecting = false } }
        message = nil
        do {
            if session == nil {
                let pending = try await controller.beginLogin(provider: provider)
                try Task.checkCancellation()
                guard activeRunID == runID else { return }
                session = pending
            }
            guard var pending = session else { return }
            if provider == .copilot { try await sleep(pending.pollingInterval ?? 5) }
            var networkFailures = 0
            while !Task.isCancelled {
                guard activeRunID == runID else { return }
                let result: ProviderLoginProgress
                do {
                    result = try await controller.continueLogin(pending)
                } catch let error as ProviderIntegrationError where error == .network {
                    try Task.checkCancellation()
                    guard activeRunID == runID else { return }
                    networkFailures += 1
                    guard networkFailures < 3 else { throw error }
                    reconnecting = true
                    try await sleep(max(2, pending.pollingInterval ?? 5))
                    continue
                }
                try Task.checkCancellation()
                guard activeRunID == runID else { return }
                networkFailures = 0
                reconnecting = false
                switch result {
                case .completed(let credential):
                    completed = true
                    completion(credential)
                    return
                case .pending(let retryAfter):
                    if provider == .copilot {
                        pending = ProviderLoginSession(
                            provider: pending.provider, authorizationURL: pending.authorizationURL,
                            userCode: pending.userCode, deviceCode: pending.deviceCode, state: pending.state,
                            codeVerifier: pending.codeVerifier, callbackURL: pending.callbackURL,
                            pollingInterval: retryAfter, expiresAt: pending.expiresAt, metadata: pending.metadata
                        )
                        session = pending
                    }
                    try await sleep(retryAfter)
                }
            }
        } catch is CancellationError {
            return
        } catch let error as ProviderIntegrationError {
            guard !Task.isCancelled, activeRunID == runID else { return }
            switch error {
            case .unsupportedLogin(let reason): message = reason
            case .loginExpired:
                session = nil
                message = "授权已过期，请重新开始。"
            case .invalidCredential where provider == .copilot:
                session = nil
                message = "GitHub 授权已拒绝或失效，请重新开始。"
            case .network: message = "网络暂不可用，请恢复连接后继续授权。"
            default: message = "登录未完成，请重试或检查账号授权设置。"
            }
        } catch {
            guard !Task.isCancelled, activeRunID == runID else { return }
            message = "登录未完成，请重试。"
        }
    }
}
