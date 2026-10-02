import Foundation

struct KiloCodeProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let endpoint: URL = {
        var url = URLComponents(string: "https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState")!
        url.queryItems = [URLQueryItem(name: "batch", value: "1"),
                          URLQueryItem(name: "input", value: #"{"0":{"json":null},"1":{"json":null}}"#)]
        return url.url!
    }()

    private struct Blocks: Decodable {
        struct Block: Decodable { let balance_mUsd: WalletDecimalValue? }
        let totalBalance_mUsd: WalletDecimalValue?
        let creditBlocks: [Block]?
    }
    private struct Pass: Decodable {
        struct Subscription: Decodable {
            let tier: String?
            let currentPeriodUsageUsd: WalletDecimalValue?
            let currentPeriodBaseCreditsUsd: WalletDecimalValue?
            let currentPeriodBonusCreditsUsd: WalletDecimalValue?
            let nextBillingAt: String?
        }
        let subscription: Subscription?
    }
    private struct Procedure<T: Decodable>: Decodable {
        let value: T
        private enum CodingKeys: String, CodingKey { case error, result, data, json }
        init(from decoder: any Decoder) throws {
            let entry = try decoder.container(keyedBy: CodingKeys.self)
            if entry.contains(.error) {
                let error = try entry.decode(ErrorPayload.self, forKey: .error)
                throw error.unauthorized ? RefreshFailure.invalidCredential : RefreshFailure.unreadableResponse
            }
            let result = try entry.nestedContainer(keyedBy: CodingKeys.self, forKey: .result)
            let data = try result.superDecoder(forKey: .data)
            let wrapped = try data.container(keyedBy: CodingKeys.self)
            value = try wrapped.contains(.json) ? wrapped.decode(T.self, forKey: .json) : T(from: data)
        }
    }
    private struct ErrorPayload: Decodable {
        let unauthorized: Bool
        private enum CodingKeys: String, CodingKey { case code, message, data, json }
        init(from decoder: any Decoder) throws {
            let error = try decoder.container(keyedBy: CodingKeys.self)
            let code = try? error.decode(String.self, forKey: .code)
            let message = try? error.decode(String.self, forKey: .message)
            var nested: ErrorPayload?
            if error.contains(.data) { nested = try? error.decode(ErrorPayload.self, forKey: .data) }
            if error.contains(.json) { nested = try? error.decode(ErrorPayload.self, forKey: .json) }
            unauthorized = [code, message].compactMap { $0?.uppercased() }.contains { $0.contains("UNAUTHORIZED") || $0.contains("FORBIDDEN") }
                || nested?.unauthorized == true
        }
    }
    private struct Batch: Decodable {
        let blocks: Blocks
        let pass: Pass
        private enum CodingKeys: String, CodingKey { case blocks = "0", pass = "1" }
        init(from decoder: any Decoder) throws {
            if var entries = try? decoder.unkeyedContainer() {
                blocks = try entries.decode(Procedure<Blocks>.self).value
                pass = try entries.decode(Procedure<Pass>.self).value
            } else {
                let entries = try decoder.container(keyedBy: CodingKeys.self)
                blocks = try entries.decode(Procedure<Blocks>.self, forKey: .blocks).value
                pass = try entries.decode(Procedure<Pass>.self, forKey: .pass).value
            }
        }
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletExpansionHTTP.query(endpoint: Self.endpoint, provider: .kiloCode, accountID: accountID,
                                            credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply: Batch
        do { reply = try JSONDecoder().decode(Batch.self, from: data) }
        catch let failure as RefreshFailure { throw failure }
        catch { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        var micro = reply.blocks.totalBalance_mUsd?.amount
        if micro == nil, let blocks = reply.blocks.creditBlocks {
            let amounts = blocks.compactMap { $0.balance_mUsd?.amount }
            if !amounts.isEmpty, amounts.count == blocks.count {
                micro = try amounts.reduce(Decimal(0)) { try WalletDecimalArithmetic.add($0, $1) }
            }
        }
        if let micro, micro >= 0 {
            let wallet = WalletBalance(currency: "USD", total: try WalletDecimalArithmetic.microDollars(micro))
            windows.append(WalletExpansionHTTP.walletWindow(id: "kiloCode.wallet.USD", wallet: wallet))
        }
        if let pass = reply.pass.subscription,
           let used = pass.currentPeriodUsageUsd?.amount, used >= 0,
           let base = pass.currentPeriodBaseCreditsUsd?.amount, base >= 0 {
            // Only an absent bonus is zero; an invalid explicit bonus is unreadable.
            let bonus = pass.currentPeriodBonusCreditsUsd?.amount ?? 0
            guard bonus >= 0 else { throw RefreshFailure.unreadableResponse }
            let total = try WalletDecimalArithmetic.add(base, bonus)
            if total > 0 {
                windows.append(QuotaWindow(id: "kiloCode.pass", name: "Kilo Pass 当期额度", scope: nil, period: .other,
                                           isExhausted: used >= total,
                                           usedPercentage: try WalletDecimalArithmetic.percentage(used: used, total: total),
                                           remainingCount: nil, totalCount: nil,
                                           resetsAt: ProviderHTTP.isoDate(pass.nextBillingAt), unit: "USD",
                                           exactCounts: DecimalQuotaCounts(used: used, remaining: max(total - used, 0), total: total)))
            }
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
