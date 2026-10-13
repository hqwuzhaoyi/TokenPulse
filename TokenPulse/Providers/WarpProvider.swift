import CryptoKit
import Foundation

struct WarpProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    /// Read-only pinned Pulse query, with uid/createdAt verified in Warp's official query schema.
    static let query = """
    query GetRequestLimitInfo($requestContext: RequestContext!) {
      user(requestContext: $requestContext) {
        __typename
        ... on UserOutput {
          user {
            requestLimitInfo { isUnlimited nextRefreshTime requestLimit requestsUsedSinceLastRefresh }
            bonusGrants { createdAt requestCreditsGranted requestCreditsRemaining expiration }
            workspaces { uid bonusGrantsInfo { grants { createdAt requestCreditsGranted requestCreditsRemaining expiration } } }
          }
        }
      }
    }
    """

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .warp, credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        var request = URLRequest(url: URL(string: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        // Retain the reference's desktop-client compatibility context. Acceptance
        // by the service on iOS/watchOS is a separate, still-unverified condition.
        for (name, value) in ["Authorization": "Bearer \(credential.accessToken)", "Accept": "application/json",
                              "Content-Type": "application/json", "x-warp-client-id": "warp-app",
                              "x-warp-os-category": "macOS", "x-warp-os-name": "macOS",
                              "x-warp-os-version": os, "User-Agent": "Warp/1.0"] { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "operationName": "GetRequestLimitInfo", "query": Self.query,
            "variables": ["requestContext": ["clientContext": [String: String](),
                                              "osContext": ["category": "macOS", "name": "macOS", "version": os]]],
        ])
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let date = now()
            let windows = try Self.windows(data, now: date)
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: date), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self), let value = try DevPassProviderClient.amount(text) { self.value = value }
            else {
                let value = try c.decode(Decimal.self)
                guard !value.isNaN, value >= 0 else { throw RefreshFailure.unreadableResponse }
                self.value = value
            }
        }
    }
    private struct Stamp: Decodable {
        let value: Date?
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            let raw: Double
            if let text = try? c.decode(String.self) {
                if let date = ProviderHTTP.isoDate(text) {
                    guard Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded()) != nil else { throw RefreshFailure.unreadableResponse }
                    value = date; return
                }
                guard let value = Double(text) else { throw RefreshFailure.unreadableResponse }; raw = value
            } else { raw = try c.decode(Double.self) }
            guard raw.isFinite, raw >= 0 else { throw RefreshFailure.unreadableResponse }
            if raw == 0 { value = nil; return }
            let seconds = raw >= 1e12 ? raw / 1000 : raw
            guard Int64(exactly: (seconds * 1000).rounded()) != nil else { throw RefreshFailure.unreadableResponse }
            value = Date(timeIntervalSince1970: seconds)
        }
    }
    private struct Reply: Decodable {
        struct Grant: Decodable { let createdAt: Stamp?; let requestCreditsGranted: Amount?; let requestCreditsRemaining: Amount?; let expiration: Stamp? }
        struct Limit: Decodable { let isUnlimited: Bool?; let nextRefreshTime: Stamp?; let requestLimit: Amount?; let requestsUsedSinceLastRefresh: Amount? }
        struct Workspace: Decodable {
            struct Info: Decodable { let grants: [Grant]? }
            let uid: String?
            let bonusGrantsInfo: Info?
        }
        struct Account: Decodable { let requestLimitInfo: Limit; let bonusGrants: [Grant]?; let workspaces: [Workspace]? }
        struct Output: Decodable { let __typename: String?; let user: Account? }
        struct Payload: Decodable { let user: Output? }
        struct Failure: Decodable { let message: String? }
        let data: Payload?
        let errors: [Failure]?
    }

    static func windows(_ data: Data, now: Date) throws -> [QuotaWindow] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard reply.errors?.isEmpty != false else { throw RefreshFailure.server }
        guard let output = reply.data?.user, output.__typename == nil || output.__typename == "UserOutput",
              let account = output.user else { throw RefreshFailure.unreadableResponse }
        var result: [QuotaWindow] = []
        let limit = account.requestLimitInfo
        if limit.isUnlimited == true {
            result.append(QuotaWindow(id: "warp.plan", name: "套餐 credits", scope: nil, isUnlimited: true,
                                     usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "credits"))
        } else if let cap = limit.requestLimit?.value, cap > 0, let used = limit.requestsUsedSinceLastRefresh?.value {
            let remaining = try difference(cap, used)
            let percentage = try percentage(used, total: cap)
            result.append(QuotaWindow(id: "warp.plan", name: "套餐 credits", scope: nil, period: .other,
                                      isExhausted: used >= cap, usedPercentage: percentage, remainingCount: nil, totalCount: nil,
                                      resetsAt: limit.nextRefreshTime?.value, unit: "credits",
                                      exactCounts: .init(used: used, remaining: remaining, total: cap)))
        }
        var occurrences: [String: Int] = [:]
        func append(_ grants: [Reply.Grant], source: String, label: String) throws {
            for (index, grant) in grants.enumerated() {
                let total = grant.requestCreditsGranted?.value
                let remaining = grant.requestCreditsRemaining?.value
                if total == nil && remaining == nil || total == 0 && (remaining ?? 0) == 0 { continue }
                if let total, let remaining, remaining > total { throw RefreshFailure.unreadableResponse }
                let expiry = grant.expiration?.value
                if let expiry, expiry <= now { continue } // Expired credits are not active zero-usage grants.
                let used = try total.flatMap { total in try remaining.map { remaining in try difference(total, remaining) } }
                let percent = try total.flatMap { total in try used.flatMap { total > 0 ? try percentage($0, total: total) : nil } }
                let fingerprint = [source, grant.createdAt?.value.map { String($0.timeIntervalSince1970) } ?? "",
                                   total.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                                   expiry.map { String($0.timeIntervalSince1970) } ?? ""].joined(separator: "|")
                let hash = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
                let occurrence = occurrences[hash, default: 0]
                occurrences[hash] = occurrence + 1
                result.append(QuotaWindow(id: "warp.grant.\(hash).\(occurrence)", name: "\(label) 附加 credits \(index + 1)", scope: nil,
                                          period: .other, isExhausted: total.flatMap { total in remaining.map { total > 0 && $0 == 0 } },
                                          usedPercentage: percent, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                          unit: "credits", expiresAt: expiry, exactCounts: .init(used: used, remaining: remaining, total: total),
                                          resetSemantics: .nonResettingAllowance))
            }
        }
        try append(account.bonusGrants ?? [], source: "personal", label: "个人")
        for (index, workspace) in (account.workspaces ?? []).enumerated() {
            let grants = workspace.bonusGrantsInfo?.grants ?? []
            guard grants.isEmpty || workspace.uid?.isEmpty == false else { throw RefreshFailure.unreadableResponse }
            if let uid = workspace.uid { try append(grants, source: "workspace:\(uid)", label: "工作区 \(index + 1)") }
        }
        return result
    }

    private static func difference(_ total: Decimal, _ used: Decimal) throws -> Decimal {
        if used >= total { return 0 }
        var lhs = total, rhs = used, result = Decimal(0)
        guard NSDecimalSubtract(&result, &lhs, &rhs, .plain) == .noError else { throw RefreshFailure.unreadableResponse }
        return result
    }
    private static func percentage(_ used: Decimal, total: Decimal) throws -> Double {
        let value = NSDecimalNumber(decimal: used).doubleValue / NSDecimalNumber(decimal: total).doubleValue * 100
        guard value.isFinite else { throw RefreshFailure.unreadableResponse }
        return min(value, 100)
    }
}
