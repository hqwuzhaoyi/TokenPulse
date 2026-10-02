import Foundation
import CoreFoundation

/// Known subscription frames only. Budget allowances are not API wallet balances.
struct ChutesProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .chutes, credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.chutes.ai/users/me/subscription_usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return .init(snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let root = try ProviderHTTP.json(data)
        let body: [String: Any]
        if let wrapper = root["data"] ?? root["result"] {
            guard let object = wrapper as? [String: Any] else { throw RefreshFailure.unreadableResponse }
            body = object
        } else { body = root }
        var windows: [QuotaWindow] = []
        var planName: String?
        if let subscribed = boolean(body["subscription"]) {
            guard subscribed else { throw RefreshFailure.subscriptionRequired }
            // Decode original bytes for Decimal quantities, before Foundation
            // dictionaries can introduce binary floating-point rounding.
            guard let reply = try? JSONDecoder().decode(PrimaryReply.self, from: data) else { throw RefreshFailure.unreadableResponse }
            if let payload = reply.four_hour,
               let window = primaryWindow(payload, id: "fourHour", name: "4 小时固定额度", period: .other) { windows.append(window) }
            if let payload = reply.monthly,
               let window = primaryWindow(payload, id: "monthly", name: "账期额度", period: .monthly) { windows.append(window) }
        } else if let subscription = body["subscription"] as? [String: Any] {
            // Compatibility is limited to the explicit pinned Pulse fixture.
            // Do not infer a percentage scale or search nested objects for quota.
            if boolean(subscription["active"]) == false ||
                (subscription["status"] as? String).map({ ["free", "inactive", "canceled", "cancelled", "expired", "none"].contains($0.lowercased()) }) == true {
                throw RefreshFailure.subscriptionRequired
            }
            planName = (subscription["plan_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let payload = body["rolling_window"] as? [String: Any],
               let seconds = statedSeconds(payload),
               let window = window(payload, id: "rolling", name: "滚动额度（\(durationName(seconds))）", period: QuotaPeriod(seconds: seconds),
                                   unit: payload["unit"] as? String, primary: false) { windows.append(window) }
            if let payload = body["monthly"] as? [String: Any],
               let window = window(payload, id: "monthly", name: "账期额度", period: .monthly,
                                   unit: payload["unit"] as? String, primary: false) { windows.append(window) }
        } else { throw RefreshFailure.unreadableResponse }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
                     providerPlanName: planName?.isEmpty == false ? planName : nil)
    }

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { value = try ProviderDecimal.amount(text) }
            else { value = try container.decode(Decimal.self) }
            guard !value.isNaN, value >= 0 else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct PrimaryWindow: Decodable {
        let usage: Amount?
        let cap: Amount?
        let remaining: Amount?
        let uncapped: Bool?
        let reset: Date?
        private enum CodingKeys: String, CodingKey { case usage, cap, remaining, uncapped, reset_at }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usage = try container.decodeIfPresent(Amount.self, forKey: .usage)
            cap = try container.decodeIfPresent(Amount.self, forKey: .cap)
            remaining = try container.decodeIfPresent(Amount.self, forKey: .remaining)
            uncapped = try container.decodeIfPresent(Bool.self, forKey: .uncapped)
            reset = (try? container.decode(String.self, forKey: .reset_at)).flatMap(ProviderHTTP.isoDate)
        }
    }
    private struct PrimaryReply: Decodable {
        let four_hour: PrimaryWindow?
        let monthly: PrimaryWindow?
        private enum CodingKeys: String, CodingKey { case subscription, four_hour, monthly, data, result }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.data) { self = try container.decode(Self.self, forKey: .data); return }
            if container.contains(.result) { self = try container.decode(Self.self, forKey: .result); return }
            guard try container.decode(Bool.self, forKey: .subscription) else { throw RefreshFailure.subscriptionRequired }
            four_hour = try container.decodeIfPresent(PrimaryWindow.self, forKey: .four_hour)
            monthly = try container.decodeIfPresent(PrimaryWindow.self, forKey: .monthly)
        }
    }
    private static func primaryWindow(_ payload: PrimaryWindow, id: String, name: String, period: QuotaPeriod) -> QuotaWindow? {
        if payload.uncapped == true {
            return .init(id: "chutes.\(id)", name: name, scope: nil, period: period,
                         isUnlimited: true, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "USD 预算")
        }
        if payload.cap?.value == 0 { return nil }
        let total = payload.cap?.value
        let remaining = payload.remaining?.value
        let reportedUsed = payload.usage?.value
        guard total != nil || remaining != nil || reportedUsed != nil else { return nil }
        let used = reportedUsed ?? total.flatMap { total in remaining.map { max(total - $0, 0) } }
        let left = remaining ?? total.flatMap { total in used.map { max(total - $0, 0) } }
        let exact = total.flatMap { total in used.flatMap { used in left.map { DecimalQuotaCounts(used: used, remaining: $0, total: total) } } }
        let percentage = exact.map { NSDecimalNumber(decimal: $0.used / $0.total * 100).doubleValue }.flatMap { $0.isFinite ? $0 : nil }
        return .init(id: "chutes.\(id)", name: name, scope: nil, period: period,
                     isExhausted: exact.map { $0.used >= $0.total }, usedPercentage: percentage,
                     remainingCount: left.map { NSDecimalNumber(decimal: $0).doubleValue },
                     totalCount: total.map { NSDecimalNumber(decimal: $0).doubleValue },
                     resetsAt: payload.reset, unit: "USD 预算", exactCounts: exact)
    }

    private static func window(_ payload: [String: Any], id: String, name: String, period: QuotaPeriod,
                               unit: String?, primary: Bool) -> QuotaWindow? {
        if boolean(payload["uncapped"]) == true {
            return .init(id: "chutes.\(id)", name: name, scope: nil, period: period,
                         isUnlimited: true, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: unit)
        }
        let limitKey = primary ? "cap" : "limit"
        let reportedLimit = nonnegative(payload[limitKey])
        // An explicitly zero allowance does not turn into a full green quota.
        if reportedLimit == 0 { return nil }
        let total = reportedLimit.flatMap { $0 > 0 ? $0 : nil }
        let used = nonnegative(payload[primary ? "usage" : "used"])
            ?? (primary ? nil : nonnegative(payload["requests"]))
        let remaining = nonnegative(payload["remaining"])
        let percent = primary ? nil : nonnegative(payload["percent_used"])
        guard used != nil || remaining != nil || total != nil || percent != nil else { return nil }
        let percentage: Double?
        if let total, let used { percentage = used / total * 100 }
        else if let total, let remaining { percentage = max(total - remaining, 0) / total * 100 }
        else { percentage = percent }
        let validPercentage = percentage.flatMap { $0.isFinite ? $0 : nil }
        let left = remaining ?? total.flatMap { total in used.map { max(total - $0, 0) } }
        return .init(id: "chutes.\(id)", name: name, scope: nil, period: period,
                     isExhausted: validPercentage.map { $0 >= 100 }, usedPercentage: validPercentage,
                     remainingCount: left, totalCount: total,
                     resetsAt: date(payload["reset_at"] ?? payload["resets_at"]), unit: unit)
    }

    private static func statedSeconds(_ payload: [String: Any]) -> Int? {
        for (key, multiplier) in [("window_seconds", 1.0), ("window_minutes", 60.0), ("window_hours", 3600.0)] {
            if payload[key] != nil {
                guard let value = nonnegative(payload[key]), value > 0,
                      let seconds = Int(exactly: value * multiplier), seconds > 0, seconds <= Int(Int32.max) else { return nil }
                return seconds
            }
        }
        return nil
    }
    private static func durationName(_ seconds: Int) -> String {
        if seconds % 3600 == 0 { return "\(seconds / 3600) 小时" }
        if seconds % 60 == 0 { return "\(seconds / 60) 分钟" }
        return "\(seconds) 秒"
    }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        guard let value = ProviderHTTP.number(value), value.isFinite else { return nil }
        return value
    }
    private static func nonnegative(_ value: Any?) -> Double? { number(value).flatMap { $0 >= 0 ? $0 : nil } }
    private static func date(_ value: Any?) -> Date? {
        if let iso = ProviderHTTP.isoDate(value) { return iso }
        // Numeric reset fields are not part of the verified backend contract.
        // Leave an unknown representation missing rather than guess its unit.
        return nil
    }
}
