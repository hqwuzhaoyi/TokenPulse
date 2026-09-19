import Foundation

struct DeepSeekProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Balance: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String
            let topped_up_balance: String
        }
        let is_available: Bool
        let balance_infos: [Balance]
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return ProviderQueryResult(
                snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now()),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RefreshFailure.unreadableResponse
        }
        var currencies: Set<String> = []
        let windows = try reply.balance_infos.map { balance in
            guard ["CNY", "USD"].contains(balance.currency),
                  currencies.insert(balance.currency).inserted else {
                throw RefreshFailure.unreadableResponse
            }
            let wallet = WalletBalance(
                currency: balance.currency,
                total: try money(balance.total_balance),
                granted: try money(balance.granted_balance),
                toppedUp: try money(balance.topped_up_balance)
            )
            return QuotaWindow(
                id: "deepseek.wallet.\(wallet.currency)", name: "\(wallet.currency) 钱包",
                scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil,
                resetsAt: nil, unit: wallet.currency, wallet: wallet
            )
        }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
                             walletAvailable: reply.is_available)
    }

    private static func money(_ text: String) throws -> Decimal {
        let digits = text.filter { $0 >= "0" && $0 <= "9" }
            .drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" })
        guard text.range(of: #"\A-?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              digits.count <= 38,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN else {
            throw RefreshFailure.unreadableResponse
        }
        return amount
    }
}
