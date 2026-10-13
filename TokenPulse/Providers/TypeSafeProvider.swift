import Foundation

actor TypeSafeActionCache {
    static let shared = TypeSafeActionCache()
    private var action: String?
    private var observedAt: Date?
    func current(at now: Date) -> String? {
        guard let observedAt, now >= observedAt, now.timeIntervalSince(observedAt) < 12 * 3600 else { return nil }
        return action
    }
    func remember(_ id: String?, at now: Date) { action = id; observedAt = id == nil ? nil : now }
}

enum TypeSafeSession {
    static let origin = "https://console.typesafe.ai"
    static let page = URL(string: origin + "/settings/billing")!
    static let policy = CookieWebSessionPolicy(domains: ["console.typesafe.ai", "typesafe.ai"], path: "/settings/billing",
        includeAllNames: true, deniedPrefixes: ["_ga", "_gid", "_gat"])
    static var profile: WebProviderLoginProfile {
        .init(loginURL: page, allowedOrigins: [origin]) { cookies, _, id, now in
            let credential = try WebProviderSession.cookieCredential(cookies: cookies, policy: policy,
                provider: .typeSafe, origin: origin, accountID: id, now: now)
            return [.init(id: id.uuidString, title: "TypeSafe", credential: try credential.encoded())]
        }
    }
}

struct TypeSafeProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    var cache: TypeSafeActionCache = .shared

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try WebProviderSession.validate(credential, provider: .typeSafe, accountID: accountID, origins: [TypeSafeSession.origin], now: now())
            _ = try TypeSafeSession.policy.values(in: credential.accessToken)
            let action: String
            if let cached = await cache.current(at: now()) { action = cached }
            else {
                action = try await discover(cookie: credential.accessToken)
                await cache.remember(action, at: now())
            }
            var reply = try await wire(Self.post(action: action, cookie: credential.accessToken))
            if reply.1.value(forHTTPHeaderField: "x-nextjs-action-not-found") == "1" {
                await cache.remember(nil, at: now())
                let fresh = try await discover(cookie: credential.accessToken)
                await cache.remember(fresh, at: now())
                reply = try await wire(Self.post(action: fresh, cookie: credential.accessToken))
            }
            try Self.accept(reply.1)
            var snapshot = try Self.snapshot(reply.0, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    private static func request(url: URL, cookie: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        return request
    }
    private static func post(action: String, cookie: String) -> URLRequest {
        var request = request(url: TypeSafeSession.page, cookie: cookie)
        request.httpMethod = "POST"; request.httpBody = Data("[]".utf8)
        request.setValue(TypeSafeSession.origin, forHTTPHeaderField: "Origin")
        request.setValue(TypeSafeSession.page.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(action, forHTTPHeaderField: "Next-Action")
        request.setValue("text/x-component", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func wire(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == "https", response.url?.host == "console.typesafe.ai",
              response.url?.port == nil || response.url?.port == 443 else { throw RefreshFailure.invalidCredential }
        guard data.count <= 2_097_152 else { throw RefreshFailure.unreadableResponse }
        return (data, response)
    }
    private static func accept(_ response: HTTPURLResponse) throws {
        if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
    }
    private func discover(cookie: String) async throws -> String {
        var page = Self.request(url: TypeSafeSession.page, cookie: cookie)
        page.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await wire(page)
        try Self.accept(response)
        let html = String(decoding: data, as: UTF8.self)
        if Self.isLoginLanding(html) { throw RefreshFailure.invalidCredential }
        for chunk in Self.chunkURLs(html) {
            var request = Self.request(url: chunk)
            request.timeoutInterval = 5
            do {
                let (data, response) = try await wire(request)
                if response.statusCode == 429 { throw RefreshFailure.rateLimited }
                if response.statusCode >= 500 { throw RefreshFailure.server }
                guard (200..<300).contains(response.statusCode) else { continue }
                if let action = Self.actionID(String(decoding: data, as: UTF8.self)) { return action }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if let failure = error as? RefreshFailure, failure == .rateLimited || failure == .server { throw failure }
                // A missing public chunk need not block searching the next listed chunk.
            }
        }
        throw RefreshFailure.unreadableResponse
    }
    static func isLoginLanding(_ body: String) -> Bool {
        body.range(of: #"\\?"\(auth\)\\?",\{\\?"children\\?":\[\\?"login\\?""#, options: .regularExpression) != nil
    }
    static func chunkURLs(_ html: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>"#, options: [.caseInsensitive]) else { return [] }
        var urls: [URL] = []
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard urls.count < 60 else { break }
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let raw = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: raw, relativeTo: TypeSafeSession.page)?.absoluteURL,
                  url.scheme == "https", url.host == "console.typesafe.ai", url.user == nil, url.password == nil,
                  url.port == nil || url.port == 443, url.path.lowercased().hasSuffix(".js"), !urls.contains(url) else { continue }
            urls.append(url)
        }
        return urls
    }
    static func actionID(_ script: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #""([0-9a-f]{40,128})"[^)]{0,150}"getBillingOverviewResult""#, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: script, range: NSRange(script.startIndex..., in: script))
        let ids = Set(matches.compactMap { Range($0.range(at: 1), in: script).map { String(script[$0]) } })
        return ids.count == 1 ? ids.first : nil
    }
    private struct Root: Decodable { let a: String }
    private struct Result: Decodable {
        struct DataBody: Decodable { let billing: Billing }
        struct Billing: Decodable { let balance: WalletNumericDecimal; let currency: String?; let plan: String? }
        let ok: Bool
        let data: DataBody?
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard data.count <= 2_097_152, let body = String(data: data, encoding: .utf8) else { throw RefreshFailure.unreadableResponse }
        if isLoginLanding(body) { throw RefreshFailure.invalidCredential }
        let lines = body.split(whereSeparator: \.isNewline)
        guard lines.count <= 256 else { throw RefreshFailure.unreadableResponse }
        var frames: [String: Data] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let id = String(line[..<colon])
            guard id.range(of: #"\A[0-9a-fA-F]+\z"#, options: .regularExpression) != nil else { continue }
            guard frames[id] == nil else { throw RefreshFailure.unreadableResponse }
            frames[id] = Data(line[line.index(after: colon)...].utf8)
        }
        guard let rootData = frames["0"], let root = try? JSONDecoder().decode(Root.self, from: rootData), root.a.hasPrefix("$@"),
              let resultData = frames[String(root.a.dropFirst(2))] else { throw RefreshFailure.unreadableResponse }
        let result = try KeyQuotaRequest.decode(Result.self, from: resultData)
        guard result.ok else { throw RefreshFailure.server }
        guard let billing = result.data?.billing else { throw RefreshFailure.unreadableResponse }
        let code = billing.currency?.uppercased()
        let monetary = code.map { Locale.commonISOCurrencyCodes.contains($0) } ?? false
        let wallet = WalletBalance(currency: monetary ? code! : "credits（币种未提供）", total: billing.balance.amount, isMonetary: monetary)
        let plan = billing.plan.map { raw in
            raw == "free_plan" ? "Free" : raw.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.capitalized }.joined(separator: " ")
        }
        return .init(accountID: accountID, windows: [WalletExpansionHTTP.walletWindow(id: "typesafe.balance", wallet: wallet)],
            collectedAt: collectedAt, providerPlanName: plan)
    }
}
