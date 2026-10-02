import Foundation

struct SakanaProviderClient: Sendable {
    static let origin = "https://console.sakana.ai"
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["console.sakana.ai", "sakana.ai"], path: "/billing",
        includeAllNames: true, deniedPrefixes: ["_ga", "_gid", "_gat", "_fbp", "_clck", "_clsk", "amplitude", "mp_",
                                              "__Host-authjs.csrf-token", "__Secure-authjs.callback-url", "authjs.csrf-token", "authjs.callback-url"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    static var loginProfile: WebProviderLoginProfile {
        WebProviderLoginProfile(loginURL: URL(string: origin + "/login")!, allowedOrigins: [origin, "https://accounts.google.com"],
            makeCredentials: { cookies, _, accountID, now in
                let session = try WebProviderSession.cookieCredential(cookies: cookies, policy: cookiePolicy, provider: .sakana,
                    origin: origin, accountID: accountID, now: now)
                try validateCookies(session.accessToken)
                return [WebLoginCredentialChoice(id: "sakana", title: "Sakana AI", credential: try session.encoded())]
            })
    }

    static func validateCookies(_ header: String) throws {
        let values = try cookiePolicy.values(in: header)
        // Framework families are discovered from actual captured names; a single guessed exact cookie is not imported.
        let bases = Set(values.keys.compactMap { key -> String? in
            guard let marker = key.range(of: "authjs.session-token"), marker.upperBound == key.endIndex || key[marker.upperBound] == "." else { return nil }
            return String(key[..<marker.upperBound])
        })
        guard bases.count == 1, let base = bases.first else { throw RefreshFailure.invalidCredential }
        let chunks = values.keys.filter { $0.hasPrefix(base + ".") }
        if values[base] != nil {
            guard chunks.isEmpty else { throw RefreshFailure.invalidCredential }
            return
        }
        let indices = chunks.compactMap { key -> Int? in
            let suffix = String(key.dropFirst(base.count + 1))
            guard let value = Int(suffix), String(value) == suffix, value >= 0 else { return nil }
            return value
        }.sorted()
        guard !indices.isEmpty, indices.count == chunks.count, indices == Array(0..<indices.count) else {
            throw RefreshFailure.invalidCredential
        }
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try WebProviderSession.validate(credential, provider: .sakana, accountID: accountID, origins: [Self.origin], now: now())
            try Self.validateCookies(credential.accessToken)
            let page = try await get(URL(string: Self.origin + "/billing")!, cookie: credential.accessToken)
            var balancePage: Data?
            var walletFailure: RefreshFailure?
            do { balancePage = try await get(URL(string: Self.origin + "/billing?tab=payAsYouGo")!, cookie: credential.accessToken) }
            catch {
                if error is CancellationError { throw error }
                walletFailure = ProviderHTTP.refreshFailure(error) as? RefreshFailure ?? .network
            }
            var snapshot = try SakanaProviderParser.snapshot(page: page, balancePage: balancePage, accountID: accountID, collectedAt: now())
            snapshot.walletFailure = walletFailure
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func get(_ url: URL, cookie: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == "https", response.url?.host == "console.sakana.ai" else { throw RefreshFailure.invalidCredential }
        if (300..<400).contains(response.statusCode) || response.url?.path == "/login" { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }
}

enum SakanaProviderParser {
    static func snapshot(page: Data, balancePage: Data?, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let html = String(data: page, encoding: .utf8), !html.isEmpty, html.utf8.count <= 2_000_000 else { throw RefreshFailure.unreadableResponse }
        let rendered = clean(html)
        var windows: [QuotaWindow] = []
        for (label, id, period) in [("5-hour", "sakana.five-hour", QuotaPeriod.fiveHour), ("Weekly", "sakana.weekly", .weekly)] {
            let pieces = sections(label: label, html: rendered)
            guard pieces.count == 1, let section = pieces.first,
                  let text = capture(#"<p\b[^>]*>\s*([0-9]+(?:\.[0-9]+)?)% used\s*</p>"#, section),
                  let percentage = Double(text), percentage.isFinite else { continue }
            let reset = capture(#"<p\b[^>]*>\s*Resets on ([^<]+?)\s*</p>"#, section).flatMap(resetDate)
            windows.append(QuotaWindow(id: id, name: period == .fiveHour ? "5 小时额度" : "每周额度", scope: nil, period: period,
                isExhausted: percentage >= 100, usedPercentage: percentage, remainingCount: nil, totalCount: nil, resetsAt: reset))
        }
        if let balancePage, let text = String(data: balancePage, encoding: .utf8), let wallet = try wallet(clean(text)) {
            windows.append(QuotaWindow(id: "sakana.balance.\(wallet.currency)", name: wallet.isMonetary ? "已标币种余额" : "服务 credits 余额（币种未提供）",
                scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: wallet))
        }
        guard !windows.isEmpty else { throw RefreshFailure.unreadableResponse }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
            providerPlanName: planName(rendered))
    }

    static func wallet(_ html: String) throws -> WalletBalance? {
        guard html.utf8.count <= 2_000_000 else { throw RefreshFailure.unreadableResponse }
        guard let block = capture(#"<h2\b[^>]*>\s*Credit balance\s*</h2>([\s\S]{0,900}?)(?:<h2\b|$)"#, html),
              let value = capture(#"<p\b[^>]*tabular-nums[^>]*>\s*([^<]+?)\s*</p>"#, block) else { return nil }
        let number = #"([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)"#
        if let amount = capture(#"^(?:USD\s*\$?|US\$)"# + number + #"$"#, value)
            ?? capture(#"^\$?"# + number + #"\s+USD$"#, value) {
            return WalletBalance(currency: "USD", total: try ProviderDecimal.amount(amount.replacingOccurrences(of: ",", with: "")))
        }
        if let amount = capture(#"^\$"# + number + #"$"#, value) {
            // Official console terms call these credits, not currency-equivalent funds. '$' alone does not prove ISO USD.
            return WalletBalance(currency: "$ credits", total: try ProviderDecimal.amount(amount.replacingOccurrences(of: ",", with: "")), isMonetary: false)
        }
        return nil
    }

    private static func clean(_ html: String) -> String {
        html.replacingOccurrences(of: #"<(script|style)\b[^>]*>[\s\S]*?</\1\s*>|<!--[\s\S]*?-->"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func sections(label: String, html: String) -> [String] {
        let labelPattern = #"<p\b[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*</p>"#
        guard let regex = try? NSRegularExpression(pattern: labelPattern, options: [.caseInsensitive]) else { return [] }
        let source = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let prefix = source.substring(to: match.range.location)
            // Only the billing Usage limit card, not arbitrary page text or scripts.
            guard let headings = try? NSRegularExpression(pattern: #"<div\b[^>]*data-slot=["']card-title["'][^>]*>([\s\S]*?)</div>"#, options: [.caseInsensitive]),
                  let last = headings.matches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)).last,
                  let titleRange = Range(last.range(at: 1), in: prefix),
                  inlineTitle(String(prefix[titleRange]))?.lowercased() == "usage limit" else { return nil }
            let rest = source.substring(from: match.range.location + match.range.length)
            let boundary = rest.range(of: #"<p\b[^>]*>\s*(?:5-hour|Weekly)\s*</p>|<div\b[^>]*data-slot=["']card(?:-title)?["'][^>]*>"#, options: [.regularExpression, .caseInsensitive])?.lowerBound ?? rest.endIndex
            let section = String(rest[..<boundary])
            return section.utf8.count <= 20_000 ? section : nil
        }
    }

    /// Only bounded inline span wrappers are normalized; block/hidden markup never expands the quota scope.
    private static func inlineTitle(_ html: String) -> String? {
        guard html.utf8.count <= 2_048,
              let tags = try? NSRegularExpression(pattern: #"<[^>]*>"#) else { return nil }
        var depth = 0
        for match in tags.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { return nil }
            let tag = String(html[range])
            if tag.range(of: #"\A</span\s*>\z"#, options: [.regularExpression, .caseInsensitive]) != nil {
                guard depth > 0 else { return nil }; depth -= 1
            } else {
                guard tag.range(of: #"\A<span\b[^>]*>\z"#, options: [.regularExpression, .caseInsensitive]) != nil,
                      !tag.hasSuffix("/>"),
                      tag.range(of: #"\s(?:hidden|aria-hidden|style)(?:\s|=|>)"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
                depth += 1; guard depth <= 4 else { return nil }
            }
        }
        guard depth == 0 else { return nil }
        let title = tags.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title.contains("<") || title.contains(">") ? nil : title
    }

    private static func planName(_ html: String) -> String? {
        guard let card = capture(#"<div\b[^>]*data-slot=["']card-title["'][^>]*>([\s\S]*?)</div>"#, html),
              inlineTitle(card) != nil,
              let firstSpan = capture(#"\A\s*<span\b[^>]*>([\s\S]*?)</span>"#, card),
              let name = inlineTitle(firstSpan), name.utf8.count <= 128,
              !["usage limit", "credit balance", "usage", "pricing"].contains(name.lowercased()),
              !name.contains("$"), !name.contains("%") else { return nil }
        return name
    }

    private static func resetDate(_ text: String) -> Date? {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "MMMM d, yyyy 'at' h:mm a"; format.isLenient = false
        guard let date = format.date(from: text) else { return nil }
        return format.string(from: date) == text ? date : nil
    }

    private static func capture(_ pattern: String, _ source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
