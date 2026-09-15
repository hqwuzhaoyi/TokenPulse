import CryptoKit
import CoreFoundation
import Foundation
import Security

struct QoderProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .qoderInternational, credential.kind == .oauth else {
            throw RefreshFailure.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://openapi.qoder.sh/api/v2/quota/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            let windows = Self.windows(root)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now(),
                                                 quotaExceeded: qoderBool(root["isQuotaExceeded"])),
                         updatedCredential: nil)
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    static func windows(_ root: [String: Any]) -> [QuotaWindow] {
        let expiresAt = QoderProviderAuthenticator.expiry(root["expiresAt"])
        return [("userQuota", "个人额度"), ("orgResourcePackage", "组织资源包")].compactMap { key, name in
            guard let bucket = root[key] as? [String: Any] else { return nil }
            let total = qoderNumber(bucket["total"])
            let used = qoderNumber(bucket["used"])
            let remaining = qoderNumber(bucket["remaining"]) ?? total.flatMap { total in
                used.map { max(total - $0, 0) }
            }
            guard total != nil || remaining != nil else { return nil }
            let computedPercentage = total.flatMap { total -> Double? in
                guard total > 0 else { return nil }
                return (used ?? remaining.map { max(total - $0, 0) }).map { $0 / total * 100 }
            }
            let reportedPercentage = qoderNumber(bucket["percentage"])
                .flatMap { 0...1 ~= $0 ? $0 * 100 : nil }
            return QuotaWindow(id: "qoder.\(key)", name: name, scope: nil, period: .other,
                               isExhausted: remaining.map { $0 == 0 },
                               usedPercentage: computedPercentage ?? reportedPercentage,
                               remainingCount: remaining,
                               totalCount: total, resetsAt: nil,
                               unit: bucket["unit"] as? String,
                               expiresAt: key == "userQuota" ? expiresAt : nil)
        }
    }
}

struct QoderProviderAuthenticator: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func begin() throws -> ProviderLoginSession {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        let verifier = Self.base64URL(Data(bytes))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let nonce = UUID().uuidString.lowercased()
        let machineID = UUID().uuidString.lowercased()
        var url = URLComponents(string: "https://qoder.com/device/selectAccounts")!
        url.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "challenge_method", value: "S256"),
            URLQueryItem(name: "machine_id", value: machineID),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        return ProviderLoginSession(provider: .qoderInternational, authorizationURL: url.url!,
                                    userCode: nil, deviceCode: nil, state: nonce, codeVerifier: verifier,
                                    callbackURL: nil, pollingInterval: 2,
                                    expiresAt: now().addingTimeInterval(180),
                                    metadata: ["machineID": machineID])
    }

    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .qoderInternational,
              let nonce = session.state, !nonce.isEmpty,
              let verifier = session.codeVerifier, !verifier.isEmpty else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        guard session.expiresAt.map({ $0 > now() }) == true else {
            throw ProviderIntegrationError.loginExpired
        }
        var url = URLComponents(string: "https://openapi.qoder.sh/api/v1/deviceToken/poll")!
        url.queryItems = [
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "verifier", value: verifier),
            URLQueryItem(name: "challenge_method", value: "S256"),
        ]
        var request = URLRequest(url: url.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if response.statusCode == 202 || response.statusCode == 404 {
            return .pending(retryAfter: session.pollingInterval ?? 2)
        }
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        let root = try ProviderHTTP.json(data)
        guard let token = root["token"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderIntegrationError.unreadableResponse
        }
        if let challenge = root["code_challenge"] as? String,
           challenge != Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) {
            throw ProviderIntegrationError.invalidCallback
        }
        let credential = ProviderCredentialEnvelope(
            provider: .qoderInternational, kind: .oauth, accessToken: token,
            refreshToken: root["refresh_token"] as? String,
            // expires_at is authoritative. The pinned poll example's expires_in is
            // milliseconds, while parseExpiresAt treats it as seconds; do not invent a lifetime.
            expiresAt: Self.expiry(root["expires_at"]), accountID: root["user_id"] as? String,
            metadata: session.metadata
        )
        return .completed(credential: try credential.encoded())
    }

    func refreshIfNeeded(_ credential: ProviderCredentialEnvelope) throws -> ProviderCredentialRefresh {
        guard credential.provider == .qoderInternational, credential.kind == .oauth else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        // qoder_executor.go Refresh is a no-op: POST .../algo/api/v3/user/refresh_token
        // returns 403 for device `dt-` tokens. Expired credentials require browser login.
        guard credential.expiresAt.map({ $0 <= now() }) != true else {
            throw ProviderIntegrationError.invalidCredential
        }
        return .init(credential: try credential.encoded(), changed: false)
    }

    static func expiry(_ value: Any?) -> Date? {
        if let date = ProviderHTTP.isoDate(value) { return date }
        guard let milliseconds = qoderNumber(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// JSONSerialization stores `true`/`false` as CFBoolean NSNumbers. Reject those so 0/1 stay numeric.
private func qoderJSONBoolean(_ value: Any) -> Bool {
    CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
}

private func qoderNumber(_ value: Any?) -> Double? {
    guard let value, !qoderJSONBoolean(value), let number = ProviderHTTP.number(value),
          number.isFinite, number >= 0 else { return nil }
    return number
}

private func qoderBool(_ value: Any?) -> Bool? {
    guard let value, qoderJSONBoolean(value) else { return nil }
    return value as? Bool
}
