import CoreFoundation
import Foundation

struct LLMProxyProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            let base = try GatewayCredentials.base(credential, provider: .llmProxy)
            let data = try await GatewayQuotaSupport.data("v1/quota-stats", base: base, credential: credential, transport: transport)
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = GatewayCredentials.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let root = try ProviderHTTP.json(data)
        guard let providers = root["providers"] as? [String: Any] else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        for upstream in providers.keys.sorted() {
            guard !upstream.isEmpty, let stats = providers[upstream] as? [String: Any] else { continue }
            let entries: [(String?, Int?, [String: Any])]
            if let groups = stats["quota_groups"] as? [String: Any] {
                entries = groups.keys.sorted().compactMap { name in (groups[name] as? [String: Any]).map { (name, nil, $0) } }
            } else if let groups = stats["quota_groups"] as? [Any] {
                entries = groups.enumerated().compactMap { index, raw in (raw as? [String: Any]).map { (nil, index, $0) } }
            } else { continue }
            for (name, index, group) in entries {
                guard let number = group["remaining_percent"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, (0...100).contains(number.doubleValue) else { continue }
                let remaining = number.doubleValue
                let named = name.flatMap { $0 == "default" || $0.isEmpty ? nil : $0 }
                let scope = [upstream, named].compactMap { $0 }.joined(separator: " · ")
                let identity = [upstream, name == nil ? "index" : "name", name ?? String(index ?? 0)]
                // An invalid group/date cannot manufacture a reset or poison other providers.
                let reset = try? GatewayQuotaSupport.date(group["reset_time"] as? String)
                windows.append(QuotaWindow(id: "llmProxy." + GatewayQuotaSupport.id(identity), name: "配额组", scope: scope, period: .other,
                                           isExhausted: remaining == 0, usedPercentage: 100 - remaining,
                                           remainingCount: nil, totalCount: nil, resetsAt: reset))
            }
        }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
                             quotaStatusText: windows.isEmpty ? "代理未提供可读取的配额组" : nil)
    }
}
