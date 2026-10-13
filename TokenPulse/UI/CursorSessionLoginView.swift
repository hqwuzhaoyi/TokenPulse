import SwiftUI
import WebKit

struct CursorSessionLoginView: View {
    let provider: Provider
    @StateObject private var model: CursorSessionLoginModel
    init(provider: Provider = .cursor, accountID: UUID, onCredential: @escaping (String) -> Void) {
        self.provider = provider
        _model = StateObject(wrappedValue: CursorSessionLoginModel(provider: provider, accountID: accountID, onCredential: onCredential))
    }
    var body: some View {
        VStack(spacing: 12) {
            Text(provider == .grokBot
                 ? L10n.text("通过 Cursor 账号授权，仅查询独立 Grok Bot 每周额度；不会合并 Cursor 月度额度或 SuperGrok。此临时浏览器不读取编辑器或 Safari 登录。")
                 : L10n.text("在此账号专用临时浏览器中登录 Cursor。此非官方接入使用 Cursor/Grok 客户端的已知授权页；不读取编辑器或 Safari 登录。"))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if let container = model.container { CursorAccountWebView(webView: container.webView).id(ObjectIdentifier(container.webView)) }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if model.waiting { ProgressView("等待授权并验证额度") }
            Button("清除会话并重新登录") { model.start() }
                .buttonStyle(.bordered)
        }
        .task { model.start() }
        .onDisappear { model.close() }
    }
}

@MainActor
final class CursorSessionLoginModel: ObservableObject {
    @Published private(set) var container: WebSessionContainer?
    @Published private(set) var message: String?
    @Published private(set) var waiting = false
    private let provider: Provider
    private let accountID: UUID
    private let onCredential: (String) -> Void
    private let auth: CursorAccountAuthenticator
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let query: @MainActor (UUID, String) async throws -> Void
    private let loadPage: @MainActor (WebSessionContainer, URL) -> Void
    private var runID = UUID()
    private var task: Task<Void, Never>?

    init(provider: Provider = .cursor, accountID: UUID, onCredential: @escaping (String) -> Void,
         auth: CursorAccountAuthenticator? = nil,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         query: (@MainActor (UUID, String) async throws -> Void)? = nil,
         loadPage: @escaping @MainActor (WebSessionContainer, URL) -> Void = { $0.webView.load(URLRequest(url: $1)) }) {
        self.provider = provider
        self.accountID = accountID
        self.onCredential = onCredential
        self.auth = auth ?? .init(provider: provider, transport: URLSessionProviderTransport.rejectingRedirects(), now: Date.init)
        self.sleep = sleep
        self.query = query ?? { id, credential in
            _ = try await ProviderQuotaClient(provider: provider).quota(for: id, credential: credential)
        }
        self.loadPage = loadPage
    }

    @discardableResult
    func start() -> Task<Void, Never> {
        close()
        message = nil
        waiting = true
        let run = runID
        let container = WebSessionContainer(scope: .init(provider: provider, accountID: accountID, host: "cursor.com"))
        self.container = container
        let attempt = auth.begin(accountID: accountID)
        loadPage(container, attempt.authorizationURL)
        let newTask = Task { @MainActor in
            defer { if runID == run { waiting = false; task = nil } }
            do {
                while runID == run && !Task.isCancelled && !container.closed {
                    try await sleep(attempt.pollingInterval ?? 2)
                    guard runID == run, !Task.isCancelled, !container.closed else { return }
                    let result: ProviderLoginProgress
                    do { result = try await auth.poll(attempt) }
                    catch let error as ProviderIntegrationError where error == .network || error == .server || error == .rateLimited {
                        // Retry only this nonce while its own expiry remains valid.
                        if error == .rateLimited { try await sleep(30) }
                        continue
                    }
                    guard runID == run, !Task.isCancelled, !container.closed else { return }
                    if case .completed(let credential) = result {
                        try await query(accountID, credential)
                        guard runID == run, !Task.isCancelled, !container.closed else { return }
                        onCredential(credential)
                        close()
                        return
                    }
                }
            } catch is CancellationError { return }
            catch {
                guard runID == run, !Task.isCancelled, !container.closed else { return }
                if error as? ProviderIntegrationError == .loginExpired { message = L10n.text("授权已过期，请重新登录。") }
                else if error as? ProviderIntegrationError == .invalidCredential || error as? RefreshFailure == .invalidCredential { message = L10n.text("Cursor 授权被拒绝或已过期，请重新登录。") }
                else { message = (error as? RefreshFailure)?.displayName ?? L10n.text("无法完成授权与额度验证，请重试。") }
            }
        }
        task = newTask
        return newTask
    }

    func close() {
        runID = UUID()
        task?.cancel()
        task = nil
        container?.close()
        container = nil
        waiting = false
    }
}

private struct CursorAccountWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
