import Foundation

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
