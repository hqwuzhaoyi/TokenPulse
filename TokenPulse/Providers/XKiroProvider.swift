import Foundation

struct XKiroProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .xKiro, credential.kind == .apiKey,
              credential.metadata["sourceCredentialFingerprint"] == credential.apiKeySourceFingerprint else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.xkiro.com/v1/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.apiKeySourceFingerprint
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Money: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            guard text.range(of: #"\A-?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
                  text.filter({ $0.isNumber }).count <= 38,
                  let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { throw RefreshFailure.unreadableResponse }
            self.value = value
        }
    }
    private struct Reply: Decodable {
        struct Window: Decodable {
            let kind: String?
            let window_sec: Int?
            let spent_usd: Money?
            let cap_usd: Money?
            let remaining_usd: Money?
            let resets_in_sec: Double?
        }
        struct Free: Decodable {
            let used_today: Double?
            let limit_per_day: Double?
            let remaining: Double?
            let limitIsUnlimited: Bool
            private enum CodingKeys: String, CodingKey { case used_today, limit_per_day, remaining }
            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                used_today = try values.decodeIfPresent(Double.self, forKey: .used_today)
                limit_per_day = try values.decodeIfPresent(Double.self, forKey: .limit_per_day)
                remaining = try values.decodeIfPresent(Double.self, forKey: .remaining)
                limitIsUnlimited = try values.contains(.limit_per_day) && values.decodeNil(forKey: .limit_per_day)
            }
        }
        struct Wallet: Decodable { let balance_usd: Money? }
        let object: String
        let plan: String?
        let windows: [Window]?
        let free_tokens: Free?
        let wallet: Wallet?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.object == "usage" else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        var seen: Set<String> = []
        for slot in reply.windows ?? [] {
            guard [slot.spent_usd?.value, slot.cap_usd?.value, slot.remaining_usd?.value].compactMap({ $0 }).allSatisfy({ $0 >= 0 }),
                  slot.resets_in_sec.map({ $0.isFinite && $0 >= 0 }) != false else { throw RefreshFailure.unreadableResponse }
            guard let seconds = slot.window_sec, seconds >= 3600, seconds % 3600 == 0,
                  let spent = slot.spent_usd?.value, let cap = slot.cap_usd?.value, cap > 0 else { continue }
            let used = NSDecimalNumber(decimal: spent / cap * 100).doubleValue
            guard used.isFinite, slot.remaining_usd.map({ $0.value <= cap }) != false,
                  slot.resets_in_sec.map({ $0 <= Double(seconds) }) != false else { throw RefreshFailure.unreadableResponse }
            let id = "xkiro.\(slot.kind ?? String(seconds))"
            guard seen.insert(id).inserted else { throw RefreshFailure.unreadableResponse }
            windows.append(QuotaWindow(id: id, name: ProviderHTTP.windowName(seconds: seconds), scope: nil,
                period: QuotaPeriod(seconds: seconds), isExhausted: spent >= cap, usedPercentage: used,
                remainingCount: slot.remaining_usd.map { NSDecimalNumber(decimal: $0.value).doubleValue },
                totalCount: NSDecimalNumber(decimal: cap).doubleValue,
                resetsAt: slot.resets_in_sec.map { collectedAt.addingTimeInterval($0) }, unit: "USD 预算额度"))
        }
        if let free = reply.free_tokens {
            guard [free.used_today, free.limit_per_day, free.remaining].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 && $0.rounded() == $0 && $0 <= 9_007_199_254_740_991 }) else { throw RefreshFailure.unreadableResponse }
            if free.limitIsUnlimited {
                windows.append(QuotaWindow(id: "xkiro.free_tokens", name: "每日免费 tokens", scope: nil, period: .other,
                    isUnlimited: true, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "tokens"))
            } else if let limit = free.limit_per_day, limit > 0 {
                windows.append(QuotaWindow(id: "xkiro.free_tokens", name: "每日免费 tokens", scope: nil, period: .other,
                    isExhausted: free.remaining.map { $0 == 0 }, usedPercentage: free.used_today.map { $0 / limit * 100 },
                    remainingCount: free.remaining, totalCount: limit, resetsAt: nextMidnightUTC(after: collectedAt), unit: "tokens"))
            }
        }
        if let balance = reply.wallet?.balance_usd?.value {
            windows.append(QuotaWindow(id: "xkiro.wallet", name: "API 钱包余额", scope: nil,
                usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: WalletBalance(currency: "USD", total: balance)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        let plan = reply.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
            providerPlanName: plan?.isEmpty == false ? plan?.capitalized : nil,
            walletCollectedAt: windows.contains(where: { $0.wallet != nil }) ? collectedAt : nil)
    }

    static func nextMidnightUTC(after date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
    }
}
