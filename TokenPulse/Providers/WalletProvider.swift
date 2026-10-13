import Foundation

/// Strict decimal strings avoid binary floating-point rounding for provider money.
enum ProviderDecimal {
    static func amount(_ text: String) throws -> Decimal {
        let digits = text.filter { $0 >= "0" && $0 <= "9" }
            .drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" })
        guard text.range(of: #"\A-?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              digits.count <= 38,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN,
              // Foundation can underflow otherwise valid strings to zero.
              amount != 0 || text.filter({ $0 >= "1" && $0 <= "9" }).isEmpty else {
            throw RefreshFailure.unreadableResponse
        }
        return amount
    }
}

struct PoeProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        let balance: Decimal
        private enum CodingKeys: String, CodingKey { case balance = "current_point_balance" }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try? container.decode(String.self, forKey: .balance) {
                balance = try ProviderDecimal.amount(text)
            } else {
                balance = try container.decode(Decimal.self, forKey: .balance)
            }
            guard !balance.isNaN else { throw RefreshFailure.unreadableResponse }
        }
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletProviderQuery.fetch(
            endpoint: "https://api.poe.com/usage/current_balance", provider: .poe,
            accountID: accountID, credential: credential, transport: transport, now: now,
            parse: Self.snapshot
        )
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RefreshFailure.unreadableResponse
        }
        return QuotaSnapshot(accountID: accountID, windows: [
            QuotaWindow(id: "poe.points", name: "剩余 points", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "points", wallet: WalletBalance(currency: "points", total: reply.balance,
                                                              isMonetary: false))
        ], collectedAt: collectedAt)
    }
}

struct VercelAIGatewayProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable { let balance: String }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletProviderQuery.fetch(
            endpoint: "https://ai-gateway.vercel.sh/v1/credits", provider: .vercelAIGateway,
            accountID: accountID, credential: credential, transport: transport, now: now,
            parse: Self.snapshot
        )
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RefreshFailure.unreadableResponse
        }
        let wallet = WalletBalance(currency: "USD", total: try ProviderDecimal.amount(reply.balance))
        // total_used is lifetime spend, not a quota limit or a balance breakdown.
        return QuotaSnapshot(accountID: accountID, windows: [
            QuotaWindow(id: "vercelAIGateway.wallet.USD", name: "API 钱包余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "USD", wallet: wallet)
        ], collectedAt: collectedAt)
    }
}

private enum WalletProviderQuery {
    static func fetch(endpoint: String, provider: Provider, accountID: UUID,
                      credential: ProviderCredentialEnvelope, transport: any ProviderTransport,
                      now: @Sendable () -> Date,
                      parse: (Data, UUID, Date) throws -> QuotaSnapshot) async throws -> ProviderQueryResult {
        guard credential.provider == provider, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return ProviderQueryResult(snapshot: try parse(data, accountID, now()), updatedCredential: nil)
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }
}
