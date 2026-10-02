import CryptoKit
import Foundation

struct XAIManagementCredential: Equatable, Sendable {
    let teamID: String
    let managementKey: String

    init(_ entered: String) throws {
        let parts = entered.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw ProviderIntegrationError.invalidCredentialData }
        try self.init(teamID: String(parts[0]), managementKey: String(parts[1]))
    }

    init(teamID: String, managementKey: String) throws {
        // The API defines a string team ID. Restrict it to one ASCII path segment;
        // UUIDs and the upstream test's team-1 format both satisfy this contract.
        guard teamID.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z"#, options: .regularExpression) != nil,
              !managementKey.isEmpty, managementKey.utf8.count <= 8192,
              managementKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        self.teamID = teamID
        self.managementKey = managementKey
    }

    init(envelope: ProviderCredentialEnvelope) throws {
        guard envelope.provider == .xaiAPI, envelope.kind == .apiKey,
              envelope.metadata["credentialRole"] == "management", let teamID = envelope.metadata["teamID"] else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        try self.init(teamID: teamID, managementKey: envelope.accessToken)
    }

    var fingerprint: String {
        SHA256.hash(data: Data("xaiAPI\n\(teamID)\n\(managementKey)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func envelope() -> ProviderCredentialEnvelope {
        .init(provider: .xaiAPI, kind: .apiKey, accessToken: managementKey,
              metadata: ["teamID": teamID, "credentialRole": "management", "sourceCredentialFingerprint": fingerprint])
    }
    var endpoint: URL {
        URL(string: "https://management-api.x.ai/v1/billing/teams/\(teamID)/prepaid/balance")!
    }
}

struct XAIAPIProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        let management: XAIManagementCredential
        do { management = try XAIManagementCredential(envelope: credential) }
        catch { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: management.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(management.managementKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            guard response.url == request.url else { throw RefreshFailure.server }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, teamID: management.teamID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = management.fingerprint
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Reply: Decodable {
        struct Total: Decodable { let val: String }
        let total: Total
    }

    static func snapshot(_ data: Data, accountID: UUID, teamID: String, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let cents = try ProviderDecimal.amount(reply.total.val)
        let dollars = -cents / 100
        guard !dollars.isNaN, cents == 0 || dollars != 0 else { throw RefreshFailure.unreadableResponse }
        let wallet = WalletBalance(currency: "USD", total: dollars)
        return QuotaSnapshot(accountID: accountID, windows: [
            QuotaWindow(id: "xaiAPI.team.\(teamID).wallet.USD", name: "已入账预付余额", scope: nil,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        unit: "USD", wallet: wallet)
        ], collectedAt: collectedAt, providerPlanName: "团队 \(teamID)")
    }
}
