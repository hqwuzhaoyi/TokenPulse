import Foundation

struct MistralProviderClient: Sendable {
    static let origin = "https://admin.mistral.ai"
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["mistral.ai"], path: "/",
                                                    names: ["csrftoken"], prefixes: ["ory_session_"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    static var loginProfile: WebProviderLoginProfile {
        WebProviderLoginProfile(loginURL: URL(string: origin + "/subscription")!,
            allowedOrigins: [origin, "https://auth.mistral.ai", "https://console.mistral.ai", "https://accounts.google.com"],
            makeCredentials: { cookies, _, accountID, now in
                var session = try WebProviderSession.cookieCredential(cookies: cookies, policy: cookiePolicy, provider: .mistral,
                    origin: origin, accountID: accountID, now: now)
                let values = try validateCookies(session.accessToken)
                var metadata: [String: String] = [:]
                if values["csrftoken"] == nil {
                    let csrfPolicy = CookieWebSessionPolicy(domains: ["console.mistral.ai"], path: "/api-ui/trpc/billing.vibeUsage",
                                                           names: ["csrftoken"], requiredNames: ["csrftoken"])
                    if let selected = try? csrfPolicy.select(cookies, now: now),
                       let value = try? csrfPolicy.values(in: selected.header)["csrftoken"] {
                        metadata["consoleCSRF"] = value
                        if let expiry = selected.expiresByName["csrftoken"] { metadata["consoleCSRFExpiry"] = String(expiry.timeIntervalSince1970) }
                    }
                }
                session = try WebProviderSession.credential(provider: .mistral, origin: origin, accountID: accountID,
                    accessToken: session.accessToken, expiresAt: session.expiresAt, metadata: metadata)
                return [WebLoginCredentialChoice(id: "mistral", title: "Mistral API / Vibe", credential: try session.encoded())]
            })
    }

    static func validateCookies(_ header: String) throws -> [String: String] {
        let values = try cookiePolicy.values(in: header)
        guard values.keys.contains(where: { $0.hasPrefix("ory_session_") && $0.count > "ory_session_".count }) else {
            throw RefreshFailure.invalidCredential
        }
        return values
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try WebProviderSession.validate(credential, provider: .mistral, accountID: accountID, origins: [Self.origin], now: now())
            let values = try Self.validateCookies(credential.accessToken)
            var wallet: WalletBalance?
            var walletFailure: RefreshFailure?
            do {
                let data = try await get(URL(string: Self.origin + "/api/billing/credits")!, cookie: credential.accessToken, accept: "application/json")
                wallet = try MistralProviderParser.wallet(data)
                if wallet == nil { walletFailure = .unreadableResponse }
            } catch {
                if error is CancellationError { throw error }
                let failure = ProviderHTTP.refreshFailure(error) as? RefreshFailure ?? .network
                // A refused primary session cannot be replaced by unrelated page numbers.
                if failure == .invalidCredential { throw failure }
                walletFailure = failure
            }
            var budgets: [String: MistralProviderParser.Budget] = [:]
            do {
                let data = try await get(URL(string: Self.origin + "/subscription")!, cookie: credential.accessToken, accept: "text/html")
                budgets = try MistralProviderParser.subscription(String(decoding: data, as: UTF8.self))
            } catch { if error is CancellationError { throw error } }
            var csrf = values["csrftoken"]
            if csrf == nil, let value = credential.metadata["consoleCSRF"],
               credential.metadata["consoleCSRFExpiry"].flatMap(Double.init).map({ $0 > now().timeIntervalSince1970 }) ?? true {
                csrf = value
            }
            if budgets["vibe_budget"] == nil, let csrf,
               csrf.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }), !csrf.contains(";") {
                var components = URLComponents(string: "https://console.mistral.ai/api-ui/trpc/billing.vibeUsage")!
                components.queryItems = [URLQueryItem(name: "batch", value: "1"), URLQueryItem(name: "input", value: #"{"0":{"json":null,"meta":{"values":["undefined"],"v":1}}}"#)]
                let cookie = values["csrftoken"] == nil ? credential.accessToken + "; csrftoken=" + csrf : credential.accessToken
                do {
                    let data = try await get(components.url!, cookie: cookie, accept: "application/json", csrf: csrf)
                    if let vibe = try MistralProviderParser.vibe(data) { budgets["vibe_budget"] = vibe }
                } catch { if error is CancellationError { throw error } }
            }
            if wallet == nil, budgets.isEmpty, let walletFailure { throw walletFailure }
            var snapshot = try MistralProviderParser.snapshot(wallet: wallet, budgets: budgets, accountID: accountID, collectedAt: now())
            snapshot.walletFailure = walletFailure
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func get(_ url: URL, cookie: String, accept: String, csrf: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(cookie, forHTTPHeaderField: "Cookie"); request.setValue(accept, forHTTPHeaderField: "Accept")
        if let csrf { request.setValue(csrf, forHTTPHeaderField: "X-CSRFToken") }
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == "https", response.url?.host == url.host else { throw RefreshFailure.invalidCredential }
        if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }
}

enum MistralProviderParser {
    private struct Money: Decodable {
        let amount: Decimal
        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) { amount = try ProviderDecimal.amount(text) }
            else { amount = try value.decode(Decimal.self) }
            guard !amount.isNaN else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct Credits: Decodable {
        let wallet_amount: Money?
        let credit_notes_amount: Money?
        let ongoing_usage_balance: Money?
        let currency: String?
    }
    struct Budget: Decodable, Equatable, Sendable {
        let usage_percentage: Double?
        let reset_at: String?
        var windowReset: Date? {
            reset_at.flatMap { ProviderHTTP.isoDate($0.hasPrefix("$D") ? String($0.dropFirst(2)) : $0) }
        }
    }
    private struct Push: Decodable {
        let text: String
        init(from decoder: any Decoder) throws {
            var values = try decoder.unkeyedContainer()
            guard try values.decode(Int.self) == 1 else { throw RefreshFailure.unreadableResponse }
            text = try values.decode(String.self)
        }
    }

    static func wallet(_ data: Data) throws -> WalletBalance? {
        guard let reply = try? JSONDecoder().decode(Credits.self, from: data) else { throw RefreshFailure.unreadableResponse }
        // All reported components are needed for a net balance; absent is never zero.
        guard let wallet = reply.wallet_amount?.amount, let notes = reply.credit_notes_amount?.amount,
              let usage = reply.ongoing_usage_balance?.amount, let code = reply.currency?.uppercased(),
              code.range(of: #"\A[A-Z]{3}\z"#, options: .regularExpression) != nil else { return nil }
        let total = try exactArithmetic(try exactArithmetic(wallet, notes, subtract: false), usage, subtract: true)
        return WalletBalance(currency: code, total: total)
    }

    private static func exactArithmetic(_ lhs: Decimal, _ rhs: Decimal, subtract: Bool) throws -> Decimal {
        var left = lhs, right = rhs, result = Decimal()
        let status = subtract ? NSDecimalSubtract(&result, &left, &right, .plain) : NSDecimalAdd(&result, &left, &right, .plain)
        guard status == .noError, !result.isNaN else { throw RefreshFailure.unreadableResponse }
        // Foundation can report noError after absorbing a tiny operand. Verify both inverse identities.
        var inverseLeft = Decimal(), inverseRight = Decimal(), checkResult = result
        let first = subtract ? NSDecimalAdd(&inverseLeft, &checkResult, &right, .plain)
            : NSDecimalSubtract(&inverseLeft, &checkResult, &right, .plain)
        checkResult = result
        let second = subtract ? NSDecimalSubtract(&inverseRight, &left, &checkResult, .plain)
            : NSDecimalSubtract(&inverseRight, &checkResult, &left, .plain)
        guard first == .noError, second == .noError, inverseLeft == lhs, inverseRight == rhs else {
            throw RefreshFailure.unreadableResponse
        }
        return result
    }

    static func subscription(_ html: String) throws -> [String: Budget] {
        guard html.utf8.count <= 2_000_000 else { throw RefreshFailure.unreadableResponse }
        let marker = "self.__next_f.push("
        var cursor = html.startIndex, parts: [String] = []
        while let found = html.range(of: marker, range: cursor..<html.endIndex) {
            cursor = found.upperBound
            guard let arguments = pushArguments(html, from: cursor) else { continue }
            parts += arguments.parts
            cursor = arguments.end
        }
        let stream = parts.joined()
        var result: [String: Budget] = [:]
        for name in ["api_budget", "vibe_budget"] {
            var scan = stream.startIndex
            var objects: Set<Data> = []
            var budget: Budget?
            while let key = stream.range(of: "\"\(name)\":", range: scan..<stream.endIndex) {
                scan = key.upperBound
                guard let start = stream[scan...].firstIndex(where: { !$0.isWhitespace }), stream[start] == "{",
                      let end = containerEnd(stream, from: start) else { continue }
                let bytes = Data(stream[start..<end].utf8); scan = end
                guard let json = try? JSONSerialization.jsonObject(with: bytes),
                      let canonical = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { continue }
                objects.insert(canonical)
                if let value = try? JSONDecoder().decode(Budget.self, from: bytes),
                   let percent = value.usage_percentage, percent.isFinite, percent >= 0 { budget = value }
                if objects.count > 1 { budget = nil; break }
            }
            if objects.count == 1, let budget { result[name] = budget }
        }
        return result
    }

    /// Offline-compatible Array.push arguments only: complete comma-separated JSON arrays, never JS expressions.
    private static func pushArguments(_ html: String, from start: String.Index) -> (parts: [String], end: String.Index)? {
        var cursor = start, parts: [String] = []
        for _ in 0..<64 {
            guard let argument = html[cursor...].firstIndex(where: { !$0.isWhitespace }), html[argument] == "[",
                  let end = containerEnd(html, from: argument) else { return nil }
            let data = Data(html[argument..<end].utf8)
            guard (try? JSONSerialization.jsonObject(with: data)) is [Any] else { return nil }
            if let push = try? JSONDecoder().decode(Push.self, from: data) { parts.append(push.text) }
            guard let separator = html[end...].firstIndex(where: { !$0.isWhitespace }) else { return nil }
            if html[separator] == ")" { return (parts, html.index(after: separator)) }
            guard html[separator] == "," else { return nil }
            cursor = html.index(after: separator)
        }
        return nil
    }

    static func vibe(_ data: Data) throws -> Budget? {
        struct Reply: Decodable {
            struct Result: Decodable { struct Payload: Decodable { let json: Budget? }; let data: Payload? }
            let result: Result?
        }
        guard let values = try? JSONDecoder().decode([Reply].self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard let budget = values.first?.result?.data?.json, let percent = budget.usage_percentage,
              percent.isFinite, percent >= 0 else { return nil }
        return budget
    }

    static func snapshot(wallet: WalletBalance?, budgets: [String: Budget], accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        var windows: [QuotaWindow] = []
        for (key, id, scope) in [("api_budget", "mistral.api", "API"), ("vibe_budget", "mistral.vibe", "Vibe")] {
            guard let budget = budgets[key], let percent = budget.usage_percentage, percent.isFinite, percent >= 0 else { continue }
            windows.append(QuotaWindow(id: id, name: "账期额度", scope: scope, period: .monthly, isExhausted: percent >= 100,
                                       usedPercentage: percent, remainingCount: nil, totalCount: nil, resetsAt: budget.windowReset))
        }
        if let wallet {
            windows.append(QuotaWindow(id: "mistral.wallet.\(wallet.currency)", name: "可用钱包余额", scope: nil,
                                       usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: wallet))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }

    /// Balanced JSON extraction honors quoting and escapes, with bounded nesting.
    private static func containerEnd(_ text: String, from start: String.Index) -> String.Index? {
        var closing: [Character] = [], quoted = false, escaped = false, index = start
        while index < text.endIndex {
            let character = text[index]
            if quoted {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false }
            } else {
                switch character {
                case "\"": quoted = true
                case "[": closing.append("]")
                case "{": closing.append("}")
                case "]", "}":
                    guard closing.last == character else { return nil }
                    closing.removeLast()
                    if closing.isEmpty { return text.index(after: index) }
                default: break
                }
                if closing.count > 128 { return nil }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
