import Foundation
import CoreFoundation

/// GitHub's internal editor quota endpoint; this is not a public quota API.
struct CopilotProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .copilot, credential.kind == .oauth,
              credential.expiresAt.map({ $0 > now() }) ?? true else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("token \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            let windows = Self.windows(root)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now(),
                                                providerPlanName: Self.planName(root["copilot_plan"] as? String)),
                         updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func windows(_ root: [String: Any]) -> [QuotaWindow] {
        let entries = root["quota_snapshots"] as? [String: Any] ?? [:]
        let reset = date(root["quota_reset_date_utc"]) ?? date(root["quota_reset_date"])
        let definitions = [("premium_interactions", "Premium requests"), ("chat", "Chat"), ("completions", "Completions")]
        return definitions.compactMap { key, name in
            guard let entry = entries[key] as? [String: Any],
                  ["has_quota", "unlimited", "overage_permitted"].allSatisfy({ flag in
                      entry[flag] == nil || entry[flag] is NSNull || boolean(entry[flag]) != nil
                  }), boolean(entry["has_quota"]) != false else { return nil }
            let unlimited = boolean(entry["unlimited"]) == true
            let total = nonnegative(entry["entitlement"])
            let remaining = nonnegative(entry["remaining"])
            let percentRemaining = number(entry["percent_remaining"])
            // Older plans emit an unissued placeholder; never discard a genuinely spent lane.
            if boolean(entry["has_quota"]) == nil, !unlimited, total == 0,
               remaining == 0, (percentRemaining ?? 0) >= 100 { return nil }
            guard unlimited || percentRemaining != nil || remaining != nil || total != nil else { return nil }
            let overage = boolean(entry["overage_permitted"])
            let used = unlimited ? nil : percentRemaining.map { min(max(100 - $0, 0), 100) }
            let exhausted: Bool? = unlimited ? false : percentRemaining.map { $0 <= 0 && overage != true }
            return QuotaWindow(
                id: "copilot.\(key)", name: name, scope: nil, period: .monthly,
                isExhausted: exhausted, isUnlimited: unlimited,
                usedPercentage: used, remainingCount: unlimited ? nil : remaining,
                totalCount: unlimited ? nil : total, resetsAt: unlimited ? nil : reset,
                unit: "次", overagePermitted: overage, overageCount: nonnegative(entry["overage_count"])
            )
        }
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    private static func number(_ value: Any?) -> Double? {
        if let numeric = value as? NSNumber, CFGetTypeID(numeric) == CFBooleanGetTypeID() { return nil }
        guard let number = ProviderHTTP.number(value), number.isFinite else { return nil }
        return number
    }

    private static func nonnegative(_ value: Any?) -> Double? {
        number(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func date(_ value: Any?) -> Date? {
        if let iso = ProviderHTTP.isoDate(value) { return iso }
        guard let text = value as? String, text.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: text), formatter.string(from: parsed) == text else { return nil }
        return parsed
    }

    private static func planName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return ["individual": "Individual", "free": "Free", "business": "Business", "enterprise": "Enterprise"][raw.lowercased()] ?? raw
    }
}

struct CopilotProviderAuthenticator: Sendable {
    // Public VS Code Copilot OAuth client, verified in pinned Pulse source.
    // Consent names the editor; TokenPulse is an unofficial integration.
    static let clientID = "Iv1.b507a08c87ecfe98"
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func begin() async throws -> ProviderLoginSession {
        let root = try await post(path: "device/code", body: ["scope": "read:user"])
        guard let code = root["user_code"] as? String, !code.isEmpty,
              let device = root["device_code"] as? String, !device.isEmpty,
              let verification = root["verification_uri"] as? String,
              let url = URL(string: verification), url.scheme == "https", url.host == "github.com",
              url.path == "/login/device", url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil,
              let lifetime = ProviderHTTP.number(root["expires_in"]), lifetime.isFinite, lifetime > 0 else {
            throw ProviderIntegrationError.unreadableResponse
        }
        let interval = ProviderHTTP.number(root["interval"]) ?? 5
        guard interval.isFinite, interval > 0 else { throw ProviderIntegrationError.unreadableResponse }
        // Always use the unfilled verification URI; the user enters this device's code on GitHub.
        return .init(provider: .copilot, authorizationURL: url, userCode: code, deviceCode: device,
                     state: nil, codeVerifier: nil, callbackURL: nil, pollingInterval: interval,
                     expiresAt: now().addingTimeInterval(lifetime), metadata: [:])
    }

    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .copilot, session.expiresAt.map({ $0 > now() }) == true,
              let code = session.deviceCode, !code.isEmpty else { throw ProviderIntegrationError.loginExpired }
        let root = try await post(path: "oauth/access_token", body: [
            "device_code": code, "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        switch root["error"] as? String {
        case "authorization_pending": return .pending(retryAfter: session.pollingInterval ?? 5)
        case "slow_down":
            let interval = ProviderHTTP.number(root["interval"])
            let prior = session.pollingInterval ?? 5
            return .pending(retryAfter: max(prior + 5, interval.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0))
        case "expired_token": throw ProviderIntegrationError.loginExpired
        case "access_denied", "incorrect_device_code", "bad_verification_code": throw ProviderIntegrationError.invalidCredential
        case .some: throw ProviderIntegrationError.unreadableResponse
        case nil: break
        }
        guard let token = root["access_token"] as? String, !token.isEmpty,
              root["token_type"] as? String == "bearer" else { throw ProviderIntegrationError.unreadableResponse }
        if let scope = root["scope"] as? String, scope != "read:user" { throw ProviderIntegrationError.invalidCredential }
        return .completed(credential: try ProviderCredentialEnvelope(
            provider: .copilot, kind: .oauth, accessToken: token,
            metadata: ["scope": "read:user", "client_id": Self.clientID]
        ).encoded())
    }

    func refreshIfNeeded(_ credential: ProviderCredentialEnvelope) throws -> ProviderCredentialRefresh {
        guard credential.provider == .copilot, credential.kind == .oauth,
              credential.expiresAt.map({ $0 > now() }) ?? true else { throw ProviderIntegrationError.invalidCredential }
        // GitHub's device OAuth token has no refresh grant. Revocation requires authorization again.
        return .init(credential: try credential.encoded(), changed: false)
    }

    private func post(path: String, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://github.com/login/\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body.merging(["client_id": Self.clientID]) { _, new in new })
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        return try ProviderHTTP.json(data)
    }
}
