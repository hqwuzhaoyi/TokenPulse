import CryptoKit
import Foundation

extension ProviderCredentialEnvelope {
    var apiKeySourceFingerprint: String? {
        guard kind == .apiKey, !accessToken.isEmpty,
              accessToken.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { return nil }
        return SHA256.hash(data: Data("\(provider.rawValue)\n\(accessToken)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct SyntheticProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .synthetic, credential.kind == .apiKey,
              let fingerprint = credential.apiKeySourceFingerprint,
              credential.metadata["sourceCredentialFingerprint"] == fingerprint else {
            throw RefreshFailure.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://api.synthetic.new/v2/quotas")!)
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

    private struct Slot: Decodable {
        let max: Double?
        let remaining: Double?
        let limited: Bool?
        let nextTickAt: String?
        let percentRemaining: Double?
        let maxCredits: String?
        let remainingCredits: String?
        let nextRegenAt: String?
        let limit: Double?
        let requests: Double?
        let renewsAt: String?
    }
    private struct Slots: Decodable {
        struct Search: Decodable { let hourly: Slot? }
        let rollingFiveHourLimit: Slot?
        let weeklyTokenLimit: Slot?
        let search: Search?
        let plan: String?
    }
    private struct Reply: Decodable {
        let rollingFiveHourLimit: Slot?
        let weeklyTokenLimit: Slot?
        let search: Slots.Search?
        let plan: String?
        let data: Slots?
        var slots: Slots {
            if rollingFiveHourLimit != nil || weeklyTokenLimit != nil || search?.hourly != nil {
                return Slots(rollingFiveHourLimit: rollingFiveHourLimit, weeklyTokenLimit: weeklyTokenLimit, search: search, plan: plan)
            }
            return data ?? Slots(rollingFiveHourLimit: nil, weeklyTokenLimit: nil, search: nil, plan: plan)
        }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let decoded = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let slots = decoded.slots
        var windows: [QuotaWindow] = []
        if let rolling = slots.rollingFiveHourLimit {
            try validate(rolling)
            if let max = rolling.max, max > 0, let remaining = rolling.remaining {
                windows.append(QuotaWindow(id: "synthetic.five_hour", name: "5 小时滚动额度", scope: nil, period: .fiveHour,
                    isExhausted: rolling.limited == true || remaining == 0, usedPercentage: Swift.max(0, (max - remaining) / max * 100),
                    remainingCount: remaining, totalCount: max, resetsAt: nil,
                    resetSemantics: .continuousReplenishment, nextReplenishmentAt: try date(rolling.nextTickAt)))
            }
        }
        if let weekly = slots.weeklyTokenLimit {
            try validate(weekly)
            let used: Double?
            if let left = weekly.percentRemaining { used = 100 - left }
            else if let total = try dollars(weekly.maxCredits), total > 0, let remaining = try dollars(weekly.remainingCredits) {
                used = Swift.max(0, (total - remaining) / total * 100)
            } else { used = nil }
            if let used {
                windows.append(QuotaWindow(id: "synthetic.weekly", name: "每周滚动额度", scope: nil, period: .weekly,
                    isExhausted: weekly.limited == true || used >= 100, usedPercentage: used,
                    remainingCount: nil, totalCount: nil, resetsAt: nil,
                    resetSemantics: .continuousReplenishment, nextReplenishmentAt: try date(weekly.nextRegenAt)))
            }
        }
        if let search = slots.search?.hourly {
            try validate(search)
            if let limit = search.limit, limit > 0, let used = search.requests {
                windows.append(QuotaWindow(id: "synthetic.search_hourly", name: "每小时额度", scope: "Search", period: .other,
                    isExhausted: search.limited == true || used >= limit, usedPercentage: used / limit * 100,
                    remainingCount: Swift.max(limit - used, 0), totalCount: limit, resetsAt: try date(search.renewsAt), unit: "次请求"))
            }
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        let plan = slots.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
                             providerPlanName: plan?.isEmpty == false ? plan : nil)
    }

    private static func validate(_ slot: Slot) throws {
        guard [slot.max, slot.remaining, slot.limit, slot.requests].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              slot.percentRemaining.map({ $0.isFinite && 0...100 ~= $0 }) != false else { throw RefreshFailure.unreadableResponse }
        _ = try date(slot.nextTickAt)
        _ = try date(slot.nextRegenAt)
        _ = try date(slot.renewsAt)
        _ = try dollars(slot.maxCredits)
        _ = try dollars(slot.remainingCredits)
    }
    private static func date(_ text: String?) throws -> Date? {
        guard let text else { return nil }
        guard let date = ProviderHTTP.isoDate(text) else { throw RefreshFailure.unreadableResponse }
        return date
    }
    private static func dollars(_ text: String?) throws -> Double? {
        guard let text else { return nil }
        let amount = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard let value = Double(amount), value.isFinite, value >= 0 else { throw RefreshFailure.unreadableResponse }
        return value
    }
}
