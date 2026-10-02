import Foundation
import CryptoKit

/// Direct Cloud Code quota summary, verified in the official CLI 1.2.15 static descriptors.
/// A user's native OAuth client must be allowed the requested scopes and account entitlement.
struct AntigravityProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let origin = URL(string: "https://cloudcode-pa.googleapis.com")!
    static let scopes = GoogleNativeOAuth.scopes + ["https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs", "https://www.googleapis.com/auth/aicode", "openid"]

    private struct Tier: Decodable { let id: String?; let name: String? }
    private struct Loaded: Decodable {
        struct Validation: Decodable { let code: Int? }
        let currentTier: Tier?
        let paidTier: Tier?
        let cloudaicompanionProject: String?
        let projectValidationError: Validation?
    }

    func authorize(callback: URL, session: ProviderLoginSession, accountID: UUID, configuredProject: String?) async throws -> String {
        guard session.provider == .antigravity, let clientID = session.metadata["clientID"] else { throw RefreshFailure.invalidCredential }
        let oauth = GoogleNativeOAuth(clientID: clientID, transport: transport, now: now, requestedScopes: Self.scopes)
        var envelope = try await oauth.exchange(callback: callback, session: session)
        let project = try Self.project(configuredProject, required: false)
        var body: [String: Any] = ["metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED",
                                                   "pluginType": "PLUGIN_UNSPECIFIED", "ideName": "TokenPulse"]]
        if let project { body["cloudaicompanionProject"] = project }
        let data = try await post("loadCodeAssist", body: body, token: envelope.accessToken)
        guard let loaded = try? JSONDecoder().decode(Loaded.self, from: data) else { throw RefreshFailure.unreadableResponse }
        if let code = loaded.projectValidationError?.code, code != 0 { throw RefreshFailure.insufficientPermissions }
        // allowedTiers alone is an offer, not an activated entitlement. Never call onboardUser.
        guard [loaded.currentTier, loaded.paidTier].compactMap({ $0?.id }).contains(where: { !$0.isEmpty }) else {
            throw RefreshFailure.subscriptionRequired
        }
        let managed = loaded.cloudaicompanionProject.flatMap { $0.isEmpty ? nil : $0 }
        let resolved = try Self.project(managed ?? project, required: true)!
        envelope.metadata["project"] = resolved
        envelope.metadata["localAccountID"] = accountID.uuidString
        if let name = loaded.paidTier?.name ?? loaded.currentTier?.name { envelope.metadata["planName"] = name }
        envelope.metadata["sourceCredentialFingerprint"] = try Self.fingerprint(envelope, accountID: accountID)
        // Only a successfully decoded real quota response may complete login.
        let checked = try await quota(accountID: accountID, credential: envelope)
        return try checked.updatedCredential ?? envelope.encoded()
    }

    func refreshed(_ credential: ProviderCredentialEnvelope) async throws -> ProviderCredentialEnvelope {
        guard credential.provider == .antigravity, credential.kind == .oauth,
              let clientID = credential.metadata["clientID"],
              let expiry = credential.expiresAt, expiry.timeIntervalSince1970.isFinite else { throw RefreshFailure.invalidCredential }
        _ = try GoogleNativeOAuth.redirectURL(clientID: clientID)
        if expiry > now().addingTimeInterval(60) { return credential }
        return try await GoogleNativeOAuth(clientID: clientID, transport: transport, now: now, requestedScopes: Self.scopes).refresh(credential)
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .antigravity, credential.kind == .oauth, !credential.accessToken.isEmpty,
              credential.metadata["localAccountID"] == accountID.uuidString,
              Set((credential.metadata["grantedScopes"] ?? "").split(separator: " ").map(String.init)).isSuperset(of: Self.scopes),
              credential.metadata["sourceCredentialFingerprint"] == (try Self.fingerprint(credential, accountID: accountID)) else {
            throw RefreshFailure.invalidCredential
        }
        let envelope = try await refreshed(credential)
        let project = try Self.project(envelope.metadata["project"], required: true)!
        let data = try await post("retrieveUserQuotaSummary", body: ["project": project], token: envelope.accessToken)
        var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
        snapshot.sourceCredentialFingerprint = envelope.metadata["sourceCredentialFingerprint"]
        snapshot.providerPlanName = envelope.metadata["planName"]
        return .init(snapshot: snapshot, updatedCredential: envelope == credential ? nil : try envelope.encoded())
    }

    private func post(_ method: String, body: [String: Any], token: String) async throws -> Data {
        let endpoint = URL(string: Self.origin.absoluteString + "/v1internal:" + method)!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenPulse", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            guard response.url == endpoint else { throw RefreshFailure.server }
            if response.statusCode == 403 { throw RefreshFailure.insufficientPermissions }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return data
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func project(_ value: String?, required: Bool) throws -> String? {
        guard let value, !value.isEmpty else {
            if required { throw RefreshFailure.insufficientPermissions }; return nil
        }
        guard value.count <= 256, value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 || $0 == 46 || $0 == 58 }) else {
            throw RefreshFailure.unreadableResponse
        }
        return value
    }

    static func fingerprint(_ envelope: ProviderCredentialEnvelope, accountID: UUID) throws -> String {
        guard envelope.provider == .antigravity, envelope.kind == .oauth,
              let subject = envelope.accountID, !subject.isEmpty,
              let client = envelope.metadata["clientID"],
              let project = try project(envelope.metadata["project"], required: true) else { throw RefreshFailure.invalidCredential }
        _ = try GoogleNativeOAuth.redirectURL(clientID: client)
        let data = try JSONEncoder().encode([Provider.antigravity.rawValue, accountID.uuidString, subject, client, project])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct IntegerAmount: Decodable {
        let value: Int64
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) {
                guard text.range(of: #"\A-?[0-9]+\z"#, options: .regularExpression) != nil,
                      let value = Int64(text) else { throw RefreshFailure.unreadableResponse }
                self.value = value
            } else { value = try c.decode(Int64.self) }
        }
    }
    private struct Summary: Decodable {
        struct Bucket: Decodable {
            let bucketId: String
            let displayName: String?
            let window: String?
            let remainingFraction: Double?
            let remainingAmount: IntegerAmount?
            let disabled: Bool?
            let resetTime: String?
        }
        struct Group: Decodable { let displayName: String?; let buckets: [Bucket]? }
        let groups: [Group]?
        let buckets: [Bucket]?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let summary = try? JSONDecoder().decode(Summary.self, from: data),
              summary.groups != nil || summary.buckets != nil else { throw RefreshFailure.unreadableResponse }
        // Root buckets are the deprecated compatibility field; don't double-count them with groups.
        let groups = summary.groups.map { $0.map { ($0.displayName, $0.buckets ?? []) } } ?? [(nil, summary.buckets ?? [])]
        var seen: Set<String> = []
        var windows: [QuotaWindow] = []
        for (group, buckets) in groups {
            for bucket in buckets {
                guard !bucket.bucketId.isEmpty, seen.insert(bucket.bucketId).inserted,
                      bucket.remainingFraction == nil || bucket.remainingAmount == nil else { throw RefreshFailure.unreadableResponse }
                if let fraction = bucket.remainingFraction, !fraction.isFinite || !(0...1).contains(fraction) { throw RefreshFailure.unreadableResponse }
                if let amount = bucket.remainingAmount, amount.value < 0 { throw RefreshFailure.unreadableResponse }
                let enabled = bucket.disabled != true
                let period: QuotaPeriod? = switch bucket.window {
                case "5h": .fiveHour
                case "weekly": .weekly
                case nil: nil
                default: .other
                }
                var reset: Date?
                if let text = bucket.resetTime {
                    guard let parsed = ProviderHTTP.isoDate(text), parsed.timeIntervalSince1970.isFinite else { throw RefreshFailure.unreadableResponse }
                    if enabled { reset = parsed }
                }
                let fraction = enabled ? bucket.remainingFraction : nil
                let amount = enabled ? bucket.remainingAmount?.value : nil
                let name = (bucket.displayName?.isEmpty == false ? bucket.displayName! : bucket.bucketId) + (enabled ? "" : "（未启用）")
                windows.append(.init(id: "antigravity.bucket.\(bucket.bucketId)", name: name, scope: group,
                    period: period, isExhausted: fraction.map { $0 == 0 } ?? amount.map { $0 == 0 },
                    usedPercentage: fraction.map { $0 == 0 ? 100 : min((1 - $0) * 100, Double(100).nextDown) }, remainingCount: nil, totalCount: nil,
                    resetsAt: reset, unit: amount == nil ? nil : "单位（类型未提供）",
                    exactCounts: amount.map { .init(remaining: Decimal($0)) }))
            }
        }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
                     quotaStatusText: windows.isEmpty ? "未返回模型组额度" : nil)
    }
}
