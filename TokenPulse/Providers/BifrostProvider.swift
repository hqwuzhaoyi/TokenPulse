import Foundation

struct BifrostProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            let base = try GatewayCredentials.base(credential, provider: .bifrost)
            let data = try await GatewayQuotaSupport.data("api/governance/virtual-keys/quota", base: base, credential: credential,
                                                         transport: transport, header: "x-bf-vk")
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = GatewayCredentials.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Budget: Decodable {
        let id: String
        let max_limit: GatewayAmount?
        let current_usage: GatewayAmount?
        let reset_duration: String?
        let last_reset: String?
        let override_amount: GatewayAmount?
        let override_mode: String?
        let override_cycles_remaining: Int?
        let source_name: String?
    }
    private struct Scoped: Decodable { let provider: String?; let model_name: String?; let budgets: [Budget]? }
    private struct Reply: Decodable {
        let virtual_key_name: String?
        let is_active: Bool?
        let budgets: [Budget]?
        let provider_configs: [Scoped]?
        let model_configs: [Scoped]?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.is_active != nil || reply.budgets != nil || reply.provider_configs != nil || reply.model_configs != nil else {
            throw RefreshFailure.unreadableResponse
        }
        if reply.is_active == false {
            let inactive = QuotaWindow(id: "bifrost.inactive", name: "虚拟 Key 已停用", scope: nil,
                                       usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil)
            return QuotaSnapshot(accountID: accountID, windows: [inactive], collectedAt: collectedAt, providerPlanName: reply.virtual_key_name)
        }
        var scoped: [(String, [String], Budget)] = []
        for budget in reply.budgets ?? [] { scoped.append(("虚拟 Key" + (budget.source_name.map { " · \($0)" } ?? ""), ["key"], budget)) }
        for config in reply.provider_configs ?? [] {
            guard let provider = config.provider, !provider.isEmpty else { throw RefreshFailure.unreadableResponse }
            for budget in config.budgets ?? [] { scoped.append(("提供商 · " + provider, ["provider", provider], budget)) }
        }
        for config in reply.model_configs ?? [] {
            guard let provider = config.provider, !provider.isEmpty, let model = config.model_name, !model.isEmpty else { throw RefreshFailure.unreadableResponse }
            for budget in config.budgets ?? [] { scoped.append(("模型 · \(provider) · \(model)", ["model", provider, model], budget)) }
        }
        var windows: [QuotaWindow] = []
        var seen: Set<String> = []
        for (scope, parts, budget) in scoped {
            guard !budget.id.isEmpty else { throw RefreshFailure.unreadableResponse }
            let id = "bifrost." + GatewayQuotaSupport.id(parts + [budget.id])
            guard seen.insert(id).inserted else { throw RefreshFailure.unreadableResponse }
            guard let base = budget.max_limit?.value else { continue }
            guard base >= 0, budget.current_usage.map({ $0.value >= 0 }) ?? true else { throw RefreshFailure.unreadableResponse }
            var limit = base
            if let extra = budget.override_amount?.value, extra > 0,
               budget.override_mode == "forever" || (budget.override_mode == "cycles" && (budget.override_cycles_remaining ?? 0) > 0) {
                limit += extra
            }
            guard !limit.isNaN else { throw RefreshFailure.unreadableResponse }
            guard limit > 0 else { continue }
            let period = period(budget.reset_duration)
            var reset: Date?
            let actualLastReset = try GatewayQuotaSupport.date(budget.last_reset)
            // The current API omits the owner's calendar-alignment flag. Only
            // sub-day Go durations cannot be calendar-aligned in the main source.
            if let seconds = period.fixedSeconds, seconds < 86400,
               let last = actualLastReset {
                let candidate = last.addingTimeInterval(TimeInterval(seconds))
                if candidate > collectedAt { reset = candidate }
            }
            let used = budget.current_usage?.value
            let remaining = used.map { limit - $0 }
            guard remaining?.isNaN != true else { throw RefreshFailure.unreadableResponse }
            windows.append(QuotaWindow(id: id, name: (budget.reset_duration ?? "无周期") + " USD 预算", scope: scope, period: period.kind,
                                       isExhausted: used.map { $0 >= limit }, usedPercentage: try GatewayQuotaSupport.percentage(used: used, total: limit),
                                       remainingCount: nil, totalCount: nil, resetsAt: reset,
                                       cycleID: actualLastReset.map { "last-reset:\($0.timeIntervalSince1970)" }, unit: "USD 预算额度",
                                       exactCounts: .init(used: used, remaining: remaining, total: limit)))
        }
        if windows.isEmpty {
            windows = [QuotaWindow(id: "bifrost.no_budget", name: "未配置可读取预算", scope: nil,
                                   usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil)]
        }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: reply.virtual_key_name)
    }

    static func period(_ raw: String?) -> (kind: QuotaPeriod, fixedSeconds: Int?) {
        guard let text = raw, !text.isEmpty else { return (.other, nil) }
        if text == "1M" { return (.monthly, nil) }
        if text == "1w" || text == "7d" { return (.weekly, nil) }
        var rest = Substring(text)
        var seconds = 0.0
        while !rest.isEmpty {
            let digits = rest.prefix { $0 >= "0" && $0 <= "9" || $0 == "." }
            guard !digits.isEmpty, let count = Double(digits), count.isFinite, count > 0 else { return (.other, nil) }
            rest.removeFirst(digits.count)
            guard let unit = rest.first else { return (.other, nil) }
            let factor: Double = unit == "h" ? 3600 : unit == "m" ? 60 : unit == "s" ? 1 : 0
            guard factor > 0 else { return (.other, nil) }
            rest.removeFirst()
            seconds += count * factor
        }
        guard seconds.isFinite, seconds >= 1, seconds < Double(Int32.max), seconds.rounded() == seconds else { return (.other, nil) }
        let duration = Int(seconds)
        return (QuotaPeriod(seconds: duration), duration)
    }
}
