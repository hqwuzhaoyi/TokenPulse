import Foundation

struct V0ProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .v0, credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        func fetch(_ path: String) async throws -> Data {
            var request = URLRequest(url: URL(string: "https://api.v0.dev/v1/\(path)")!)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return data
        }
        do {
            let billing = try await fetch("user/billing")
            let rate: Data?
            do { rate = try await fetch("rate-limits") }
            catch is CancellationError { throw CancellationError() }
            catch { rate = nil }
            let windows = try Self.windows(billing: billing, rate: rate)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self), let amount = try DevPassProviderClient.amount(text) { value = amount }
            else {
                let amount = try container.decode(Decimal.self)
                guard !amount.isNaN, amount >= 0 else { throw RefreshFailure.unreadableResponse }
                value = amount
            }
        }
    }
    private struct Stamp: Decodable {
        let value: Date?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw: Double
            if let text = try? container.decode(String.self) {
                if let parsed = ProviderHTTP.isoDate(text) { value = parsed; return }
                guard let number = Double(text) else { throw RefreshFailure.unreadableResponse }
                raw = number
            } else { raw = try container.decode(Double.self) }
            guard raw.isFinite, raw >= 0 else { throw RefreshFailure.unreadableResponse }
            if raw == 0 { value = nil; return }
            let seconds = raw >= 1e12 ? raw / 1000 : raw
            guard Int64(exactly: (seconds * 1000).rounded()) != nil else { throw RefreshFailure.unreadableResponse }
            value = Date(timeIntervalSince1970: seconds)
        }
    }
    private struct Quota: Decodable { let limit: Amount?; let remaining: Amount?; let reset: Stamp? }
    private struct Token: Decodable {
        struct Balance: Decodable { let total: Amount?; let remaining: Amount? }
        struct Cycle: Decodable { let end: Stamp? }
        let balance: Balance?; let billingCycle: Cycle?
    }
    private struct Kind: Decodable { let billingType: String }
    private struct Envelope<T: Decodable>: Decodable { let data: T }

    static func windows(billing: Data, rate: Data?) throws -> [QuotaWindow] {
        do {
            let kind = try JSONDecoder().decode(Kind.self, from: billing).billingType
            let quota: (Decimal?, Decimal?, Date?)
            switch kind {
            case "token":
                let token = try JSONDecoder().decode(Envelope<Token>.self, from: billing).data
                quota = (token.balance?.total?.value, token.balance?.remaining?.value, token.billingCycle?.end?.value)
            case "legacy":
                let legacy = try JSONDecoder().decode(Envelope<Quota>.self, from: billing).data
                quota = (legacy.limit?.value, legacy.remaining?.value, legacy.reset?.value)
            default: throw RefreshFailure.unreadableResponse
            }
            var result: [QuotaWindow] = []
            if let billing = try window(id: "v0.billing", name: "账期 credits", total: quota.0, remaining: quota.1, reset: quota.2, unit: "credits") { result.append(billing) }
            // Auxiliary data has its own best-effort boundary; never discard successfully parsed billing.
            if let rate, let entry = try? JSONDecoder().decode(Quota.self, from: rate),
               let window = try? window(id: "v0.rate_limit", name: "消息限流", total: entry.limit?.value,
                                        remaining: entry.remaining?.value, reset: entry.reset?.value, unit: "条消息") { result.append(window) }
            return result
        } catch { throw RefreshFailure.unreadableResponse }
    }

    private static func window(id: String, name: String, total: Decimal?, remaining: Decimal?, reset: Date?, unit: String) throws -> QuotaWindow? {
        guard let total, total > 0, let remaining else { return nil }
        guard remaining >= 0, remaining <= total else { throw RefreshFailure.unreadableResponse }
        var lhs = total, rhs = remaining, used = Decimal(0)
        guard NSDecimalSubtract(&used, &lhs, &rhs, .plain) == .noError else { throw RefreshFailure.unreadableResponse }
        let percentage = NSDecimalNumber(decimal: used).doubleValue / NSDecimalNumber(decimal: total).doubleValue * 100
        guard percentage.isFinite else { throw RefreshFailure.unreadableResponse }
        return QuotaWindow(id: id, name: name, scope: nil, period: .other, isExhausted: remaining == 0,
                           usedPercentage: percentage, remainingCount: nil, totalCount: nil, resetsAt: reset, unit: unit,
                           exactCounts: .init(used: used, remaining: remaining, total: total))
    }
}
