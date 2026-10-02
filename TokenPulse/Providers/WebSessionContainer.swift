import Foundation
import CryptoKit

struct WebSessionCookieSelection {
    let header: String
    let expiresByName: [String: Date]
}

/// Shared browser extraction: explicit domains, endpoint paths, expiry and cookie names.
enum WebSessionCookiePolicy {
    static func select(_ cookies: [HTTPCookie], names: [String], requiredNames: Set<String>,
                       requiredAnyNames: Set<String> = [], domains: Set<String>, path: String,
                       now: Date) throws -> WebSessionCookieSelection {
        var values: [String: String] = [:]
        var expiry: [String: Date] = [:]
        for cookie in cookies where names.contains(cookie.name) {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            guard domains.contains(domain), cookie.expiresDate.map({ $0 > now }) != false,
                  path == cookie.path || (path.hasPrefix(cookie.path) &&
                    (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/"))) else { continue }
            guard !cookie.value.isEmpty, cookie.value.utf8.count <= 32_768,
                  cookie.value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
                  !cookie.value.contains("\""), !cookie.value.contains("\\"),
                  !cookie.value.contains(";"), !cookie.value.contains(","),
                  values[cookie.name] == nil || values[cookie.name] == cookie.value else {
                throw RefreshFailure.invalidCredential
            }
            values[cookie.name] = cookie.value
            if let date = cookie.expiresDate {
                expiry[cookie.name] = expiry[cookie.name].map { min($0, date) } ?? date
            }
        }
        guard requiredNames.isSubset(of: Set(values.keys)),
              requiredAnyNames.isEmpty || !requiredAnyNames.isDisjoint(with: Set(values.keys)) else {
            throw RefreshFailure.invalidCredential
        }
        let header = names.compactMap { name in values[name].map { "\(name)=\($0)" } }.joined(separator: "; ")
        guard header.utf8.count <= 32_768 else { throw RefreshFailure.invalidCredential }
        return .init(header: header, expiresByName: expiry)
    }
}

#if os(iOS)
import WebKit

struct WebSessionScope: Equatable {
    let provider: Provider
    let accountID: UUID
    let host: String
}

/// Each login attempt owns a separate ephemeral store. No Safari or other account cookies are read.
@MainActor
final class WebSessionContainer {
    let scope: WebSessionScope
    let webView: WKWebView
    private(set) var closed = false

    init(scope: WebSessionScope) {
        self.scope = scope
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

    func close() {
        guard !closed else { return }
        closed = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                         modifiedSince: .distantPast) {}
    }
}
#endif

/// Cookie rules are provider-owned; selection never reads the user's normal browser.
struct CookieWebSessionPolicy: Sendable {
    let domains: Set<String>
    let path: String
    var names: [String] = []
    var prefixes: [String] = []
    var includeAllNames = false
    var deniedPrefixes: [String] = []
    var requiredNames: Set<String> = []
    var requiredAnyNames: Set<String> = []

    func select(_ cookies: [HTTPCookie], now: Date) throws -> WebSessionCookieSelection {
        let scoped = cookies.filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return domains.contains(domain) && (includeAllNames || names.contains(cookie.name) || prefixes.contains { cookie.name.hasPrefix($0) })
                && !deniedPrefixes.contains { cookie.name.hasPrefix($0) }
        }
        let selectedNames = Array(Set(scoped.map(\.name))).sorted()
        guard !selectedNames.isEmpty, selectedNames.allSatisfy(Self.validName) else { throw RefreshFailure.invalidCredential }
        return try WebSessionCookiePolicy.select(scoped, names: selectedNames, requiredNames: requiredNames,
            requiredAnyNames: requiredAnyNames, domains: domains, path: path, now: now)
    }

    func values(in header: String) throws -> [String: String] {
        guard !header.isEmpty, header.utf8.count <= 32_768 else { throw RefreshFailure.invalidCredential }
        var values: [String: String] = [:]
        for item in header.split(separator: ";", omittingEmptySubsequences: false) {
            let parts = item.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw RefreshFailure.invalidCredential }
            let name = String(parts[0]), value = String(parts[1])
            guard Self.validName(name), values[name] == nil,
                  (includeAllNames || names.contains(name) || prefixes.contains { name.hasPrefix($0) }),
                  !deniedPrefixes.contains(where: { name.hasPrefix($0) }),
                  !value.isEmpty, value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
                  !value.contains("\""), !value.contains("\\"), !value.contains(",") else { throw RefreshFailure.invalidCredential }
            values[name] = value
        }
        guard requiredNames.isSubset(of: Set(values.keys)),
              requiredAnyNames.isEmpty || !requiredAnyNames.isDisjoint(with: Set(values.keys)) else { throw RefreshFailure.invalidCredential }
        return values
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 256 && name.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || Array("!#$%&'*+-.^_`|~".utf8).contains($0)
        }
    }
}

/// Common account binding for provider-specific web credentials and workspace scopes.
enum WebProviderSession {
    static func credential(provider: Provider, origin: String, accountID: UUID, accessToken: String,
                           expiresAt: Date? = nil, remoteAccountID: String? = nil,
                           metadata: [String: String] = [:]) throws -> ProviderCredentialEnvelope {
        var metadata = metadata
        metadata["origin"] = origin
        metadata["localAccountID"] = accountID.uuidString
        metadata["webSessionFormat"] = "v1"
        var envelope = ProviderCredentialEnvelope(provider: provider, kind: .session, accessToken: accessToken,
            expiresAt: expiresAt, accountID: remoteAccountID, metadata: metadata)
        envelope.metadata["sourceCredentialFingerprint"] = try fingerprint(envelope)
        return envelope
    }

    static func cookieCredential(cookies: [HTTPCookie], policy: CookieWebSessionPolicy,
                                 provider: Provider, origin: String, accountID: UUID, now: Date,
                                 metadata: [String: String] = [:]) throws -> ProviderCredentialEnvelope {
        let selection = try policy.select(cookies, now: now)
        return try credential(provider: provider, origin: origin, accountID: accountID, accessToken: selection.header,
            expiresAt: selection.expiresByName.values.min(), metadata: metadata)
    }

    static func fingerprint(_ envelope: ProviderCredentialEnvelope) throws -> String {
        guard envelope.kind == .session, envelope.metadata["webSessionFormat"] == "v1",
              let account = envelope.metadata["localAccountID"], UUID(uuidString: account) != nil,
              let origin = envelope.metadata["origin"], let url = URL(string: origin), url.scheme == "https",
              let host = url.host, origin == "https://" + host.lowercased(),
              !envelope.accessToken.isEmpty, envelope.accessToken.utf8.count <= 65_536,
              envelope.accessToken.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else {
            throw RefreshFailure.invalidCredential
        }
        let metadata = envelope.metadata.filter { $0.key != "sourceCredentialFingerprint" }
            .sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }
        let data = try JSONEncoder().encode([envelope.provider.rawValue, envelope.accessToken, envelope.accountID ?? ""] + metadata)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(_ envelope: ProviderCredentialEnvelope, provider: Provider, accountID: UUID,
                         origins: Set<String>, now: Date) throws {
        guard envelope.provider == provider, envelope.metadata["localAccountID"] == accountID.uuidString,
              origins.contains(envelope.metadata["origin"] ?? ""),
              envelope.expiresAt.map({ $0 > now }) != false,
              try fingerprint(envelope) == envelope.metadata["sourceCredentialFingerprint"] else {
            throw RefreshFailure.invalidCredential
        }
    }
}

struct WebLoginCredentialChoice: Identifiable, Sendable {
    let id: String
    let title: String
    let credential: String
}

struct WebProviderLoginProfile: Sendable {
    let loginURL: URL
    let allowedOrigins: Set<String>
    var storageKeys: [String] = []
    var storagePrefixes: [String] = []
    var sessionStorageKeys: [String] = []
    let makeCredentials: @Sendable ([HTTPCookie], [String: String], UUID, Date) async throws -> [WebLoginCredentialChoice]

    func permits(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host, url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return allowedOrigins.contains("https://\(host.lowercased())")
    }
}

extension Provider {
    var webLoginProfile: WebProviderLoginProfile? {
        switch self {
        case .replicate: ReplicateProviderClient.loginProfile
        case .mistral: MistralProviderClient.loginProfile
        case .sakana: SakanaProviderClient.loginProfile
        default: nil
        }
    }
}

#if os(iOS)
import SwiftUI

struct WebProviderSessionLoginView: View {
    @StateObject private var model: WebProviderSessionLoginModel
    init(provider: Provider, profile: WebProviderLoginProfile, accountID: UUID, onCredential: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: WebProviderSessionLoginModel(provider: provider, profile: profile,
            accountID: accountID, onCredential: onCredential))
    }
    var body: some View {
        VStack(spacing: 10) {
            if let view = model.container?.webView { ProviderSessionBrowser(webView: view) }
            if !model.choices.isEmpty {
                Text("选择要添加的工作区或组织").font(.headline)
                ScrollView {
                    ForEach(model.choices) { choice in
                        Button(choice.title) { model.choose(choice) }.disabled(model.verifying)
                    }
                }.frame(maxHeight: 160)
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            Button(model.verifying ? "正在验证" : "完成登录并验证") { model.beginVerification() }
                .buttonStyle(.borderedProminent).disabled(model.verifying)
            Button("清除会话并重新登录") { model.start() }.disabled(model.verifying)
            Text("登录完成后验证额度，再保存此账号的会话。会话过期时可重新登录。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
        .task { model.start() }
        .onDisappear { model.close() }
    }
}

@MainActor
final class WebProviderSessionLoginModel: ObservableObject {
    @Published private(set) var container: WebSessionContainer?
    @Published private(set) var choices: [WebLoginCredentialChoice] = []
    @Published private(set) var message: String?
    @Published private(set) var verifying = false
    private let provider: Provider
    private let profile: WebProviderLoginProfile
    private let accountID: UUID
    private let onCredential: (String) -> Void
    private var runID = UUID()
    private var task: Task<Void, Never>?

    init(provider: Provider, profile: WebProviderLoginProfile, accountID: UUID, onCredential: @escaping (String) -> Void) {
        self.provider = provider; self.profile = profile; self.accountID = accountID; self.onCredential = onCredential
    }
    func start() {
        close(); message = nil
        let container = WebSessionContainer(scope: .init(provider: provider, accountID: accountID, host: profile.loginURL.host ?? ""))
        self.container = container
        container.webView.load(URLRequest(url: profile.loginURL))
    }
    func close() {
        runID = UUID(); task?.cancel(); task = nil; verifying = false; choices = []
        container?.close(); container = nil
    }
    func beginVerification() {
        guard task == nil, let container, !container.closed else { return }
        let run = runID
        choices = []; verifying = true; message = nil
        task = Task { @MainActor in
            defer { if runID == run { verifying = false; task = nil } }
            do {
                guard profile.permits(container.webView.url) else { throw RefreshFailure.invalidCredential }
                let cookies = await withCheckedContinuation { continuation in
                    container.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
                }
                guard active(run, container) else { return }
                let storage = try await readStorage(container)
                guard active(run, container) else { return }
                let candidates = try await profile.makeCredentials(cookies, storage, accountID, Date())
                guard active(run, container), !candidates.isEmpty,
                      Set(candidates.map(\.id)).count == candidates.count else { throw RefreshFailure.invalidCredential }
                if candidates.count == 1 { try await validate(candidates[0], run: run, container: container) }
                else { choices = candidates }
            } catch { if active(run, container) { message = (error as? RefreshFailure)?.displayName ?? "无法验证登录，请完成登录后重试。" } }
        }
    }
    func choose(_ choice: WebLoginCredentialChoice) {
        guard task == nil, choices.contains(where: { $0.id == choice.id }), let container, !container.closed else { return }
        let run = runID; verifying = true; message = nil
        task = Task { @MainActor in
            defer { if runID == run { verifying = false; task = nil } }
            do { try await validate(choice, run: run, container: container) }
            catch { if active(run, container) { message = (error as? RefreshFailure)?.displayName ?? "无法验证所选账号，请重试。" } }
        }
    }
    private func active(_ run: UUID, _ container: WebSessionContainer) -> Bool {
        runID == run && !container.closed && !Task.isCancelled
    }
    private func validate(_ choice: WebLoginCredentialChoice, run: UUID, container: WebSessionContainer) async throws {
        guard active(run, container) else { return }
        let result = try await ProviderQuotaClient(provider: provider).quotaResult(for: accountID, credential: choice.credential)
        guard active(run, container) else { return }
        onCredential(result.updatedCredential ?? choice.credential)
        close()
    }
    private func readStorage(_ container: WebSessionContainer) async throws -> [String: String] {
        guard profile.permits(container.webView.url) else { throw RefreshFailure.invalidCredential }
        if profile.storageKeys.isEmpty && profile.storagePrefixes.isEmpty && profile.sessionStorageKeys.isEmpty { return [:] }
        let data = try JSONEncoder().encode(["origins": Array(profile.allowedOrigins), "keys": profile.storageKeys,
            "prefixes": profile.storagePrefixes, "sessionKeys": profile.sessionStorageKeys])
        guard let configuration = String(data: data, encoding: .utf8) else { throw RefreshFailure.invalidCredential }
        let script = """
        (() => { const c = \(configuration); if (!c.origins.includes(location.origin)) return null;
          const out = {}; for (const k of Object.keys(localStorage)) {
            if (c.keys.includes(k) || c.prefixes.some(p => k.startsWith(p))) out[k] = localStorage.getItem(k);
          }
          for (const k of c.sessionKeys) { const v = sessionStorage.getItem(k); if (v !== null) out['session:' + k] = v; }
          return JSON.stringify({origin:location.origin, values:out}); })()
        """
        let object = try await container.webView.evaluateJavaScript(script)
        guard profile.permits(container.webView.url), let text = object as? String, text.utf8.count <= 262_144,
              let data = text.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let origin = root["origin"] as? String, profile.allowedOrigins.contains(origin),
              let values = root["values"] as? [String: String], values.count <= 128 else { throw RefreshFailure.invalidCredential }
        return values
    }
}

private struct ProviderSessionBrowser: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
