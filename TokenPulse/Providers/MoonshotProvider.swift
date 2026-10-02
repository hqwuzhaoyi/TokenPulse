import Foundation
import CryptoKit

extension ProviderRegion {
    var moonshotCurrency: String { self == .china ? "CNY" : "USD" }
    var moonshotEndpoint: URL {
        URL(string: "https://api.moonshot.\(self == .china ? "cn" : "ai")/v1/users/me/balance")!
    }
}

extension ProviderCredentialEnvelope {
    var providerRegion: ProviderRegion? {
        guard provider.requiresRegion, let raw = metadata["region"] else { return nil }
        return ProviderRegion(rawValue: raw)
    }

    var regionalIdentity: String? {
        guard provider.requiresRegion, kind == .apiKey, let region = providerRegion,
              let bytes = try? JSONEncoder().encode([provider.rawValue, region.rawValue, accessToken]) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

struct MoonshotProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { value = try ProviderDecimal.amount(text) }
            else { value = try container.decode(Decimal.self) }
            guard !value.isNaN else { throw RefreshFailure.unreadableResponse }
        }
    }

    private struct Reply: Decodable {
        struct Balance: Decodable {
            let available_balance: Amount
            let voucher_balance: Amount?
            let cash_balance: Amount?
        }
        let code: Int
        let status: Bool
        let data: Balance?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .moonshot, credential.kind == .apiKey,
              let region = credential.providerRegion else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: region.moonshotEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, region: region, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.regionalIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, region: ProviderRegion, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard reply.code == 0, reply.status else { throw RefreshFailure.server }
        guard let balance = reply.data else { throw RefreshFailure.unreadableResponse }
        let wallet = WalletBalance(currency: region.moonshotCurrency, total: balance.available_balance.value,
                                   granted: balance.voucher_balance?.value, toppedUp: balance.cash_balance?.value)
        return .init(accountID: accountID, windows: [
            .init(id: "moonshot.\(region.rawValue).wallet", name: "API 钱包余额", scope: nil,
                  usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                  unit: wallet.currency, wallet: wallet)
        ], collectedAt: collectedAt)
    }
}
