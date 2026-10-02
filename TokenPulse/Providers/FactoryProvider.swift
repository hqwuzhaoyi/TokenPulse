import CoreFoundation
import Foundation

/// Public Key configuration; private Factory web billing contracts pinned to Pulse 397c8fc4.
struct FactoryProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .factory, credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        func fetch(_ url: URL) async throws -> [String: Any] {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            for (name, value) in ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json",
                                  "x-factory-client": "web-app", "Origin": "https://app.factory.ai", "Referer": "https://app.factory.ai/"] {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            guard response.url?.host == "api.factory.ai", response.url?.scheme == "https" else { throw RefreshFailure.server }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return try ProviderHTTP.json(data)
        }
        do {
            let me = try await fetch(URL(string: "https://api.factory.ai/api/app/auth/me")!)
            let profile = me["userProfile"] as? [String: Any]
            let userID = (profile?["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subscription = ((me["organization"] as? [String: Any])?["subscription"] as? [String: Any])
            let orb = (subscription?["orbSubscription"] as? [String: Any])?["plan"] as? [String: Any]
            let plan = [orb?["name"] as? String, (subscription?["factoryTier"] as? String)?.capitalized]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            let limits: [String: Any]?
            do { limits = try await fetch(URL(string: "https://api.factory.ai/api/billing/limits")!) }
            catch is CancellationError { throw CancellationError() }
            catch { limits = nil } // The reference explicitly falls back when this route fails.
            let date = now()
            let windows: [QuotaWindow]
            if let limits, let current = try Self.currentWindows(limits, now: date) {
                windows = current // A selected new billing response must never mix in old Premium.
            } else {
                var url = URLComponents(string: "https://api.factory.ai/api/organization/subscription/usage")!
                url.queryItems = [.init(name: "useCache", value: "true")]
                if let userID, !userID.isEmpty { url.queryItems?.append(.init(name: "userId", value: userID)) }
                windows = try Self.legacyWindows(await fetch(url.url!), now: date)
            }
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: date,
                                                 providerPlanName: plan), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    /// nil means old billing; [] means new billing selected but no valid issued windows.
    static func currentWindows(_ root: [String: Any], now: Date) throws -> [QuotaWindow]? {
        let enabled = try flag(root["usesTokenRateLimitsBilling"])
        guard enabled == true, root["limits"] != nil else { return nil }
        guard let pools = root["limits"] as? [String: Any] else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        for (key, scope) in [("standard", "Standard"), ("core", "Core")] {
            guard let raw = pools[key] else { continue }
            guard let pool = raw as? [String: Any] else { throw RefreshFailure.unreadableResponse }
            var selected: [QuotaWindow] = []
            for (name, period, label) in [("fiveHour", QuotaPeriod.fiveHour, "5 小时额度"), ("weekly", .weekly, "每周额度"), ("monthly", .monthly, "每月额度")] {
                guard let rawWindow = pool[name] else { continue }
                guard let entry = rawWindow as? [String: Any] else { throw RefreshFailure.unreadableResponse }
                let percent = try number(entry["usedPercent"])
                let seconds = try number(entry["secondsRemaining"])
                let end = try date(entry["windowEnd"])
                let reset: Date?
                if let seconds, seconds > 0 {
                    let value = now.timeIntervalSince1970 + seconds
                    guard validEpoch(value) else { throw RefreshFailure.unreadableResponse }
                    reset = Date(timeIntervalSince1970: value)
                } else { reset = end.flatMap { $0 > now ? $0 : nil } }
                guard let percent else { continue }
                guard percent >= 0 else { throw RefreshFailure.unreadableResponse }
                if reset == nil, end != nil { continue } // An expired window is not fresh zero usage.
                selected.append(QuotaWindow(id: "factory.rate.\(key).\(name)", name: label, scope: scope, period: period,
                    isExhausted: percent >= 100, usedPercentage: min(percent, 100), remainingCount: nil,
                    totalCount: nil, resetsAt: reset))
            }
            if key == "standard" || selected.contains(where: { ($0.usedPercentage ?? 0) > 0 || $0.resetsAt != nil }) { windows += selected }
        }
        let balance = try number(root["extraUsageBalanceCents"])
        let allowed = try flag(root["extraUsageAllowed"])
        if let balance {
            guard balance >= 0, balance.rounded() == balance, Int64(exactly: balance) != nil else { throw RefreshFailure.unreadableResponse }
            if balance > 0 || allowed == true {
                // The response does not name a currency. Do not infer USD or a spendable API wallet.
                windows.append(QuotaWindow(id: "factory.extraUsage", name: "附加用量余额", scope: nil,
                    usedPercentage: nil, remainingCount: balance, totalCount: nil, resetsAt: nil,
                    unit: "cents（币种未提供）"))
            }
        }
        return windows
    }

    static func legacyWindows(_ root: [String: Any], now: Date) throws -> [QuotaWindow] {
        guard let usage = root["usage"] as? [String: Any] else { throw RefreshFailure.unreadableResponse }
        let end = try date(usage["endDate"])
        _ = try date(usage["startDate"])
        if let end, end <= now { return [] }
        return try [("standard", "Standard"), ("premium", "Premium")].compactMap { key, scope in
            guard let raw = usage[key] else { return nil }
            guard let tokens = raw as? [String: Any] else { throw RefreshFailure.unreadableResponse }
            let used = try number(tokens["userTokens"])
            let total = try number(tokens["totalAllowance"])
            let ratio = try number(tokens["usedRatio"])
            guard used.map({ $0 >= 0 }) != false, total.map({ $0 >= 0 }) != false else { throw RefreshFailure.unreadableResponse }
            if let total, total > 1e12 {
                return QuotaWindow(id: "factory.legacy.\(key)", name: "每月额度", scope: scope, period: .monthly,
                    isUnlimited: true, usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "tokens")
            }
            let allowance = total.flatMap { $0 > 0 ? $0 : nil }
            var fraction: Double?
            if let ratio, ratio >= -0.001, ratio <= 1.001,
               !(ratio <= 0 && ((used ?? 0) > 0 && allowance != nil || allowance == nil)) { fraction = min(max(ratio, 0), 1) }
            if fraction == nil, let used, let allowance {
                fraction = used / allowance
                guard fraction?.isFinite == true else { throw RefreshFailure.unreadableResponse }
            }
            guard let fraction else { return nil }
            let remaining = allowance.flatMap { total in used.map { max(0, total - $0) } }
            return QuotaWindow(id: "factory.legacy.\(key)", name: "每月额度", scope: scope, period: .monthly,
                isExhausted: fraction >= 1, usedPercentage: min(fraction * 100, 100), remainingCount: remaining,
                totalCount: allowance, resetsAt: end, unit: allowance != nil ? "tokens" : nil)
        }
    }

    private static func flag(_ raw: Any?) throws -> Bool? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw RefreshFailure.unreadableResponse }
        return value.boolValue
    }
    private static func number(_ raw: Any?) throws -> Double? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID(), let value = ProviderHTTP.number(raw), value.isFinite else { throw RefreshFailure.unreadableResponse }
        return value
    }
    private static func validEpoch(_ seconds: Double) -> Bool {
        seconds.isFinite && seconds > 0 && Int64(exactly: (seconds * 1000).rounded()) != nil
    }
    private static func date(_ raw: Any?) throws -> Date? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let date = ProviderHTTP.isoDate(raw) { return date }
        guard let number = try number(raw) else { throw RefreshFailure.unreadableResponse }
        if number == 0 { return nil }
        guard number > 0 else { throw RefreshFailure.unreadableResponse }
        let seconds = number > 1e12 ? number / 1000 : number
        guard validEpoch(seconds) else { throw RefreshFailure.unreadableResponse }
        return Date(timeIntervalSince1970: seconds)
    }
}
