import CryptoKit
import Darwin
import Foundation

/// A gateway root belongs to one credential, rather than to a provider globally.
struct GatewayServerAddress: Equatable, Sendable {
    let url: URL

    init(_ entered: String, trimming suffixes: [String] = ["/v1"]) throws {
        let text = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\\"),
              !text.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let enteredHost = parts.host, !enteredHost.isEmpty,
              parts.percentEncodedHost?.contains("%") != true,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        var host = enteredHost.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if scheme == "http" {
            guard let localHost = Self.localHTTPHost(host) else { throw ProviderIntegrationError.invalidCredentialData }
            host = localHost
        }
        parts.scheme = scheme
        parts.host = host
        if parts.port == Self.defaultPort(scheme) { parts.port = nil }
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

    private static func defaultPort(_ scheme: String?) -> Int {
        scheme?.lowercased() == "http" ? 80 : 443
    }

    /// HTTP is an explicit local-address exception, never a DNS resolution guess.
    /// Strict literals avoid decimal/octal/hex/short-form IP interpretations.
    private static func localHTTPHost(_ host: String) -> String? {
        if host == "localhost" { return host }
        if host.hasSuffix(".local"), host.count <= 253 {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2, labels.allSatisfy({ label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            }) else { return nil }
            return host
        }
        if host.hasPrefix("["), host.hasSuffix("]") {
            let literal = String(host.dropFirst().dropLast())
            var address = in6_addr()
            guard literal.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            let uniqueLocal = bytes[0] & 0xfe == 0xfc
            let linkLocal = bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
            guard loopback || uniqueLocal || linkLocal else { return nil }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let capacity = socklen_t(buffer.count)
            guard inet_ntop(AF_INET6, &address, &buffer, capacity) != nil else { return nil }
            let normalized = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return "[\(normalized)]"
        }
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }
        var bytes: [UInt8] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 3,
                  (piece.count == 1 || piece.first != "0"),
                  piece.allSatisfy({ $0 >= "0" && $0 <= "9" }), let octet = UInt8(piece) else { return nil }
            bytes.append(octet)
        }
        let privateAddress = bytes[0] == 127 || bytes[0] == 10
            || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168)
            || (bytes[0] == 169 && bytes[1] == 254)
        return privateAddress ? bytes.map(String.init).joined(separator: ".") : nil
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && (lhs.port ?? defaultPort(lhs.scheme)) == (rhs.port ?? defaultPort(rhs.scheme))
    }
}

extension ProviderCredentialEnvelope {
    var gatewayAddress: GatewayServerAddress? {
        guard let value = metadata["serverAddress"] else { return nil }
        return try? GatewayServerAddress(value)
    }

    var sourceCredentialIdentity: String? {
        if provider == .newAPI { return gatewayIdentity }
        if [.factory, .devPass, .v0, .warp].contains(provider) {
            guard kind == .apiKey, !accessToken.isEmpty,
                  let bytes = try? JSONEncoder().encode([provider.rawValue, accessToken]) else { return nil }
            // Recompute from the actual Key; metadata cannot claim another Key's identity.
            return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        return metadata["sourceCredentialFingerprint"]
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
        // iOS may deny the first local connection before the permission alert is
        // answered. Let URLSession wait rather than treating that race as a bad key.
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, (try? GatewayServerAddress(url.absoluteString, trimming: [])) != nil else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        return try await Self.session.data(for: request)
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
