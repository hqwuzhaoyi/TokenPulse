import SwiftUI
import AuthenticationServices

struct GoogleNativeOAuthLoginView: View {
    let provider: Provider
    let accountID: UUID
    var requestedScopes: [String] = GoogleNativeOAuth.scopes
    let complete: @Sendable (URL, ProviderLoginSession, UUID, String?) async throws -> String
    let onCredential: (String) -> Void
    @StateObject private var model = GoogleNativeOAuthLoginModel()
    @State private var clientID = ""
    @State private var project = ""

    var body: some View {
        Form {
            Section("自己的 Google iOS OAuth Client") {
                TextField("Client ID（…apps.googleusercontent.com）", text: $clientID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Cloud 项目 ID（可选）", text: $project)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                Text("在 Google Cloud 注册 iOS OAuth client，Bundle ID 为 com.tokenpulse.app。需开启 Google 账户授权并授予页面列出的权限。使用自己的 client ID，无需 client secret。")
                Text("请先在 Google 官方服务中完成账户与 Code Assist 项目设置。留空项目时使用服务返回的已激活项目；TokenPulse 不会创建项目或自动开通服务。")
                Text("此接入不支持强制 App Check 或 DPoP 的 client 配置。服务可能拒绝第三方 client，将显示实际权限或支持错误。")
            }.font(.footnote)
            Section {
                if model.busy { ProgressView("正在授权并验证额度") }
                else {
                    Button("使用 Google 账户授权") {
                        model.start(provider: provider, accountID: accountID, clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines), project: project.trimmingCharacters(in: .whitespacesAndNewlines), scopes: requestedScopes, complete: complete, onCredential: onCredential)
                    }.disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = model.message { Text(error).foregroundStyle(.orange) }
            }
        }
        .onDisappear { model.cancel() }
    }
}

@MainActor
final class GoogleNativeOAuthLoginModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var browser: ASWebAuthenticationSession?
    private var task: Task<Void, Never>?
    private var runID: UUID?

    func start(provider: Provider, accountID: UUID, clientID: String, project: String, scopes: [String],
               complete: @escaping @Sendable (URL, ProviderLoginSession, UUID, String?) async throws -> String,
               onCredential: @escaping (String) -> Void) {
        cancel()
        message = nil
        let id = UUID(); runID = id
        do {
            let pending = try GoogleNativeOAuth(clientID: clientID, transport: URLSessionProviderTransport.rejectingRedirects(), now: Date.init, requestedScopes: scopes).begin(provider: provider)
            busy = true
            let session = ASWebAuthenticationSession(url: pending.authorizationURL, callbackURLScheme: pending.callbackURL?.scheme) { [weak self] callback, error in
                Task { @MainActor [weak self] in
                    guard let self, self.runID == id else { return }
                    self.browser = nil
                    guard let callback, error == nil else {
                        self.busy = false
                        self.message = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ? nil : "Google 授权未完成"
                        return
                    }
                    self.task = Task { @MainActor [weak self] in
                        do {
                            let encoded = try await complete(callback, pending, accountID, project.isEmpty ? nil : project)
                            try Task.checkCancellation()
                            guard let self, self.runID == id else { return }
                            self.busy = false; self.runID = nil
                            onCredential(encoded)
                        } catch {
                            guard let self, self.runID == id else { return }
                            self.busy = false
                            if error is CancellationError { return }
                            if case ProviderIntegrationError.unsupportedLogin(let reason) = error { self.message = reason }
                            else { self.message = (ProviderHTTP.refreshFailure(error) as? RefreshFailure)?.displayName ?? "Google 授权未完成" }
                        }
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browser = session
            if !session.start() { browser = nil; busy = false; message = "无法打开 Google 授权窗口" }
        } catch {
            busy = false
            if case ProviderIntegrationError.unsupportedLogin(let reason) = error { message = reason }
            else { message = "Google Client ID 格式无效" }
        }
    }

    func cancel() {
        runID = nil; task?.cancel(); task = nil; browser?.cancel(); browser = nil; busy = false
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
