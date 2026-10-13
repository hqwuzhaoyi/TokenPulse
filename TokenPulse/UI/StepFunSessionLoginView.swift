import SwiftUI
import WebKit

struct StepFunSessionLoginView: View {
    @StateObject private var model: StepFunSessionLoginModel
    @State private var site = StepFunSite.china

    init(accountID: UUID, onCredential: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: StepFunSessionLoginModel(accountID: accountID, onCredential: onCredential))
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("站点", selection: $site) {
                ForEach(StepFunSite.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            Text("国内站和国际站分别登录。切换站点会清除本次临时会话；完成验证后保存所选站点的凭证。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if let webView = model.container?.webView {
                StepFunWebView(webView: webView).id(ObjectIdentifier(webView))
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal)
            }
            Button(model.verifying ? L10n.text("正在验证") : L10n.text("完成登录并验证")) {
                model.beginVerification()
            }
            .buttonStyle(.borderedProminent).disabled(model.verifying)
            Button("清除会话并重新登录") { model.start(site: site) }.disabled(model.verifying)
            Text("登录只在此账号的临时浏览器中进行；仅保存查询套餐所需的会话与设备标识。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        .task { model.start(site: site) }
        .onChange(of: site) { _, site in model.start(site: site) }
        .onDisappear { model.close() }
    }
}

@MainActor
final class StepFunSessionLoginModel: ObservableObject {
    @Published private(set) var container: WebSessionContainer?
    @Published private(set) var message: String?
    @Published private(set) var verifying = false
    private let accountID: UUID
    private let onCredential: (String) -> Void
    private var completed = false
    private var runID = UUID()
    private var site = StepFunSite.china
    private var verificationTask: Task<Void, Never>?
    private let readCookies: @MainActor (WebSessionContainer) async -> [HTTPCookie]
    private let query: @MainActor (UUID, String) async throws -> Void
    private let loadPage: @MainActor (WebSessionContainer, URL) -> Void

    init(accountID: UUID, onCredential: @escaping (String) -> Void,
         readCookies: @escaping @MainActor (WebSessionContainer) async -> [HTTPCookie] = { container in
             await withCheckedContinuation { continuation in
                 container.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                     continuation.resume(returning: $0)
                 }
             }
         },
         query: @escaping @MainActor (UUID, String) async throws -> Void = { accountID, credential in
             _ = try await ProviderQuotaClient(provider: .stepFun).quota(for: accountID, credential: credential)
         },
         loadPage: @escaping @MainActor (WebSessionContainer, URL) -> Void = { container, url in
             container.webView.load(URLRequest(url: url))
         }) {
        self.accountID = accountID
        self.onCredential = onCredential
        self.readCookies = readCookies
        self.query = query
        self.loadPage = loadPage
    }

    func start(site: StepFunSite) {
        close()
        self.site = site
        message = nil
        completed = false
        let container = WebSessionContainer(scope: .init(provider: .stepFun, accountID: accountID, host: site.host))
        self.container = container
        loadPage(container, site.usageURL)
    }

    func close() {
        runID = UUID()
        verificationTask?.cancel()
        verificationTask = nil
        container?.close()
        container = nil
        verifying = false
    }

    @discardableResult
    func beginVerification() -> Task<Void, Never>? {
        guard verificationTask == nil, !verifying, !completed, container?.closed == false else { return nil }
        let run = runID
        let task = Task { @MainActor in
            await verify(expectedRun: run)
            if runID == run { verificationTask = nil }
        }
        verificationTask = task
        return task
    }

    private func verify(expectedRun: UUID) async {
        guard runID == expectedRun, !Task.isCancelled, !verifying, !completed,
              let container, !container.closed else { return }
        let run = runID
        let selectedSite = site
        verifying = true
        defer { if runID == run { verifying = false } }
        do {
            let cookies = await readCookies(container)
            // Cookie reads may complete after dismissal or a region change. Do not send that old session.
            guard runID == run, !container.closed, !Task.isCancelled else { return }
            let credential = try StepFunSession.credential(cookies: cookies, site: selectedSite, accountID: accountID, now: Date())
            try await query(accountID, credential)
            guard runID == run, !container.closed, !Task.isCancelled else { return }
            completed = true
            onCredential(credential)
            close()
        } catch {
            guard runID == run, !container.closed, !Task.isCancelled else { return }
            let failure = error as? RefreshFailure
            message = failure == .invalidCredential
                ? L10n.text("未读取到有效会话及匹配的设备标识，请完成登录后重试。")
                : failure?.displayName ?? L10n.text("无法验证套餐，请检查网络后重试。")
        }
    }
}

private struct StepFunWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
