import Foundation
import CryptoKit

struct GeminiProviderClient: Sendable {
    static let origin = "https://cloudcode-pa.googleapis.com"
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    struct Project: Sendable { let id: String; let plan: String? }
    private struct Tier: Decodable { let id: String?; let name: String? }
    private struct Load: Decodable { let currentTier: Tier?; let paidTier: Tier?; let cloudaicompanionProject: String? }

    func discoverProject(token: String, configuredProject: String?) async throws -> Project {
        let configuredProject = try Self.validateConfiguredProject(configuredProject)
        var body: [String: Any] = ["metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "PLUGIN_UNSPECIFIED", "ideName": "TokenPulse"]]
        if let configuredProject, !configuredProject.isEmpty { body["cloudaicompanionProject"] = configuredProject }
        let data = try await rpc("loadCodeAssist", token: token, body: body)
        guard let load = try? JSONDecoder().decode(Load.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard load.currentTier != nil else { throw RefreshFailure.googleProjectRequired }
        guard let project = load.cloudaicompanionProject ?? configuredProject, Self.validProject(project) else { throw RefreshFailure.googleProjectRequired }
        let rawPlan = load.paidTier?.name ?? load.currentTier?.name
        let plan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(id: project, plan: plan.flatMap { $0.isEmpty ? nil : String($0.prefix(128)) })
    }

    func authorize(callback: URL, session: ProviderLoginSession, accountID: UUID, configuredProject: String?) async throws -> String {
        let configuredProject = try Self.validateConfiguredProject(configuredProject)
        guard session.provider == .gemini, let client = session.metadata["clientID"] else { throw RefreshFailure.invalidCredential }
        var envelope = try await GoogleNativeOAuth(clientID: client, transport: transport, now: now).exchange(callback: callback, session: session)
        try Task.checkCancellation()
        let project = try await discoverProject(token: envelope.accessToken, configuredProject: configuredProject)
        envelope.metadata["project"] = project.id
        envelope.metadata["localAccountID"] = accountID.uuidString
        envelope.metadata["googleNativeFormat"] = "v1"
        envelope.metadata["sourceCredentialFingerprint"] = try Self.fingerprint(envelope)
        // Validate the actual quota service before allowing this account to be saved.
        _ = try await quota(accountID: accountID, credential: envelope)
        try Task.checkCancellation()
        return try envelope.encoded()
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            let identity = try Self.fingerprint(credential)
            guard credential.metadata["localAccountID"] == accountID.uuidString,
                  let expiration = credential.expiresAt, expiration > now(), let storedProject = credential.metadata["project"] else { throw RefreshFailure.invalidCredential }
            let resolved = try await discoverProject(token: credential.accessToken, configuredProject: storedProject)
            // Never silently switch the queried account's cloud project or its cached identity.
            guard resolved.id == storedProject else { throw RefreshFailure.googleProjectRequired }
            let data = try await rpc("retrieveUserQuota", token: credential.accessToken, body: ["project": storedProject])
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now(), plan: resolved.plan)
            snapshot.sourceCredentialFingerprint = identity
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func validProject(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 58 || $0 == 46 }
    }
    static func validateConfiguredProject(_ value: String?) throws -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        guard validProject(value) else {
            throw ProviderIntegrationError.unsupportedLogin("项目 ID 格式无效，请输入 Cloud 项目 ID；留空则使用已激活项目。")
        }
        return value
    }
    static func fingerprint(_ envelope: ProviderCredentialEnvelope) throws -> String {
        guard envelope.provider == .gemini, envelope.kind == .oauth, GoogleNativeOAuth.headerSafe(envelope.accessToken),
              let refresh = envelope.refreshToken, !refresh.isEmpty,
              let subject = envelope.accountID, !subject.isEmpty,
              let localID = envelope.metadata["localAccountID"], UUID(uuidString: localID) != nil,
              envelope.metadata["googleNativeFormat"] == "v1", let client = envelope.metadata["clientID"],
              let project = envelope.metadata["project"], validProject(project),
              let scope = envelope.metadata["grantedScopes"], Set(scope.split(separator: " ").map(String.init)).isSuperset(of: GoogleNativeOAuth.scopes) else { throw RefreshFailure.invalidCredential }
        _ = try GoogleNativeOAuth.redirectURL(clientID: client)
        let bytes = try JSONEncoder().encode([envelope.provider.rawValue, localID, subject, client, project])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func refreshIfNeeded(_ envelope: ProviderCredentialEnvelope) async throws -> ProviderCredentialRefresh {
        _ = try Self.fingerprint(envelope)
        guard let expires = envelope.expiresAt else { throw RefreshFailure.invalidCredential }
        if expires > now().addingTimeInterval(90) { return .init(credential: try envelope.encoded(), changed: false) }
        guard let client = envelope.metadata["clientID"] else { throw RefreshFailure.invalidCredential }
        let refreshed = try await GoogleNativeOAuth(clientID: client, transport: transport, now: now).refresh(envelope)
        return .init(credential: try refreshed.encoded(), changed: true)
    }

    private func rpc(_ method: String, token: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(Self.origin)/v1internal:\(method)")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenPulse/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        try GoogleNativeOAuth.validateResponseOrigin(response, request: request)
        if response.statusCode == 403 || response.statusCode == 400 {
            struct Reply: Decodable { struct APIError: Decodable { struct Detail: Decodable { let reason: String? }; let details: [Detail]? }; let error: APIError? }
            let reasons = (try? JSONDecoder().decode(Reply.self, from: data))?.error?.details?.compactMap(\.reason) ?? []
            if reasons.contains("UNSUPPORTED_CLIENT") { throw RefreshFailure.googleClientUnsupported }
            if response.statusCode == 403 { throw RefreshFailure.googleProjectRequired }
        }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }

    private struct Bucket: Decodable {
        let remainingAmount: String?; let remainingFraction: Double?; let resetTime: String?; let tokenType: String?; let modelId: String?
    }
    private struct Quota: Decodable { let buckets: [Bucket]? }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date, plan: String? = nil) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Quota.self, from: data), let buckets = reply.buckets else { throw RefreshFailure.unreadableResponse }
        var selected: [String: (Bucket, Date?, Decimal?)] = [:]
        for bucket in buckets {
            // A model ID is the published dimension; no invented Pro/Flash pool grouping.
            guard let model = bucket.modelId, !model.isEmpty else { throw RefreshFailure.unreadableResponse }
            let date: Date?
            if let text = bucket.resetTime {
                guard let parsed = ProviderHTTP.isoDate(text), Int64(exactly: (parsed.timeIntervalSince1970 * 1000).rounded()) != nil else { throw RefreshFailure.unreadableResponse }; date = parsed
            } else { date = nil }
            let amount: Decimal?
            if let text = bucket.remainingAmount { let parsed = try ProviderDecimal.amount(text); guard parsed >= 0 else { throw RefreshFailure.unreadableResponse }; amount = parsed } else { amount = nil }
            if let fraction = bucket.remainingFraction { guard fraction.isFinite, (0...1).contains(fraction) else { throw RefreshFailure.unreadableResponse } }
            guard bucket.remainingFraction != nil || amount != nil else { throw RefreshFailure.unreadableResponse }
            if let old = selected[model] {
                // Fraction-bearing buckets are comparable; amount-only buckets cannot
                // infer a denominator or be mixed across token types.
                guard let fraction = bucket.remainingFraction, let previous = old.0.remainingFraction else { throw RefreshFailure.unreadableResponse }
                if fraction < previous { selected[model] = (bucket, date, amount) }
            } else { selected[model] = (bucket, date, amount) }
        }
        guard !selected.isEmpty else { throw RefreshFailure.noQuotaWindows }
        let windows = selected.keys.sorted().map { model in
            let (bucket, reset, amount) = selected[model]!
            return QuotaWindow(id: "gemini.\(model)", name: model, scope: nil, period: .other,
                isExhausted: bucket.remainingFraction.map { $0 == 0 }, usedPercentage: bucket.remainingFraction.map { (1 - $0) * 100 },
                remainingCount: nil, totalCount: nil, resetsAt: reset, unit: bucket.tokenType ?? "额度单位",
                exactCounts: amount.map { .init(remaining: $0) })
        }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt, providerPlanName: plan)
    }
}
