import CoreFoundation
import CryptoKit
import Foundation

extension Provider {
    var requiresGatewayAddress: Bool { [.newAPI, .sub2api, .bifrost, .liteLLM, .llmProxy].contains(self) }
}

enum GatewayCredentials {
    static func address(_ entered: String, provider: Provider) throws -> GatewayServerAddress {
        let text = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualified = text.contains("://") ? text : "https://" + text
        let suffixes = provider == .sub2api ? ["/v1/usage", "/v1"] : ["/v1"]
        return try GatewayServerAddress(qualified, trimming: suffixes)
    }

    static func make(provider: Provider, key: String, server: String) throws -> ProviderCredentialEnvelope {
        guard provider.requiresGatewayAddress else { throw ProviderIntegrationError.invalidCredentialData }
        let token = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= 32768, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        let base = try address(server, provider: provider)
        return .init(provider: provider, kind: .apiKey, accessToken: token, metadata: ["serverAddress": base.value])
    }

    static func base(_ credential: ProviderCredentialEnvelope, provider: Provider) throws -> GatewayServerAddress {
        guard credential.provider == provider, credential.kind == .apiKey, provider.requiresGatewayAddress,
              !credential.accessToken.isEmpty, credential.accessToken.utf8.allSatisfy({ (33...126).contains($0) }),
              let server = credential.metadata["serverAddress"] else { throw RefreshFailure.invalidCredential }
        do { return try address(server, provider: provider) }
        catch { throw RefreshFailure.invalidCredential }
    }

    static func fingerprint(_ credential: ProviderCredentialEnvelope) -> String? {
        guard let base = try? base(credential, provider: credential.provider),
              let data = try? JSONEncoder().encode([credential.provider.rawValue, base.value, credential.accessToken]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct GatewayAmount: Decodable, Sendable {
    let value: Decimal
    init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        if let text = try? values.decode(String.self) { value = try ProviderDecimal.amount(text) }
        else { value = try values.decode(Decimal.self) }
        guard !value.isNaN else { throw RefreshFailure.unreadableResponse }
    }
}

enum GatewayQuotaSupport {
    static func checkedAdd(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var left = lhs
        var right = rhs
        var result = Decimal()
        guard NSDecimalAdd(&result, &left, &right, .plain) == .noError, !result.isNaN else {
            throw RefreshFailure.unreadableResponse
        }
        return result
    }

    static func percentage(used: Decimal?, total: Decimal?) throws -> Double? {
        guard let used, let total, total > 0 else { return nil }
        guard used >= 0 else { throw RefreshFailure.unreadableResponse }
        let fraction = used / total * 100
        let percentage = NSDecimalNumber(decimal: fraction).doubleValue
        guard !fraction.isNaN, percentage.isFinite else { throw RefreshFailure.unreadableResponse }
        return percentage
    }

    static func date(_ raw: String?) throws -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let date = ProviderHTTP.isoDate(raw) else { throw RefreshFailure.unreadableResponse }
        return date
    }

    static func id(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func reply(_ route: String, base: GatewayServerAddress, credential: ProviderCredentialEnvelope,
                      transport: any ProviderTransport, query: [URLQueryItem] = [],
                      header: String = "Authorization") async throws -> (Data, HTTPURLResponse) {
        var parts = URLComponents(url: base.endpoint(route), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            parts.queryItems = query
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(header == "Authorization" ? "Bearer \(credential.accessToken)" : credential.accessToken,
                         forHTTPHeaderField: header)
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard let url = response.url, GatewayServerAddress.sameOrigin(base.url, url) else { throw RefreshFailure.server }
        return (data, response)
    }

    static func data(_ route: String, base: GatewayServerAddress, credential: ProviderCredentialEnvelope,
                     transport: any ProviderTransport, query: [URLQueryItem] = [],
                     header: String = "Authorization") async throws -> Data {
        let (data, response) = try await reply(route, base: base, credential: credential, transport: transport, query: query, header: header)
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }
}
