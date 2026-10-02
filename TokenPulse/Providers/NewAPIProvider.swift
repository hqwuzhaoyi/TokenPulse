import CryptoKit
import Foundation

/// A gateway root belongs to one credential, rather than to a provider globally.
struct GatewayServerAddress: Equatable, Sendable {
    let url: URL

    init(_ entered: String, trimming suffixes: [String] = ["/v1"]) throws {
        let text = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\\"),
              !text.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        if parts.port == 443 { parts.port = nil }
        // Encoded separators and relative path segments change endpoint routing.
        let path = parts.percentEncodedPath
        guard !path.lowercased().contains("%2f"), !path.lowercased().contains("%5c"),
              !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        for suffix in suffixes where parts.path.hasSuffix(suffix) {
            parts.path.removeLast(suffix.count)
            break
        }
        guard let root = parts.url else { throw ProviderIntegrationError.invalidCredentialData }
        url = root
    }

    var value: String { url.absoluteString }

    func endpoint(_ path: String) -> URL {
        url.appendingPathComponent(path)
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? 443) == (rhs.port ?? 443)
    }
}

extension ProviderCredentialEnvelope {
    var gatewayAddress: GatewayServerAddress? {
        guard let value = metadata["serverAddress"] else { return nil }
        return try? GatewayServerAddress(value)
    }

    var sourceCredentialIdentity: String? {
        provider == .newAPI ? gatewayIdentity : metadata["sourceCredentialFingerprint"]
    }

    /// Scope is canonical server + key; metadata order and trailing /v1 are irrelevant.
    var gatewayIdentity: String? {
        guard provider == .newAPI, kind == .apiKey, let address = gatewayAddress,
              let bytes = try? JSONEncoder().encode([provider.rawValue, address.value, accessToken]) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Uses an ephemeral, cookie-free session and never forwards a gateway credential
/// through a redirect to another scheme, host or port.
struct GatewayProviderTransport: ProviderTransport {
    private static let delegate = GatewayRedirectDelegate()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Self.session.data(for: request)
    }
}

final class GatewayRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let redirected = request.url,
              GatewayServerAddress.sameOrigin(original, redirected) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct NewAPIProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .apiKey, let address = credential.gatewayAddress else {
            throw RefreshFailure.invalidCredential
        }
        func request(_ route: String, authenticated: Bool) -> URLRequest {
            var request = URLRequest(url: address.endpoint(route))
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if authenticated {
                request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            }
            return request
        }
        do {
            let subscription = try await fetch(request("v1/dashboard/billing/subscription", authenticated: true))
            let usage = try await fetch(request("v1/dashboard/billing/usage", authenticated: true))
            // Unit settings can change. Fetch each pass, without the account's key.
            let status = try await fetch(request("api/status", authenticated: false))
            var snapshot = try Self.snapshot(subscription: subscription, usage: usage, status: status,
                                             accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard let requested = request.url, let received = response.url,
              GatewayServerAddress.sameOrigin(requested, received) else { throw RefreshFailure.server }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }

    private struct Subscription: Decodable {
        let hard_limit_usd: Amount
        let soft_limit_usd: Amount?
        let system_hard_limit_usd: Amount?
    }
    private struct Usage: Decodable { let total_usage: Amount }
    private struct Status: Decodable {
        struct Payload: Decodable {
            let quota_display_type: String?
            let display_in_currency: Bool?
        }
        let success: Bool
        let data: Payload
    }
    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                guard text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
                      text.filter({ $0 >= "0" && $0 <= "9" }).count <= 38,
                      let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                    throw RefreshFailure.unreadableResponse
                }
                value = amount
            } else {
                value = try container.decode(Decimal.self)
            }
            guard !value.isNaN, value >= 0 else { throw RefreshFailure.unreadableResponse }
        }
    }

    static func snapshot(subscription: Data, usage: Data, status: Data,
                         accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let decoder = JSONDecoder()
        guard let totals = try? decoder.decode(Subscription.self, from: subscription),
              let consumed = try? decoder.decode(Usage.self, from: usage),
              let settings = try? decoder.decode(Status.self, from: status), settings.success else {
            throw RefreshFailure.unreadableResponse
        }
        let unlimited = totals.hard_limit_usd.value == 100_000_000
            && totals.soft_limit_usd?.value == 100_000_000
            && totals.system_hard_limit_usd?.value == 100_000_000
        let amount = totals.hard_limit_usd.value - consumed.total_usage.value / 100
        guard !amount.isNaN else { throw RefreshFailure.unreadableResponse }
        let display = settings.data.quota_display_type?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let currency: String? = if let display { ["USD", "CNY"].contains(display) ? display : nil }
            else { settings.data.display_in_currency == true ? "USD" : nil }
        let wallet = !unlimited ? currency.map { WalletBalance(currency: $0, total: amount) } : nil
        let tokens = !unlimited && display == "TOKENS"
        let name = unlimited ? "无限 Key" : wallet != nil ? "API 钱包余额" : tokens ? "Token 余额" : "余额单位未知"
        let window = QuotaWindow(id: "newAPI.balance", name: name, scope: nil, isUnlimited: unlimited,
                                 usedPercentage: nil,
                                 remainingCount: tokens ? NSDecimalNumber(decimal: amount).doubleValue : nil,
                                 totalCount: nil, resetsAt: nil, unit: tokens ? "tokens" : currency, wallet: wallet)
        return QuotaSnapshot(accountID: accountID, windows: [window], collectedAt: collectedAt)
    }
}
