import Foundation

/// Device-side GET for the fixed balance routes; credentials never enter URLs.
enum WalletExpansionHTTP {
    static func query(endpoint: URL, provider: Provider, accountID: UUID,
                      credential: ProviderCredentialEnvelope, transport: any ProviderTransport,
                      now: @Sendable () -> Date,
                      parse: (Data, UUID, Date) throws -> QuotaSnapshot) async throws -> ProviderQueryResult {
        guard credential.provider == provider, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return ProviderQueryResult(snapshot: try parse(data, accountID, now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func walletWindow(id: String, wallet: WalletBalance) -> QuotaWindow {
        QuotaWindow(id: id, name: wallet.isMonetary ? "API 钱包余额" : "剩余 \(wallet.currency)", scope: nil,
                    usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                    unit: wallet.currency, wallet: wallet)
    }
}

/// Accept a JSON number or a strict decimal string without a Double intermediate.
struct WalletDecimalValue: Decodable {
    let amount: Decimal
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { amount = try ProviderDecimal.amount(text) }
        else { amount = try container.decode(Decimal.self) }
        guard !amount.isNaN else { throw RefreshFailure.unreadableResponse }
    }
}

enum WalletDecimalArithmetic {
    static func add(_ left: Decimal, _ right: Decimal) throws -> Decimal {
        var left = left, right = right, result = Decimal()
        guard NSDecimalAdd(&result, &left, &right, .plain) == .noError, !result.isNaN else {
            throw RefreshFailure.unreadableResponse
        }
        return result
    }
    static func microDollars(_ value: Decimal) throws -> Decimal {
        var value = value, scale = Decimal(1_000_000), result = Decimal()
        guard NSDecimalDivide(&result, &value, &scale, .plain) == .noError, !result.isNaN else {
            throw RefreshFailure.unreadableResponse
        }
        return result
    }
    static func percentage(used: Decimal, total: Decimal) throws -> Double {
        let value = NSDecimalNumber(decimal: used / total * 100).doubleValue
        guard value.isFinite else { throw RefreshFailure.unreadableResponse }
        return min(max(value, 0), 100)
    }
}
