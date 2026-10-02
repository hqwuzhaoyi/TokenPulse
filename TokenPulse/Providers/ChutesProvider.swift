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
        } else if body["subscription"] is [String: Any] {
            // Only shape selection uses the dictionary. Decode every legacy
            // quantity from original JSON bytes, just like the primary path.
            let reply: LegacyReply
            do { reply = try JSONDecoder().decode(LegacyReply.self, from: data) }
            catch let failure as RefreshFailure { throw failure }
            catch { throw RefreshFailure.unreadableResponse }
            planName = reply.subscription.plan_name?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let payload = reply.rolling_window, let seconds = payload.seconds,
               let window = legacyWindow(payload, id: "rolling", name: "滚动额度（\(durationName(seconds))）", period: QuotaPeriod(seconds: seconds)) {
                windows.append(window)
            }
            if let payload = reply.monthly,
               let window = legacyWindow(payload, id: "monthly", name: "账期额度", period: .monthly) { windows.append(window) }
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
        let used = reportedUsed ?? total.flatMap { total in remaining.flatMap { exactDifference(total, $0) } }
        let left = remaining ?? total.flatMap { total in used.flatMap { exactDifference(total, $0) } }
        let exact = DecimalQuotaCounts(used: used, remaining: left, total: total)
        let percentage = total.flatMap { total in used.map { NSDecimalNumber(decimal: $0 / total * 100).doubleValue } }.flatMap { $0.isFinite ? $0 : nil }
        return .init(id: "chutes.\(id)", name: name, scope: nil, period: period,
                     isExhausted: total.flatMap { total in used.map { $0 >= total } }, usedPercentage: percentage,
                     remainingCount: left.map { NSDecimalNumber(decimal: $0).doubleValue },
                     totalCount: total.map { NSDecimalNumber(decimal: $0).doubleValue },
                     resetsAt: payload.reset, unit: "USD 预算", exactCounts: exact)
    }

    /// Preserve reported amounts when their derived difference is not exact.
    private static func exactDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        if rhs >= lhs { return 0 }
        var lhs = lhs, rhs = rhs, result = Decimal()
        guard NSDecimalSubtract(&result, &lhs, &rhs, .plain) == .noError, !result.isNaN else { return nil }
        // Foundation can return noError after aligning distant exponents and
        // dropping a tiny subtrahend. Recover it to verify the derived count.
        var recovered = Decimal()
        guard NSDecimalSubtract(&recovered, &lhs, &result, .plain) == .noError,
              recovered == rhs else { return nil }
        return result
    }

    private struct LegacyWindow: Decodable {
        let used: Amount?
        let total: Amount?
        let remaining: Amount?
        let percent: Amount?
        let uncapped: Bool?
        let unit: String?
        let reset: Date?
        let seconds: Int?
        private enum CodingKeys: String, CodingKey {
            case used, requests, limit, remaining, percent_used, uncapped, unit
            case reset_at, resets_at, window_seconds, window_minutes, window_hours
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            used = try c.decodeIfPresent(Amount.self, forKey: .used) ?? c.decodeIfPresent(Amount.self, forKey: .requests)
            total = try c.decodeIfPresent(Amount.self, forKey: .limit)
            remaining = try c.decodeIfPresent(Amount.self, forKey: .remaining)
            percent = try c.decodeIfPresent(Amount.self, forKey: .percent_used)
            uncapped = try? c.decodeIfPresent(Bool.self, forKey: .uncapped)
            unit = try? c.decodeIfPresent(String.self, forKey: .unit)
            let resetKey: CodingKeys = c.contains(.reset_at) ? .reset_at : .resets_at
            reset = (try? c.decode(String.self, forKey: resetKey)).flatMap(ProviderHTTP.isoDate)
            var duration: Int?
            for (key, multiplier) in [(CodingKeys.window_seconds, Decimal(1)), (.window_minutes, 60), (.window_hours, 3600)] {
                guard c.contains(key) else { continue }
                // Unknown/invalid stated duration omits only this rolling
                // window. It must not invalidate a readable monthly window.
                if let value = try? c.decode(Amount.self, forKey: key), value.value > 0 {
                    let scaled = NSDecimalNumber(decimal: value.value * multiplier).doubleValue
                    if let count = Int(exactly: scaled), count > 0, count <= Int(Int32.max) { duration = count }
                }
                break
            }
            seconds = duration
        }
    }
    private struct LegacyReply: Decodable {
        struct Subscription: Decodable {
            let active: Bool?
            let status: String?
            let plan_name: String?
            private enum CodingKeys: String, CodingKey { case active, status, plan_name }
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                active = try? c.decodeIfPresent(Bool.self, forKey: .active)
                status = try? c.decodeIfPresent(String.self, forKey: .status)
                plan_name = try? c.decodeIfPresent(String.self, forKey: .plan_name)
            }
        }
        let subscription: Subscription
        let rolling_window: LegacyWindow?
        let monthly: LegacyWindow?
        private enum CodingKeys: String, CodingKey { case data, result, subscription, rolling_window, monthly }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if c.contains(.data) { self = try c.decode(Self.self, forKey: .data); return }
            if c.contains(.result) { self = try c.decode(Self.self, forKey: .result); return }
            subscription = try c.decode(Subscription.self, forKey: .subscription)
            if subscription.active == false || subscription.status.map({ ["free", "inactive", "canceled", "cancelled", "expired", "none"].contains($0.lowercased()) }) == true {
                throw RefreshFailure.subscriptionRequired
            }
            rolling_window = try c.decodeIfPresent(LegacyWindow.self, forKey: .rolling_window)
            monthly = try c.decodeIfPresent(LegacyWindow.self, forKey: .monthly)
        }
    }
    private static func legacyWindow(_ payload: LegacyWindow, id: String, name: String, period: QuotaPeriod) -> QuotaWindow? {
        if payload.uncapped == true {
            return .init(id: "chutes.\(id)", name: name, scope: nil, period: period, isUnlimited: true,
                         usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: payload.unit)
        }
        let total = payload.total?.value
        if total == 0 { return nil }
        let remaining = payload.remaining?.value
        let reportedUsed = payload.used?.value
        let reportedPercent = payload.percent?.value
        guard total != nil || remaining != nil || reportedUsed != nil || reportedPercent != nil else { return nil }
        // Decimal itself can lose a tiny subtrahend. Use the existing inverse
        // check instead of treating a rounded difference as reported usage.
        let used = reportedUsed ?? total.flatMap { total in remaining.flatMap { exactDifference(total, $0) } }
        let left = remaining ?? total.flatMap { total in used.flatMap { exactDifference(total, $0) } }
        let percentage: Double?
        let exhausted: Bool?
        if let total, let used {
            let computed = NSDecimalNumber(decimal: used / total * 100).doubleValue
            percentage = computed.isFinite ? (used < total ? min(computed, Double(100).nextDown) : computed) : nil
            exhausted = used >= total
        } else if let reportedPercent, total == nil || remaining == nil {
            let value = NSDecimalNumber(decimal: reportedPercent).doubleValue
            percentage = value.isFinite ? value : nil
            exhausted = percentage.map { $0 >= 100 }
        } else { percentage = nil; exhausted = nil }
        let counts = total != nil || used != nil || left != nil ? DecimalQuotaCounts(used: used, remaining: left, total: total) : nil
        return .init(id: "chutes.\(id)", name: name, scope: nil, period: period,
                     isExhausted: exhausted, usedPercentage: percentage,
                     remainingCount: left.map { NSDecimalNumber(decimal: $0).doubleValue },
                     totalCount: total.map { NSDecimalNumber(decimal: $0).doubleValue },
                     resetsAt: payload.reset, unit: payload.unit, exactCounts: counts)
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
}
