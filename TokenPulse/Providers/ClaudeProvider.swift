import Foundation
#if os(iOS)
import Combine
import SwiftUI
import WebKit
#endif

struct ClaudeProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .session,
              credential.metadata["cookieFormat"] == "restrictedHeader",
              let organizationID = credential.metadata["organizationID"],
              !organizationID.isEmpty else {
            throw RefreshFailure.invalidCredential
        }

        let endpoint = URL(string: "https://claude.ai/api/organizations")!
            .appending(path: organizationID)
            .appending(path: "usage")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        Self.applyWebHeaders(to: &request, cookieHeader: credential.accessToken)

        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            let windows = Self.windows(root)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(
                snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func applyWebHeaders(to request: inout URLRequest, cookieHeader: String) {
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                + "AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
    }

    static func windows(_ root: [String: Any]) -> [QuotaWindow] {
        var windows = (root["limits"] as? [[String: Any]] ?? []).compactMap { limit -> QuotaWindow? in
            guard let kind = limit["kind"] as? String else { return nil }
            let seconds: Int
            switch kind {
            case "session": seconds = 5 * 3_600
            case "weekly_all", "weekly_scoped": seconds = 7 * 86_400
            default: return nil
            }
            let scope = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
            let resetsAt = ProviderHTTP.isoDate(limit["resets_at"])
            return QuotaWindow(
                id: "claude.\(kind).\(scope ?? "all")",
                name: ProviderHTTP.windowName(seconds: seconds),
                scope: scope,
                period: QuotaPeriod(seconds: seconds),
                usedPercentage: ProviderHTTP.number(limit["percent"]),
                remainingCount: nil,
                totalCount: nil,
                resetsAt: resetsAt,
                cycleID: ProviderHTTP.cycleID(prefix: "claude.\(kind).\(scope ?? "all")", resetsAt: resetsAt)
            )
        }

        if windows.isEmpty {
            for (key, seconds) in [("five_hour", 5 * 3_600), ("seven_day", 7 * 86_400)] {
                guard let node = root[key] as? [String: Any] else { continue }
                let resetsAt = ProviderHTTP.isoDate(node["resets_at"])
                windows.append(QuotaWindow(
                    id: "claude.\(key)",
                    name: ProviderHTTP.windowName(seconds: seconds),
                    scope: nil,
                    period: QuotaPeriod(seconds: seconds),
                    usedPercentage: ProviderHTTP.number(node["utilization"]),
                    remainingCount: nil,
                    totalCount: nil,
                    resetsAt: resetsAt,
                    cycleID: ProviderHTTP.cycleID(prefix: "claude.\(key)", resetsAt: resetsAt)
                ))
            }
        }
        return windows
    }
}

#if os(iOS)
struct ClaudeOrganization: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

@MainActor
final class ClaudeSessionLoginModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var webView: WKWebView?
    @Published private(set) var organizations: [ClaudeOrganization] = []
    @Published private(set) var message: String?

    private var sessionHeader: String?
    private var sessionExpiresAt: Date?
    private let onCredential: (String) -> Void

    init(onCredential: @escaping (String) -> Void) {
        self.onCredential = onCredential
    }

    func start() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    func select(_ organization: ClaudeOrganization) {
        guard let sessionHeader else { return }
        do {
            let credential = try ProviderCredentialEnvelope(
                provider: .claude,
                kind: .session,
                accessToken: sessionHeader,
                expiresAt: sessionExpiresAt,
                metadata: ["cookieFormat": "restrictedHeader", "organizationID": organization.id]
            ).encoded()
            onCredential(credential)
        } catch {
            message = "无法保存 Claude 登录信息"
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            var names: Set<String> = []
            let sessionCookies = cookies.filter {
                ["sessionKey", "sessionKeyV3"].contains($0.name)
                    && ($0.domain == "claude.ai" || $0.domain == ".claude.ai")
                    && !$0.value.isEmpty
                    && names.insert($0.name).inserted
            }
            guard !sessionCookies.isEmpty else { return }
            let header = sessionCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            let expiresAt = sessionCookies.compactMap(\.expiresDate).min()
            Task { @MainActor in await self.loadOrganizations(cookieHeader: header, expiresAt: expiresAt) }
        }
    }

    private func loadOrganizations(cookieHeader: String, expiresAt: Date?) async {
        sessionHeader = cookieHeader
        sessionExpiresAt = expiresAt
        var request = URLRequest(url: URL(string: "https://claude.ai/api/bootstrap")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        ClaudeProviderClient.applyWebHeaders(to: &request, cookieHeader: cookieHeader)

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = root["account"] as? [String: Any],
                  let memberships = account["memberships"] as? [[String: Any]] else { return }
            organizations = memberships.compactMap { membership in
                guard let organization = membership["organization"] as? [String: Any],
                      let id = organization["uuid"] as? String else { return nil }
                let name = (organization["name"] as? String) ?? id
                return ClaudeOrganization(id: id, name: name)
            }
            message = organizations.isEmpty ? "登录成功，但未返回可选组织" : nil
        } catch is CancellationError {
            return
        } catch {
            message = "无法读取 Claude 组织，请稍后重试"
        }
    }
}

struct ClaudeSessionLoginView: View {
    @StateObject private var model: ClaudeSessionLoginModel

    init(onCredential: @escaping (String) -> Void) {
        _model = StateObject(wrappedValue: ClaudeSessionLoginModel(onCredential: onCredential))
    }

    var body: some View {
        VStack {
            if let webView = model.webView {
                ClaudeWebView(webView: webView)
                if !model.organizations.isEmpty {
                    Text("选择要监控的 Claude 组织").font(.headline)
                    ForEach(model.organizations) { organization in
                        Button(organization.name) { model.select(organization) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
            } else {
                Button("登录 Claude") { model.start() }
                    .buttonStyle(.borderedProminent)
                Text("登录仅发生在 TokenPulse 的临时浏览器中，不读取其他应用或 Safari 的 Cookie。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClaudeWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
