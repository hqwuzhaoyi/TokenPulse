import Foundation

enum GitKrakenSessionCredential {
    static func envelope(token text: String, organizationID: String? = nil) throws -> ProviderCredentialEnvelope {
        var words = text.split(whereSeparator: \.isWhitespace)
        if words.first?.lowercased() == "bearer" { words.removeFirst() }
        guard words.count == 1 else { throw ProviderIntegrationError.invalidCredentialData }
        let token = String(words[0])
        let organization = organizationID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard organization.isEmpty || organization.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        // A JWT expiry is a local freshness hint, never proof of authentication or signature validity.
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        var expiry: Date?
        if pieces.count == 3 {
            var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            struct Claims: Decodable { let exp: Double? }
            if let data = Data(base64Encoded: encoded), let claims = try? JSONDecoder().decode(Claims.self, from: data),
               let exp = claims.exp, exp.isFinite, exp > 0, Int64(exactly: exp.rounded()) != nil {
                expiry = Date(timeIntervalSince1970: exp)
            }
        }
        return .init(provider: .gitKraken, kind: .session, accessToken: token, expiresAt: expiry,
                     metadata: organization.isEmpty ? [:] : ["organizationID": organization])
    }
}

struct GitKrakenProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Quota: Decodable { let used: Double?; let limit: Double? }
        struct Usage: Decodable {
            let used: Double?
            let limit: Double?
            let resetsOn: String?
            let organization: Quota?
        }
        let data: Usage
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .gitKraken, credential.kind == .session,
              !credential.accessToken.isEmpty, credential.expiresAt.map({ $0 > now() }) ?? true else {
            throw RefreshFailure.invalidCredential
        }
        let organization = credential.metadata["organizationID"]
        if let organization {
            guard organization.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil else {
                throw RefreshFailure.invalidCredential
            }
        }
        var request = URLRequest(url: URL(string: "https://api.gitkraken.dev/v1/ai-tasks/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenPulse", forHTTPHeaderField: "Client-Name")
        request.setValue(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1", forHTTPHeaderField: "Client-Version")
        if let organization { request.setValue(organization, forHTTPHeaderField: "gk-org-id") }
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return .init(snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now(), organizationID: organization), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date, organizationID: String? = nil) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let payload = reply.data
        let reset = ProviderHTTP.isoDate(payload.resetsOn)
        var windows: [QuotaWindow] = []
        if let window = window(id: "gitKraken.personal", name: "个人 AI 额度", scope: nil,
                               used: payload.used, limit: payload.limit, reset: reset) { windows.append(window) }
        if let org = payload.organization,
           let window = window(id: "gitKraken.organization", name: "组织共享 AI 额度",
                               scope: organizationID.map { "组织 \($0)" } ?? "默认组织（接口未提供名称）",
                               used: org.used, limit: org.limit, reset: reset) { windows.append(window) }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        // sharedUsed is only this person's contribution to the pool, not a separate allowance.
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }

    private static func window(id: String, name: String, scope: String?, used: Double?, limit: Double?, reset: Date?) -> QuotaWindow? {
        guard let limit, limit.isFinite else { return nil }
        if limit == -1 {
            return QuotaWindow(id: id, name: name, scope: scope, isUnlimited: true,
                               usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "credits")
        }
        guard let used, used.isFinite, used >= 0, limit > 0 else { return nil }
        let percentage = used / limit * 100
        guard percentage.isFinite else { return nil }
        return QuotaWindow(id: id, name: name, scope: scope, isExhausted: used >= limit,
                           usedPercentage: percentage, remainingCount: max(0, limit - used), totalCount: limit,
                           resetsAt: reset, unit: "credits")
    }
}
