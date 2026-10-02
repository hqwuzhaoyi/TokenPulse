import Foundation

/// Contract read from command-code@1.51.3 via pinned Pulse. No plan-price denominators.
struct CommandCodeProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                value = try ProviderDecimal.amount(text)
            } else {
                value = try container.decode(Decimal.self)
            }
            guard !value.isNaN else { throw RefreshFailure.unreadableResponse }
        }
    }

    private struct Whoami: Decodable {
        struct Org: Decodable { let id: String?; let login: String? }
        struct Limit: Decodable {
            let scope: String?
            let model: String?
            let modelLabel: String?
            let spent: Amount?
            let limit: Amount?
            let exceeded: Bool?
            let resetInterval: String?
            let resetAt: String?
        }
        let success: Bool?
        let org: Org?
        let orgLimits: [Limit]?
    }

    private struct Credits: Decodable {
        struct Pots: Decodable {
            let planId: String?
            let monthlyCredits: Amount?
            let purchasedCredits: Amount?
            let freeCredits: Amount?
        }
        struct Limit: Decodable { let used: Amount?; let cap: Amount?; let resetAt: Double? }
        struct Limits: Decodable { let limited: Bool?; let fiveHour: Limit?; let weekly: Limit? }
        let success: Bool?
        let credits: Pots?
        let windowLimits: Limits?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .commandCode, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        do {
            let whoamiData = try await get(path: "/alpha/whoami", items: [.init(name: "limits", value: "1")], token: credential.accessToken)
            let whoami = try Self.decode(Whoami.self, whoamiData)
            guard whoami.success != false else { throw RefreshFailure.server }
            let org = whoami.org?.id
            let creditsData = try await get(path: "/alpha/billing/credits",
                                            items: org.map { [.init(name: "orgId", value: $0)] } ?? [],
                                            token: credential.accessToken)
            return .init(snapshot: try Self.snapshot(whoamiData: whoamiData, creditsData: creditsData,
                                                     accountID: accountID, collectedAt: now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func get(path: String, items: [URLQueryItem], token: String) async throws -> Data {
        var components = URLComponents(string: "https://api.commandcode.ai" + path)!
        components.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }

    static func snapshot(whoamiData: Data, creditsData: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let whoami = try decode(Whoami.self, whoamiData)
        let reply = try decode(Credits.self, creditsData)
        guard whoami.success != false, reply.success != false else { throw RefreshFailure.server }
        guard reply.credits != nil || reply.windowLimits != nil else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        if reply.windowLimits?.limited == true {
            for (id, name, period, limit) in [
                ("commandCode.five-hour", "5 小时消费限额", QuotaPeriod.fiveHour, reply.windowLimits?.fiveHour),
                ("commandCode.weekly", "每周消费限额", QuotaPeriod.weekly, reply.windowLimits?.weekly)
            ] {
                guard let limit else { continue }
                let milliseconds = limit.resetAt
                let reset = milliseconds.flatMap { value in
                    value.isFinite && value > 0 && Int64(exactly: value.rounded()) != nil
                        ? Date(timeIntervalSince1970: value / 1_000) : nil
                }
                if let window = window(id: id, name: name, scope: nil, period: period,
                                       spent: limit.used?.value, limit: limit.cap?.value, reset: reset) {
                    windows.append(window)
                }
            }
        }
        var occurrences: [String: Int] = [:]
        for limit in whoami.orgLimits ?? [] {
            let scopeKey = limit.scope ?? "organization"
            let modelKey = limit.model ?? ""
            let interval = limit.resetInterval ?? "unspecified"
            // Length-prefix provider identity components, never positions or reset timestamps.
            let base = "commandCode.org." + [scopeKey, modelKey, interval].map { "\($0.utf8.count):\($0)" }.joined(separator: ".")
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let id = occurrence == 0 ? base : "\(base).duplicate.\(occurrence)"
            let scope = limit.scope == "model" ? (limit.modelLabel ?? limit.model) : whoami.org?.login
            let period: QuotaPeriod? = switch interval {
            case "daily", "total": nil
            case "weekly": .weekly
            case "monthly": .monthly
            default: nil
            }
            let name = switch interval {
            case "daily": "每日消费限额"
            case "weekly": "每周消费限额"
            case "monthly": "每月消费限额"
            case "total": "累计消费限额"
            default: "组织消费限额"
            }
            if let window = window(id: id, name: name, scope: scope, period: period,
                                   spent: limit.spent?.value, limit: limit.limit?.value,
                                   reset: ProviderHTTP.isoDate(limit.resetAt), exceeded: limit.exceeded) {
                windows.append(window)
            }
        }
        if let pots = reply.credits, let monthly = pots.monthlyCredits?.value,
           let purchased = pots.purchasedCredits?.value, let free = pots.freeCredits?.value {
            // A missing pot is unknown, not zero; only sum all three explicitly supplied pots.
            let total = monthly + purchased + free
            guard !total.isNaN else { throw RefreshFailure.unreadableResponse }
            windows.append(QuotaWindow(id: "commandCode.wallet.USD", name: "可用美元余额", scope: nil,
                                       usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                       wallet: WalletBalance(currency: "USD", total: total)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
                             providerPlanName: reply.credits?.planId)
    }

    private static func window(id: String, name: String, scope: String?, period: QuotaPeriod?,
                               spent: Decimal?, limit: Decimal?, reset: Date?, exceeded: Bool? = nil) -> QuotaWindow? {
        guard let spent, let limit, spent >= 0, limit > 0 else { return nil }
        let percentage = NSDecimalNumber(decimal: spent / limit * 100).doubleValue
        let remaining = NSDecimalNumber(decimal: max(0, limit - spent)).doubleValue
        let total = NSDecimalNumber(decimal: limit).doubleValue
        guard percentage.isFinite, remaining.isFinite, total.isFinite else { return nil }
        return QuotaWindow(id: id, name: name, scope: scope, period: period,
                           isExhausted: exceeded ?? (spent >= limit), usedPercentage: percentage,
                           remainingCount: remaining, totalCount: total, resetsAt: reset, unit: "USD",
                           exactCounts: DecimalQuotaCounts(used: spent, remaining: max(0, limit - spent), total: limit))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw RefreshFailure.unreadableResponse }
        return value
    }
}
