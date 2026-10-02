import CryptoKit
import Foundation

struct VolcengineAccessKeys: Equatable, Sendable {
    let accessKeyID: String
    let secretAccessKey: String

    init(_ entered: String) throws {
        let text = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              parts[0].utf8.count <= 256, parts[1].utf8.count <= 4096,
              parts[0].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              parts[1].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        accessKeyID = String(parts[0])
        secretAccessKey = String(parts[1])
    }

    var value: String { "\(accessKeyID):\(secretAccessKey)" }
    var fingerprint: String {
        SHA256.hash(data: Data("volcengine\ncn-beijing\n\(value)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func envelope() -> ProviderCredentialEnvelope {
        .init(provider: .volcengine, kind: .apiKey, accessToken: value,
              metadata: ["sourceCredentialFingerprint": fingerprint])
    }
}

/// Implements the published Top OpenAPI HMAC-SHA256 scheme. Signing is local to
/// the requesting device; the endpoint, service and region are fixed constants.
enum VolcengineRequestSigner {
    static let host = "open.volcengineapi.com"
    static let region = "cn-beijing"
    static let service = "ark"
    private static let signedHeaders = "content-type;host;x-content-sha256;x-date"
    private static let contentType = "application/x-www-form-urlencoded; charset=utf-8"

    static func request(action: String, keys: VolcengineAccessKeys, date: Date) throws -> URLRequest {
        guard ["GetCodingPlanUsage", "GetAFPUsage"].contains(action) else { throw ProviderIntegrationError.invalidCredentialData }
        var components = URLComponents(string: "https://\(host)/")!
        components.queryItems = [URLQueryItem(name: "Action", value: action), URLQueryItem(name: "Version", value: "2024-01-01")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in headers(url: components.url!, keys: keys, date: date) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func headers(url: URL, keys: VolcengineAccessKeys, date: Date, body: Data = Data()) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: date)
        let day = String(timestamp.prefix(8))
        let payloadHash = hex(SHA256.hash(data: body))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pairs: [(name: String, value: String)] = query.map { (encode($0.name), encode($0.value ?? "")) }
        let sorted = pairs.sorted { lhs, rhs in lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name }
        let encodedPairs: [String] = sorted.map { "\($0.name)=\($0.value)" }
        let encoded = encodedPairs.joined(separator: "&")
        let path = encode(url.path.isEmpty ? "/" : url.path, keepingSlashes: true)
        let canonical = "GET\n\(path)\n\(encoded)\ncontent-type:\(contentType)\nhost:\(host)\nx-content-sha256:\(payloadHash)\nx-date:\(timestamp)\n\n\(signedHeaders)\n\(payloadHash)"
        let scope = "\(day)/\(region)/\(service)/request"
        let toSign = "HMAC-SHA256\n\(timestamp)\n\(scope)\n\(hex(SHA256.hash(data: Data(canonical.utf8))))"
        var signingKey = Data(keys.secretAccessKey.utf8)
        for element in [day, region, service, "request"] {
            signingKey = Data(HMAC<SHA256>.authenticationCode(for: Data(element.utf8), using: SymmetricKey(data: signingKey)))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(toSign.utf8), using: SymmetricKey(data: signingKey)))
        return ["Content-Type": contentType, "Host": host, "X-Date": timestamp, "X-Content-Sha256": payloadHash,
                "Authorization": "HMAC-SHA256 Credential=\(keys.accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"]
    }

    private static func encode(_ text: String, keepingSlashes: Bool = false) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~" + (keepingSlashes ? "/" : ""))
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
    private static func hex<T: Sequence>(_ value: T) -> String where T.Element == UInt8 {
        value.map { String(format: "%02x", $0) }.joined()
    }
}

struct VolcengineProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .volcengine, credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        let keys: VolcengineAccessKeys
        do { keys = try VolcengineAccessKeys(credential.accessToken) }
        catch { throw RefreshFailure.invalidCredential }
        guard credential.metadata["sourceCredentialFingerprint"] == keys.fingerprint else { throw RefreshFailure.invalidCredential }
        let collectedAt = now()
        async let coding = fetch(action: "GetCodingPlanUsage", keys: keys, date: collectedAt)
        async let agent = fetch(action: "GetAFPUsage", keys: keys, date: collectedAt)
        let outcomes = try await [coding, agent]
        let windows = outcomes.flatMap { (try? $0.get()) ?? [] }
        guard !windows.isEmpty else {
            let failures = outcomes.compactMap { result -> RefreshFailure? in if case .failure(let error) = result { return error }; return nil }
            for failure in [RefreshFailure.invalidCredential, .rateLimited, .network, .unreadableResponse, .server] where failures.contains(failure) {
                throw failure
            }
            throw RefreshFailure.subscriptionRequired
        }
        var snapshot = QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
        snapshot.sourceCredentialFingerprint = keys.fingerprint
        return .init(snapshot: snapshot, updatedCredential: nil)
    }

    private func fetch(action: String, keys: VolcengineAccessKeys, date: Date) async throws -> Result<[QuotaWindow], RefreshFailure> {
        do {
            let request = try VolcengineRequestSigner.request(action: action, keys: keys, date: date)
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            guard response.url?.host == VolcengineRequestSigner.host, response.url?.scheme == "https" else { throw RefreshFailure.server }
            if response.statusCode == 404 { return .failure(.subscriptionRequired) }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { return .failure(failure) }
            return .success(try Self.windows(data, action: action))
        } catch is CancellationError { throw CancellationError() }
        catch { return .failure(ProviderHTTP.refreshFailure(error) as? RefreshFailure ?? .network) }
    }

    private struct Number: Decodable {
        let value: Double
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                guard text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil, let parsed = Double(text) else { throw RefreshFailure.unreadableResponse }
                value = parsed
            } else { value = try container.decode(Double.self) }
            guard value.isFinite, value >= 0 else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct Coding: Decodable {
        struct Row: Decodable { let Level: String; let Percent: Number?; let ResetTimestamp: Number? }
        struct Payload: Decodable { let QuotaUsage: [Row]?; let Status: String? }
        let Result: Payload
    }
    private struct Agent: Decodable {
        struct Row: Decodable { let Quota: Number; let Used: Number?; let ResetTime: Number? }
        struct Payload: Decodable { let AFPFiveHour: Row?; let AFPWeekly: Row?; let AFPMonthly: Row?; let Status: String? }
        let Result: Payload
    }

    static func windows(_ data: Data, action: String) throws -> [QuotaWindow] {
        let root = try ProviderHTTP.json(data)
        if let metadata = root["ResponseMetadata"] as? [String: Any], let error = metadata["Error"] as? [String: Any] {
            let code = (error["Code"] as? String ?? "").lowercased()
            if ["invalidaccesskey", "signaturedoesnotmatch", "invalidsecuritytoken", "accessdenied", "authentication"].contains(where: { code.contains($0) }) { throw RefreshFailure.invalidCredential }
            if code.contains("throttl") || code.contains("ratelimit") { throw RefreshFailure.rateLimited }
            if code.contains("subscription") || code.contains("notfound") { throw RefreshFailure.subscriptionRequired }
            throw RefreshFailure.server
        }
        do {
            switch action {
            case "GetCodingPlanUsage":
                let reply = try JSONDecoder().decode(Coding.self, from: data)
                guard reply.Result.QuotaUsage != nil || reply.Result.Status != nil else { throw RefreshFailure.unreadableResponse }
                var seen: Set<QuotaPeriod> = []
                return try (reply.Result.QuotaUsage ?? []).compactMap { row in
                    guard let period = period(row.Level) else { return nil }
                    guard seen.insert(period).inserted else { throw RefreshFailure.unreadableResponse }
                    return QuotaWindow(id: "volcengine.coding.\(period.rawValue)", name: name(period), scope: "Coding Plan", period: period,
                                       isExhausted: row.Percent.map { $0.value >= 100 }, usedPercentage: row.Percent?.value,
                                       remainingCount: nil, totalCount: nil, resetsAt: try reset(row.ResetTimestamp?.value))
                }
            case "GetAFPUsage":
                let reply = try JSONDecoder().decode(Agent.self, from: data)
                let rows: [(QuotaPeriod, Agent.Row?)] = [(.fiveHour, reply.Result.AFPFiveHour), (.weekly, reply.Result.AFPWeekly), (.monthly, reply.Result.AFPMonthly)]
                guard rows.contains(where: { $0.1 != nil }) || reply.Result.Status != nil else { throw RefreshFailure.unreadableResponse }
                return try rows.compactMap { period, row in
                    guard let row, row.Quota.value > 0 else { return nil }
                    let used = row.Used?.value
                    let percentage = used.map { $0 / row.Quota.value * 100 }
                    guard percentage?.isFinite ?? true else { throw RefreshFailure.unreadableResponse }
                    return QuotaWindow(id: "volcengine.agent.\(period.rawValue)", name: name(period), scope: "Agent Plan", period: period,
                                       isExhausted: used.map { $0 >= row.Quota.value }, usedPercentage: percentage,
                                       remainingCount: used.map { row.Quota.value - $0 }, totalCount: row.Quota.value,
                                       resetsAt: try reset(row.ResetTime?.value), unit: "AFP")
                }
            default: throw RefreshFailure.unreadableResponse
            }
        } catch let failure as RefreshFailure { throw failure }
        catch { throw RefreshFailure.unreadableResponse }
    }

    private static func period(_ level: String) -> QuotaPeriod? {
        switch level.lowercased() {
        case "5h", "5-hour", "five_hour", "session": .fiveHour
        case "week", "weekly": .weekly
        case "month", "monthly": .monthly
        default: nil
        }
    }
    private static func name(_ period: QuotaPeriod) -> String {
        switch period { case .fiveHour: "5 小时额度"; case .weekly: "每周额度"; case .monthly: "每月额度"; case .other: "额度" }
    }
    private static func reset(_ value: Double?) throws -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value >= 100_000_000_000 ? value / 1000 : value
        guard seconds < 32_503_680_000 else { throw RefreshFailure.unreadableResponse }
        return Date(timeIntervalSince1970: seconds)
    }
}
