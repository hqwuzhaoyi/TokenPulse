import SwiftUI

struct ProviderSignInView: View {
    let provider: Provider
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var login = DeviceLoginModel()
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            Group {
                if provider == .claude {
                    ClaudeSessionLoginView(onCredential: completion)
                } else {
                    Form {
                        if let session = login.session {
                            if let code = session.userCode {
                                Text("授权码").font(.caption)
                                Text(code).font(.title.monospaced()).textSelection(.enabled)
                            }
                            Link("前往 \(provider.displayName) 完成授权", destination: session.authorizationURL)
                            Text("完成网页授权后返回这里，应用会自动取得登录结果。")
                                .font(.caption).foregroundStyle(.secondary)
                            if login.message == nil {
                                ProgressView(login.reconnecting ? "连接恢复中，保留当前授权码" : "等待授权")
                            }
                        } else if login.message == nil { ProgressView("准备登录") }
                        if let message = login.message {
                            Text(message).foregroundStyle(.red)
                            Button(login.session == nil ? "重新授权" : "继续授权") { attempt += 1 }
                        }
                    }
                    .task(id: scenePhase == .active ? attempt : -1) {
                        guard scenePhase == .active else { return }
                        await login.authorize(provider: provider, completion: completion)
                    }
                }
            }
            .navigationTitle("登录 \(provider.displayName)")
            .toolbar { Button("取消") { dismiss() } }
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
            guard let pending = session else { return }
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
            case .network: message = "网络暂不可用，请恢复连接后继续授权。"
            default: message = "登录未完成，请重试或检查账号授权设置。"
            }
        } catch {
            guard !Task.isCancelled, activeRunID == runID else { return }
            message = "登录未完成，请重试。"
        }
    }
}
