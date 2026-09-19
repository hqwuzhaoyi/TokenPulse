import Foundation

struct SuperGrokProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .oauth else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            guard var window = Self.window(root) else {
                throw RefreshFailure.noQuotaWindows
            }
            if window.usedPercentage == nil {
                do {
                    if let measured = try await creditsMeasurement(token: credential.accessToken) {
                        let resetsAt = measured.resetsAt ?? window.resetsAt
                        window = QuotaWindow(id: window.id, name: window.name, scope: window.scope,
                                             period: window.period,
                                             usedPercentage: measured.percent, remainingCount: nil, totalCount: nil,
                                             resetsAt: resetsAt)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Retain the proxy's known period when the additional measurement is unavailable.
                }
            }
            return .init(
                snapshot: QuotaSnapshot(accountID: accountID, windows: [window], collectedAt: now()),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    private func creditsMeasurement(token: String) async throws -> GrokCreditsMeasurement? {
        var request = URLRequest(url: URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = Data([0, 0, 0, 0, 0])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return try GrokCreditsMeasurement.decode(data, headerStatus: response.value(forHTTPHeaderField: "grpc-status"))
    }

    static func window(_ root: [String: Any]) -> QuotaWindow? {
        guard let config = root["config"] as? [String: Any] else { return nil }
        let current = config["currentPeriod"] as? [String: Any]
        let start = ProviderHTTP.isoDate(current?["start"] ?? config["billingPeriodStart"])
        let end = ProviderHTTP.isoDate(current?["end"] ?? config["billingPeriodEnd"])
        let seconds = start.flatMap { start in
            end.flatMap { end in end > start ? Int(end.timeIntervalSince(start).rounded()) : nil }
        }
        let percent = ProviderHTTP.number(config["creditUsagePercent"])
        return QuotaWindow(
            id: "superGrok.pool",
            name: seconds.map { ProviderHTTP.windowName(seconds: $0) } ?? "SuperGrok 套餐额度",
            scope: nil,
            period: QuotaPeriod(seconds: seconds),
            usedPercentage: percent.map { min(max($0, 0), 100) },
            remainingCount: nil,
            totalCount: nil,
            resetsAt: end
        )
    }
}

// Reads the credits RPC's published float and reset timestamp only. Absent usage is not zero.
private struct GrokCreditsMeasurement {
    let percent: Double
    let resetsAt: Date?

    static func decode(_ data: Data, headerStatus: String?) throws -> Self? {
        if let headerStatus, headerStatus != "0" { throw RefreshFailure.unreadableResponse }
        let bytes = [UInt8](data)
        var index = 0
        var message: [UInt8]?
        var status = headerStatus
        while index < bytes.count {
            guard index + 5 <= bytes.count else { throw RefreshFailure.unreadableResponse }
            let flags = bytes[index]
            let length = bytes[(index + 1)..<(index + 5)].reduce(0) { ($0 << 8) | Int($1) }
            index += 5
            guard length <= bytes.count - index else { throw RefreshFailure.unreadableResponse }
            let frame = Array(bytes[index..<(index + length)])
            index += length
            if flags == 0x80 {
                guard let trailer = String(bytes: frame, encoding: .utf8) else { throw RefreshFailure.unreadableResponse }
                for line in trailer.components(separatedBy: .newlines) {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, parts[0].lowercased() == "grpc-status" {
                        status = parts[1].trimmingCharacters(in: .whitespaces)
                        guard status == "0" else { throw RefreshFailure.unreadableResponse }
                    }
                }
            } else {
                guard flags == 0, message == nil else { throw RefreshFailure.unreadableResponse }
                message = frame
            }
        }
        guard status == "0", let message else { throw RefreshFailure.unreadableResponse }
        let response = try fields(message)
        let config = try response[1]?.bytes.map(fields) ?? response
        guard let published = config[1]?.float, published.isFinite, published >= 0, published <= 100 else { return nil }
        let period = try config[8]?.bytes.map(fields)
        let timestamp = period?[3]?.bytes ?? config[5]?.bytes
        let seconds = try timestamp.map(fields)?[1]?.integer
        let date = seconds.flatMap { $0 < 20_000_000_000 ? Date(timeIntervalSince1970: Double($0)) : nil }
        return Self(percent: Double(published), resetsAt: date)
    }

    private struct Field {
        var integer: UInt64?
        var bytes: [UInt8]?
        var float: Float?
    }

    private static func fields(_ bytes: [UInt8]) throws -> [UInt64: Field] {
        var result: [UInt64: Field] = [:]
        var index = 0
        while index < bytes.count {
            let tag = try varint(bytes, index: &index)
            let number = tag >> 3
            guard number > 0, number <= 536_870_911 else { throw RefreshFailure.unreadableResponse }
            switch tag & 7 {
            case 0:
                result[number] = Field(integer: try varint(bytes, index: &index))
            case 1:
                guard index + 8 <= bytes.count else { throw RefreshFailure.unreadableResponse }
                index += 8
            case 2:
                let length = try varint(bytes, index: &index)
                guard length <= UInt64(bytes.count - index) else { throw RefreshFailure.unreadableResponse }
                result[number] = Field(bytes: Array(bytes[index..<(index + Int(length))]))
                index += Int(length)
            case 5:
                guard index + 4 <= bytes.count else { throw RefreshFailure.unreadableResponse }
                let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << ($1 * 8) }
                result[number] = Field(float: Float(bitPattern: bits))
                index += 4
            default: throw RefreshFailure.unreadableResponse
            }
        }
        return result
    }

    private static func varint(_ bytes: [UInt8], index: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard index < bytes.count else { throw RefreshFailure.unreadableResponse }
            let byte = bytes[index]
            index += 1
            let payload = UInt64(byte & 0x7f)
            guard payload <= UInt64.max >> shift else { throw RefreshFailure.unreadableResponse }
            value |= payload << shift
            if byte & 0x80 == 0 { return value }
        }
        throw RefreshFailure.unreadableResponse
    }
}

struct SuperGrokProviderAuthenticator: Sendable {
    private static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    private static let scopes = ["openid", "email", "offline_access", "grok-cli:access"]
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date

    init(transport: any ProviderTransport, now: @escaping @Sendable () -> Date) {
        self.transport = transport
        self.now = now
    }

    func begin() async throws -> ProviderLoginSession {
        var request = URLRequest(url: URL(string: "https://auth.x.ai/oauth2/device/code")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = ProviderHTTP.formBody([
            "client_id": Self.clientID,
            "scope": Self.scopes.joined(separator: " "),
        ])
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        let root = try ProviderHTTP.json(data)
        guard let userCode = root["user_code"] as? String,
              let deviceCode = root["device_code"] as? String,
              let verificationURL = ((root["verification_uri_complete"] as? String)
                ?? (root["verification_uri"] as? String)).flatMap(URL.init(string:)) else {
            throw ProviderIntegrationError.unreadableResponse
        }
        let interval = max(ProviderHTTP.number(root["interval"]) ?? 5, 1)
        let lifetime = ProviderHTTP.number(root["expires_in"]) ?? 15 * 60
        return ProviderLoginSession(
            provider: .superGrok,
            authorizationURL: verificationURL,
            userCode: userCode,
            deviceCode: deviceCode,
            state: nil,
            codeVerifier: nil,
            callbackURL: nil,
            pollingInterval: interval,
            expiresAt: now().addingTimeInterval(lifetime),
            metadata: [:]
        )
    }

    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .superGrok,
              session.expiresAt.map({ $0 > now() }) != false,
              let deviceCode = session.deviceCode else { throw ProviderIntegrationError.loginExpired }
        let (data, response) = try await tokenRequest([
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": deviceCode,
            "client_id": Self.clientID,
        ])
        if response.statusCode == 400 {
            let root = try? ProviderHTTP.json(data)
            switch root?["error"] as? String {
            case "authorization_pending": return .pending(retryAfter: session.pollingInterval ?? 5)
            case "slow_down": return .pending(retryAfter: (session.pollingInterval ?? 5) + 5)
            default: break
            }
        }
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        return .completed(credential: try parseCredential(data, prior: nil).encoded())
    }

    func refreshIfNeeded(_ credential: ProviderCredentialEnvelope) async throws -> ProviderCredentialRefresh {
        guard credential.kind == .oauth else { throw ProviderIntegrationError.invalidCredentialData }
        guard credential.expiresAt.map({ $0 <= now().addingTimeInterval(60) }) == true else {
            return .init(credential: try credential.encoded(), changed: false)
        }
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            throw ProviderIntegrationError.invalidCredential
        }
        let (data, response) = try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes.joined(separator: " "),
        ])
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        return .init(credential: try parseCredential(data, prior: credential).encoded(), changed: true)
    }

    private func tokenRequest(_ form: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://auth.x.ai/oauth2/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = ProviderHTTP.formBody(form)
        return try await ProviderHTTP.send(request, transport: transport)
    }

    private func parseCredential(_ data: Data, prior: ProviderCredentialEnvelope?) throws -> ProviderCredentialEnvelope {
        let root = try ProviderHTTP.json(data)
        guard let accessToken = root["access_token"] as? String,
              let lifetime = ProviderHTTP.number(root["expires_in"]) else {
            throw ProviderIntegrationError.unreadableResponse
        }
        return ProviderCredentialEnvelope(
            provider: .superGrok,
            kind: .oauth,
            accessToken: accessToken,
            refreshToken: (root["refresh_token"] as? String) ?? prior?.refreshToken,
            expiresAt: now().addingTimeInterval(lifetime),
            accountID: prior?.accountID
        )
    }
}
