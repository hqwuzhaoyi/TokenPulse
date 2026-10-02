import CoreFoundation
import CryptoKit
import Foundation

struct IBMBobCredential: Equatable, Sendable {
    enum Mode: String, Sendable { case apikey, token }
    let mode: Mode
    let secret: String
    let expiresAt: Date?

    init(_ entered: String) throws {
        let parts = entered.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let mode = Mode(rawValue: String(parts[0])) else { throw ProviderIntegrationError.invalidCredentialData }
        try self.init(mode: mode, secret: String(parts[1]))
    }
    private init(mode: Mode, secret: String) throws {
        guard !secret.isEmpty, secret.utf8.count <= 32768, secret.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ProviderIntegrationError.invalidCredentialData }
        self.mode = mode
        self.secret = secret
        if mode == .token {
            let segments = secret.split(separator: ".", omittingEmptySubsequences: false)
            guard segments.count == 3, segments.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 } }),
                  let header = Self.jsonSegment(String(segments[0])), let algorithm = header["alg"] as? String, !algorithm.isEmpty, algorithm.lowercased() != "none",
                  let claims = Self.jsonSegment(String(segments[1])) else { throw ProviderIntegrationError.invalidCredentialData }
            if let raw = claims["exp"] {
                guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                      number.doubleValue > 0, number.doubleValue < 32_503_680_000 else { throw ProviderIntegrationError.invalidCredentialData }
                expiresAt = Date(timeIntervalSince1970: number.doubleValue)
            } else { expiresAt = nil }
        } else { expiresAt = nil }
    }
    init(envelope: ProviderCredentialEnvelope) throws {
        guard envelope.provider == .ibmBob, let rawMode = envelope.metadata["bobCredentialMode"], let mode = Mode(rawValue: rawMode),
              envelope.kind == (mode == .token ? .session : .apiKey) else { throw ProviderIntegrationError.invalidCredentialData }
        try self.init(mode: mode, secret: envelope.accessToken)
    }
    var authorization: String { "\(mode == .token ? "Bearer" : "Apikey") \(secret)" }
    var fingerprint: String { SHA256.hash(data: Data("ibmBob\n\(mode.rawValue)\n\(secret)".utf8)).map { String(format: "%02x", $0) }.joined() }
    func envelope() -> ProviderCredentialEnvelope {
        .init(provider: .ibmBob, kind: mode == .token ? .session : .apiKey, accessToken: secret, expiresAt: expiresAt,
              metadata: ["bobCredentialMode": mode.rawValue, "sourceCredentialFingerprint": fingerprint])
    }
    private static func jsonSegment(_ segment: String) -> [String: Any]? {
        var value = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

struct IBMBobProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let home = URL(string: "https://api.us-east.bob.ibm.com")!
    static let regionalHosts: Set<String> = ["api.us-east.bob.ibm.com", "api.eu-de.bob.ibm.com"]

    struct TeamDescriptor: Sendable {
        let instanceID: String
        let teamID: String
        let userID: String
        let base: URL
        let scope: String
        let plan: String?
        let resetsAt: Date?
        let budget: Decimal?
        var windowID: String { "ibmBob.\(instanceID).\(teamID).\(userID)" }
        var endpoint: URL { base.appendingPathComponent("admin/v1/teams/\(teamID)/users/\(userID)") }
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        let bob: IBMBobCredential
        do { bob = try IBMBobCredential(envelope: credential) }
        catch { throw RefreshFailure.invalidCredential }
        if let expiry = bob.expiresAt, expiry <= now() { throw RefreshFailure.invalidCredential }
        do {
            let profile = try await fetch(Self.home.appendingPathComponent("admin/v1/profile"), bob: bob)
            // Validate every region and path/header identifier before making any
            // regional request, including a hostile region in a later instance.
            let teams = try Self.descriptors(profile)
            guard !teams.isEmpty else { throw RefreshFailure.subscriptionRequired }
            var windows: [QuotaWindow] = []
            for team in teams {
                try Task.checkCancellation()
                let body = try await fetch(team.endpoint, bob: bob, team: team)
                windows.append(try Self.window(body, team: team))
            }
            let plans = Array(Set(teams.compactMap(\.plan))).sorted()
            var snapshot = QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now(),
                                         providerPlanName: plans.isEmpty ? nil : plans.joined(separator: ", "))
            snapshot.sourceCredentialFingerprint = bob.fingerprint
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func fetch(_ url: URL, bob: IBMBobCredential, team: TeamDescriptor? = nil) async throws -> Data {
        guard let host = url.host, Self.regionalHosts.contains(host), url.scheme == "https", url.port == nil else { throw RefreshFailure.unreadableResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(bob.authorization, forHTTPHeaderField: "Authorization")
        if let team {
            request.setValue(team.instanceID, forHTTPHeaderField: "x-instance-id")
            request.setValue(team.teamID, forHTTPHeaderField: "x-team-id")
        }
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url == request.url else { throw RefreshFailure.server }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }

    static func regionalBase(_ entered: String?) throws -> URL {
        guard var host = entered?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !host.isEmpty else { return home }
        if host.hasSuffix(".") { host.removeLast() }
        if !host.hasPrefix("api.") { host = "api." + host }
        guard regionalHosts.contains(host) else { throw RefreshFailure.unreadableResponse }
        return URL(string: "https://\(host)")!
    }

    private struct Quantity: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { value = try ProviderDecimal.amount(text) }
            else { value = try container.decode(Decimal.self) }
            guard !value.isNaN, value >= 0 else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct Moment: Decodable {
        let date: Date?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let epoch = try? container.decode(Double.self) {
                guard epoch.isFinite, epoch >= 0, epoch < 32_503_680_000 else { throw RefreshFailure.unreadableResponse }
                date = epoch == 0 ? nil : Date(timeIntervalSince1970: epoch)
            } else {
                let text = try container.decode(String.self)
                guard let parsed = ProviderHTTP.isoDate(text) else { throw RefreshFailure.unreadableResponse }
                date = parsed
            }
        }
    }
    private struct Profile: Decodable {
        struct Instance: Decodable {
            struct Team: Decodable { let id: String; let name: String?; let budget_limit: Quantity? }
            let instance_id: String
            let instance_name: String?
            let name: String?
            let user_id: String?
            let plan_name: String?
            let refresh_at: Moment?
            let region_domain: String?
            let teams: [Team]
        }
        let instances: [Instance]
    }
    private struct Budget: Decodable {
        let usage: Quantity
        let limit: Quantity?
        let reportsBudget: Bool
        private enum CodingKeys: String, CodingKey { case usage; case limit = "budget_limit" }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usage = try container.decode(Quantity.self, forKey: .usage)
            reportsBudget = container.contains(.limit)
            limit = try container.decodeIfPresent(Quantity.self, forKey: .limit)
        }
    }

    static func descriptors(_ data: Data) throws -> [TeamDescriptor] {
        guard let profile = try? JSONDecoder().decode(Profile.self, from: data) else { throw RefreshFailure.unreadableResponse }
        var descriptors: [TeamDescriptor] = []
        var identities: Set<String> = []
        for instance in profile.instances {
            let base = try regionalBase(instance.region_domain)
            guard validID(instance.instance_id) else { throw RefreshFailure.unreadableResponse }
            guard let user = instance.user_id else { continue }
            guard validID(user) else { throw RefreshFailure.unreadableResponse }
            for team in instance.teams {
                guard validID(team.id) else { throw RefreshFailure.unreadableResponse }
                let instanceLabel = nonempty(instance.instance_name ?? instance.name) ?? instance.instance_id
                let teamLabel = nonempty(team.name) ?? team.id
                let descriptor = TeamDescriptor(instanceID: instance.instance_id, teamID: team.id, userID: user,
                                                base: base, scope: "\(instanceLabel) · \(teamLabel)", plan: nonempty(instance.plan_name),
                                                resetsAt: instance.refresh_at?.date, budget: team.budget_limit?.value)
                guard identities.insert(descriptor.windowID).inserted else { throw RefreshFailure.unreadableResponse }
                descriptors.append(descriptor)
            }
        }
        return descriptors
    }

    static func window(_ data: Data, team: TeamDescriptor) throws -> QuotaWindow {
        guard let reply = try? JSONDecoder().decode(Budget.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let used = reply.usage.value
        // An absent per-user field may use the profile's budget. Explicit null is
        // unknown/unbounded and must never inherit an old finite profile limit.
        let budget = reply.reportsBudget ? reply.limit?.value : team.budget
        var percentage: Double?
        var remaining: Decimal?
        if let budget, budget > 0 {
            let ratio = used / budget * 100
            let converted = NSDecimalNumber(decimal: ratio).doubleValue
            remaining = budget - used
            guard !ratio.isNaN, converted.isFinite, remaining?.isNaN == false else { throw RefreshFailure.unreadableResponse }
            percentage = converted
        }
        return QuotaWindow(id: team.windowID, name: budget == nil ? "Bobcoins（预算未提供）" : "Bobcoins",
                           scope: team.scope, period: .monthly, usedPercentage: percentage,
                           remainingCount: nil, totalCount: nil, resetsAt: team.resetsAt, unit: "Bobcoins",
                           exactCounts: DecimalQuotaCounts(used: used, remaining: remaining, total: budget))
    }

    private static func validID(_ value: String) -> Bool {
        value.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z"#, options: .regularExpression) != nil
    }
    private static func nonempty(_ value: String?) -> String? {
        value.flatMap { text in let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines); return trimmed.isEmpty ? nil : trimmed }
    }
}
