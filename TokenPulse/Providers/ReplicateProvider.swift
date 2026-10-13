import Foundation

struct ReplicateProviderClient: Sendable {
    static let origin = "https://replicate.com"
    static let pageURL = URL(string: origin + "/account/billing")!
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["replicate.com"], path: "/",
                                                    names: ["sessionid", "csrftoken"], requiredNames: ["sessionid"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    static var loginProfile: WebProviderLoginProfile {
        WebProviderLoginProfile(loginURL: pageURL, allowedOrigins: [origin, "https://github.com"], makeCredentials: { cookies, _, accountID, now in
            let base = try WebProviderSession.cookieCredential(cookies: cookies, policy: cookiePolicy, provider: .replicate,
                                                               origin: origin, accountID: accountID, now: now)
            let client = ReplicateProviderClient(transport: URLSessionProviderTransport.rejectingRedirects(), now: { now })
            let page = try await client.get(pageURL, cookie: base.accessToken, accept: "text/html")
            let accounts = try ReplicateProviderParser.accounts(in: String(decoding: page, as: UTF8.self))
            return try accounts.map { account in
                let scoped = try WebProviderSession.credential(provider: .replicate, origin: origin, accountID: accountID,
                    accessToken: base.accessToken, expiresAt: base.expiresAt, remoteAccountID: account.id,
                    metadata: ["accountKind": account.kind, "accountUsername": account.username])
                let title = account.kind == "organization"
                    ? L10n.format("组织 · %@", account.username) : L10n.format("个人 · %@", account.username)
                return WebLoginCredentialChoice(id: account.id, title: title, credential: try scoped.encoded())
            }
        })
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try WebProviderSession.validate(credential, provider: .replicate, accountID: accountID, origins: [Self.origin], now: now())
            _ = try Self.cookiePolicy.values(in: credential.accessToken)
            let page = try await get(Self.pageURL, cookie: credential.accessToken, accept: "text/html")
            let accounts = try ReplicateProviderParser.accounts(in: String(decoding: page, as: UTF8.self))
            guard let selected = accounts.first(where: {
                $0.kind == credential.metadata["accountKind"] && $0.username == credential.metadata["accountUsername"]
                    && $0.id == credential.accountID
            }) else { throw RefreshFailure.invalidCredential }
            let data = try await get(selected.balanceURL, cookie: credential.accessToken, accept: "application/json")
            var snapshot = try ReplicateProviderParser.snapshot(data, accountID: accountID, collectedAt: now(), account: selected)
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func get(_ url: URL, cookie: String, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(cookie, forHTTPHeaderField: "Cookie"); request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == "https", response.url?.host == "replicate.com" else { throw RefreshFailure.invalidCredential }
        if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }
}

enum ReplicateProviderParser {
    struct Account: Equatable, Hashable, Sendable {
        let kind: String
        let username: String
        var id: String { "\(kind):\(username)" }
        var title: String { kind == "organization" ? "组织 · \(username)" : "个人 · \(username)" }
        var balanceURL: URL {
            // Restrict the server-reported username to one safe identifier/path segment.
            URL(string: "https://replicate.com/api/\(kind == "organization" ? "organizations" : "users")/\(username)/unused-credit")!
        }
    }

    static func accounts(in html: String) throws -> [Account] {
        guard html.utf8.count <= 2_000_000 else { throw RefreshFailure.unreadableResponse }
        let scripts = try NSRegularExpression(pattern: #"<script\b([^>]*)>([\s\S]*?)</script\s*>"#, options: [.caseInsensitive])
        let props = try NSRegularExpression(pattern: #"\bid\s*=\s*(["'])react-component-props[^"']*\1"#, options: [.caseInsensitive])
        let json = try NSRegularExpression(pattern: #"\btype\s*=\s*(["'])application/json\1"#, options: [.caseInsensitive])
        let text = html as NSString
        var found: Set<Account> = []
        var visited = 0
        for script in scripts.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let attributes = text.substring(with: script.range(at: 1))
            let range = NSRange(location: 0, length: (attributes as NSString).length)
            guard props.firstMatch(in: attributes, range: range) != nil,
                  json.firstMatch(in: attributes, range: range) != nil,
                  let payload = try? JSONSerialization.jsonObject(with: Data(text.substring(with: script.range(at: 2)).utf8)) else { continue }
            var queue: [Any] = [payload]
            var index = 0
            while index < queue.count, visited < 4_000 {
                let item = queue[index]; index += 1; visited += 1
                if let object = item as? [String: Any], let account = object["account"] as? [String: Any],
                   let kind = account["kind"] as? String, ["user", "organization"].contains(kind),
                   let username = account["username"] as? String,
                   username.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z"#, options: .regularExpression) != nil {
                    found.insert(Account(kind: kind, username: username))
                }
                let children = (item as? [Any]) ?? ((item as? [String: Any]).map { Array($0.values) } ?? [])
                queue.append(contentsOf: children.filter { $0 is [Any] || $0 is [String: Any] })
            }
            guard visited < 4_000 else { throw RefreshFailure.unreadableResponse }
        }
        guard !found.isEmpty else {
            if isLoginPage(html) { throw RefreshFailure.invalidCredential }
            throw RefreshFailure.unreadableResponse
        }
        return found.sorted { $0.id < $1.id }
    }

    static func isLoginPage(_ html: String) -> Bool {
        html.range(of: #"<title>\s*Sign in\s*\|\s*Replicate\s*</title>"#, options: [.regularExpression, .caseInsensitive]) != nil
        && html.range(of: #"<a\b[^>]*\bhref=["']/login/github/(?:\?[^"']*)?["']"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private struct Reply: Decodable {
        let unusedCredit: Decimal?
        private enum CodingKeys: String, CodingKey { case unusedCredit = "unused_credit" }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try values.decodeIfPresent(String.self, forKey: .unusedCredit) {
                unusedCredit = try ProviderDecimal.amount(text)
            } else { unusedCredit = nil }
        }
    }

    /// Decimal decode is performed directly from JSON bytes, never a Double bridge.
    static func balance(_ data: Data) throws -> Decimal {
        struct NumberReply: Decodable { let unused_credit: Decimal? }
        let amount: Decimal?
        if let numeric = try? JSONDecoder().decode(NumberReply.self, from: data) { amount = numeric.unused_credit }
        else if let textual = try? JSONDecoder().decode(Reply.self, from: data) { amount = textual.unusedCredit }
        else { throw RefreshFailure.unreadableResponse }
        guard let amount else { throw RefreshFailure.noQuotaWindows }
        guard !amount.isNaN, amount >= 0 else { throw RefreshFailure.unreadableResponse }
        return amount
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date, account: Account) throws -> QuotaSnapshot {
        QuotaSnapshot(accountID: accountID, windows: [
            QuotaWindow(id: "replicate.wallet.USD", name: "预付美元余额", scope: account.title,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: try balance(data)))
        ], collectedAt: collectedAt)
    }
}
