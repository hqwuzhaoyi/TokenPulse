import Foundation

/// Only the pinned CLI displayText forms are accepted; no guessed JSON or pricing tables.
struct AmpProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Result: Decodable { let displayText: String? }
        struct Failure: Decodable { let code: String? }
        let ok: Bool
        let result: Result?
        let error: Failure?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .amp, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://ampcode.com/api/internal?userDisplayBalanceInfo")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"method":"userDisplayBalanceInfo","params":{}}"#.utf8)
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return .init(snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard reply.ok else { throw reply.error?.code == "auth-required" ? RefreshFailure.invalidCredential : .server }
        guard let text = reply.result?.displayText, !text.isEmpty else { throw RefreshFailure.unreadableResponse }
        let cleaned = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
        let lines = cleaned.split(whereSeparator: \.isNewline).map(String.init)
        var windows: [QuotaWindow] = []
        var plan: String?
        if let free = lines.lazy.compactMap(freeDollars).first ?? lines.lazy.compactMap(freePercent).first {
            windows.append(free)
        }
        var balance: Decimal?
        for line in lines {
            if let tier = tier(line) { plan = plan ?? tier.plan; windows += tier.windows }
            else if let legacy = legacy(line) { plan = plan ?? legacy.plan; windows += legacy.windows }
            else if balance == nil, let match = match(#"^\s*Individual credits:\s*\$"# + number + #"\s+remaining\s*$"#, line) {
                balance = amount(match[0])
            }
        }
        var seen: Set<String> = []
        windows = windows.filter { seen.insert($0.id).inserted }
        if let balance {
            windows.append(QuotaWindow(id: "amp.wallet.USD", name: "个人美元余额", scope: nil,
                                       usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                       wallet: WalletBalance(currency: "USD", total: balance)))
        }
        guard !windows.isEmpty else {
            let lower = cleaned.lowercased()
            if !lower.contains("signed in as"), lower.contains("sign in") || lower.contains("log in") || lower.contains("login") {
                throw RefreshFailure.invalidCredential
            }
            throw RefreshFailure.unreadableResponse
        }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: plan)
    }

    // Commas are accepted only as conventional groups of exactly three digits.
    private static let number = #"((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?)"#

    private static func freeDollars(_ text: String) -> QuotaWindow? {
        guard let found = match(#"^\s*Amp Free:\s*\$"# + number + #"\s*/\s*\$"# + number + #"\s+remaining\s*\(replenishes\s+\+\$"# + number + #"/hour\)\s*$"#, text),
              let remaining = amount(found[0]), let total = amount(found[1]), amount(found[2]) != nil else { return nil }
        return allowance(id: "amp.free", name: "Amp Free · 逐小时补充", remaining: remaining, total: total,
                         period: nil, reset: nil, unit: "USD", continuous: true)
    }

    private static func freePercent(_ text: String) -> QuotaWindow? {
        guard let found = match(#"^\s*Amp Free:\s*"# + number + #"\s*%\s+remaining(?:\s+today(?:\s*\(resets daily\))?|\s*\(resets daily\))\s*$"#, text),
              let remaining = amount(found[0]), remaining <= 100 else { return nil }
        return allowance(id: "amp.free", name: "Amp Free · 每日额度", remaining: remaining, total: 100,
                         period: .other, reset: nil, unit: nil)
    }

    private static func tier(_ text: String) -> (plan: String, windows: [QuotaWindow])? {
        guard let found = match(#"^\s*Amp\s+(.+?)\s+Tier:\s*agent usage\s+\$"# + number + #"\s+of\s+\$"# + number + #"\s+remaining\b(.*)$"#, text) else { return nil }
        let remainder = found[3]
        let end = periodEnd(remainder)
        var windows: [QuotaWindow] = []
        if let remaining = amount(found[1]), let total = amount(found[2]),
           let agent = allowance(id: "amp.agent", name: "Agent 账期额度", remaining: remaining, total: total,
                                 period: .monthly, reset: end, unit: "USD") { windows.append(agent) }
        if let orb = match(#"\borb usage\s+"# + number + #"h\s+of\s+"# + number + #"h\s+a1\.small orb hours remaining\b"#, remainder),
           let remaining = amount(orb[0]), let total = amount(orb[1]),
           let window = allowance(id: "amp.orb", name: "Orb 账期额度", remaining: remaining, total: total,
                                  period: .monthly, reset: end, unit: "小时") { windows.append(window) }
        return (found[0], windows)
    }

    private static func legacy(_ text: String) -> (plan: String, windows: [QuotaWindow])? {
        let tail = #":\s*"# + number + #"\s*%\s+other usage and\s+"# + number + #"\s*%\s+orb usage remaining\b"#
        guard let found = match(#"^\s*Amp\s+(.+?)\s+Subscription"# + tail, text)
                ?? match(#"^\s*Subscription\s+(.+?)"# + tail, text) else { return nil }
        let windows: [QuotaWindow] = [("amp.agent", "Agent 账期额度", found[1]), ("amp.orb", "Orb 账期额度", found[2])].compactMap { id, name, value in
            guard let remaining = amount(value), remaining <= 100 else { return nil }
            // Legacy text provides percentages only, never a dollar or hour quantity.
            return allowance(id: id, name: name, remaining: remaining, total: 100, period: .monthly, reset: nil, unit: nil)
        }
        return (found[0], windows)
    }

    private static func allowance(id: String, name: String, remaining: Decimal, total: Decimal,
                                  period: QuotaPeriod?, reset: Date?, unit: String?, continuous: Bool = false) -> QuotaWindow? {
        guard remaining >= 0, total > 0 else { return nil }
        let percentage = NSDecimalNumber(decimal: max(0, total - remaining) / total * 100).doubleValue
        let remainder = NSDecimalNumber(decimal: remaining).doubleValue
        let limit = NSDecimalNumber(decimal: total).doubleValue
        guard percentage.isFinite, remainder.isFinite, limit.isFinite else { return nil }
        return QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: remaining == 0,
                           usedPercentage: percentage, remainingCount: unit == nil ? nil : remainder,
                           totalCount: unit == nil ? nil : limit, resetsAt: reset, unit: unit,
                           resetSemantics: continuous ? .continuousReplenishment : nil,
                           resetDatePrecision: reset != nil ? .day : nil,
                           exactCounts: unit == nil ? nil : DecimalQuotaCounts(used: max(0, total - remaining), remaining: remaining, total: total))
    }

    private static func periodEnd(_ text: String) -> Date? {
        guard let found = match(#"\bperiod\s+(\d{4}-\d{2}-\d{2})\s+to\s+(\d{4}-\d{2}-\d{2})\b"#, text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let start = formatter.date(from: found[0]), let end = formatter.date(from: found[1]),
              formatter.string(from: start) == found[0], formatter.string(from: end) == found[1], end > start else { return nil }
        return end
    }

    private static func amount(_ text: String) -> Decimal? { try? ProviderDecimal.amount(text.replacingOccurrences(of: ",", with: "")) }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        }
    }
}
