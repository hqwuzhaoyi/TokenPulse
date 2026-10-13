import CoreFoundation
import Foundation

struct Sub2APIProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            let base = try GatewayCredentials.base(credential, provider: .sub2api)
            let data = try await GatewayQuotaSupport.data("v1/usage", base: base, credential: credential, transport: transport)
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = GatewayCredentials.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Reply: Decodable {
        struct Quota: Decodable { let limit: GatewayAmount?; let used: GatewayAmount?; let remaining: GatewayAmount?; let unit: String? }
        struct Subscription: Decodable {
            let daily_usage_usd: GatewayAmount?; let daily_limit_usd: GatewayAmount?
            let weekly_usage_usd: GatewayAmount?; let weekly_limit_usd: GatewayAmount?
            let monthly_usage_usd: GatewayAmount?; let monthly_limit_usd: GatewayAmount?
            let expires_at: String?
        }
        struct Rate: Decodable { let window: String; let limit: GatewayAmount?; let used: GatewayAmount?; let remaining: GatewayAmount?; let reset_at: String? }
        let isValid: Bool?
        let planName: String?
        let balance: GatewayAmount?
        let remaining: GatewayAmount?
        let unit: String?
        let quota: Quota?
        let subscription: Subscription?
        let rate_limits: [Rate]?
        let expires_at: String?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let root = try ProviderHTTP.json(data)
        if let valid = root["isValid"] as? NSNumber, CFGetTypeID(valid) == CFBooleanGetTypeID(), !valid.boolValue {
            throw RefreshFailure.invalidCredential
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let expiry = try GatewayQuotaSupport.date(reply.expires_at)
        var windows: [QuotaWindow] = []
        var ids: Set<String> = []
        for rate in reply.rate_limits ?? [] {
            let label = rate.window.lowercased()
            guard let seconds = seconds(label) else { continue }
            let id = "sub2api.rate.\(label)"
            guard ids.insert(id).inserted else { throw RefreshFailure.unreadableResponse }
            if let window = try budget(id: id, name: label + " 限流额度", scope: "限流", used: rate.used?.value, total: rate.limit?.value,
                                       remaining: rate.remaining?.value, unit: reply.unit ?? "USD",
                                       period: QuotaPeriod(seconds: seconds), reset: GatewayQuotaSupport.date(rate.reset_at), expiry: expiry) { windows.append(window) }
        }
        if let quota = reply.quota,
           let window = try budget(id: "sub2api.quota", name: "分组配额", scope: nil, used: quota.used?.value, total: quota.limit?.value,
                                   remaining: quota.remaining?.value, unit: quota.unit ?? reply.unit ?? "USD", period: .other,
                                   reset: nil, expiry: expiry) { windows.append(window) }
        if let subscription = reply.subscription {
            let subscriptionExpiry = try GatewayQuotaSupport.date(subscription.expires_at)
            let periods: [(String, QuotaPeriod, Decimal?, Decimal?)] = [
                ("每日", .other, subscription.daily_usage_usd?.value, subscription.daily_limit_usd?.value),
                ("每周", .weekly, subscription.weekly_usage_usd?.value, subscription.weekly_limit_usd?.value),
                ("每月", .monthly, subscription.monthly_usage_usd?.value, subscription.monthly_limit_usd?.value)
            ]
            for (label, period, used, total) in periods {
                if let window = try budget(id: "sub2api.subscription.\(label)", name: label + "预算", scope: "分组订阅",
                                           used: used, total: total, remaining: nil, unit: "USD", period: period,
                                           reset: nil, expiry: subscriptionExpiry ?? expiry) { windows.append(window) }
            }
        }
        let walletAmount = reply.balance?.value ?? ((reply.quota == nil && reply.subscription == nil) ? reply.remaining?.value : nil)
        if let amount = walletAmount {
            let unit = (reply.unit ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !unit.isEmpty else { throw RefreshFailure.unreadableResponse }
            let monetary = Locale.commonISOCurrencyCodes.contains(unit.uppercased())
            let displayedUnit = monetary ? unit.uppercased() : unit
            windows.append(QuotaWindow(id: "sub2api.balance", name: monetary ? "API 钱包余额" : "可用 \(displayedUnit)", scope: nil,
                                       usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: displayedUnit,
                                       expiresAt: expiry, wallet: WalletBalance(currency: displayedUnit, total: amount, isMonetary: monetary)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: reply.planName)
    }

    static func seconds(_ label: String) -> Int? {
        guard let unit = label.last, let number = Int(label.dropLast()), number > 0 else { return nil }
        let factor: Int = unit == "h" ? 3600 : unit == "d" ? 86400 : 0
        let value = number.multipliedReportingOverflow(by: factor)
        return factor > 0 && !value.overflow ? value.partialValue : nil
    }

    private static func budget(id: String, name: String, scope: String?, used: Decimal?, total: Decimal?, remaining: Decimal?, unit: String,
                               period: QuotaPeriod, reset: Date?, expiry: Date?) throws -> QuotaWindow? {
        guard total.map({ $0 >= 0 }) ?? true else { throw RefreshFailure.unreadableResponse }
        guard let total, total > 0 else { return nil }
        guard used.map({ $0 >= 0 }) ?? true else { throw RefreshFailure.unreadableResponse }
        return QuotaWindow(id: id, name: name, scope: scope, period: period,
                           isExhausted: remaining.map { $0 <= 0 }, usedPercentage: try GatewayQuotaSupport.percentage(used: used, total: total),
                           remainingCount: nil, totalCount: nil, resetsAt: reset, unit: unit, expiresAt: expiry,
                           exactCounts: DecimalQuotaCounts(used: used, remaining: remaining, total: total),
                           resetSemantics: id == "sub2api.quota" ? .nonResettingAllowance : nil)
    }
}
