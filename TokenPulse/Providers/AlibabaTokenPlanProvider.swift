import Foundation
import CryptoKit
import CoreFoundation

struct AlibabaTokenPlanCredential: Sendable {
    let keys: VolcengineAccessKeys
    let region: ProviderRegion
    let site: AlibabaTokenPlanSite

    init(key: String, region: ProviderRegion?, site: AlibabaTokenPlanSite?) throws {
        guard let region, let site, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-sp-") else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        keys = try VolcengineAccessKeys(key)
        self.region = region
        self.site = site
    }
    init(envelope: ProviderCredentialEnvelope) throws {
        guard envelope.provider == .alibabaTokenPlan, envelope.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        try self.init(key: envelope.accessToken, region: envelope.providerRegion,
                      site: envelope.metadata["consoleSite"].flatMap(AlibabaTokenPlanSite.init(rawValue:)))
    }
    var fingerprint: String {
        // Recompute from actual credentials and target; never trust a claimed fingerprint.
        let data = try! JSONEncoder().encode(["alibabaTokenPlan", region.rawValue, site.rawValue, keys.value])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    func envelope() -> ProviderCredentialEnvelope {
        .init(provider: .alibabaTokenPlan, kind: .apiKey, accessToken: keys.value,
              metadata: ["region": region.rawValue, "consoleSite": site.rawValue, "sourceCredentialFingerprint": fingerprint])
    }
    var tokenHost: String { "modelstudio.\(region.alibabaRegionID).aliyuncs.com" }
    var gatewayHost: String {
        switch (region, site) {
        case (.china, .domestic): "bailian-cs.console.aliyun.com"
        case (.china, .international): "bailian-cs.console.alibabacloud.com"
        case (.international, .domestic): "modelstudio-cs.console.aliyun.com"
        case (.international, .international): "bailian-singapore-cs.alibabacloud.com"
        }
    }
    var gatewayAction: String { region == .china ? "BroadScopeAspnGateway" : "IntlBroadScopeAspnGateway" }
}

/// ACS3-HMAC-SHA256, pinned to modelstudioai/cli 8bbbbc7 client/acs.ts.
/// GenerateCLIAccessToken signs an empty body, not an empty JSON object.
enum AlibabaTokenPlanSigner {
    static func request(credential: AlibabaTokenPlanCredential, date: Date, nonce: String) -> URLRequest {
        let host = credential.tokenHost
        let path = "/modelstudio/cli/generateAccessToken"
        let formatter = ISO8601DateFormatter()
        let hash = hex(SHA256.hash(data: Data()))
        var headers = ["host": host, "content-type": "application/json",
                       "x-acs-action": "GenerateCLIAccessToken", "x-acs-version": "2026-02-10",
                       "x-acs-date": formatter.string(from: date), "x-acs-signature-nonce": nonce,
                       "x-acs-content-sha256": hash]
        let names = headers.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(headers[$0]!)" }.joined(separator: "\n") + "\n"
        let signedHeaders = names.joined(separator: ";")
        let canonical = ["POST", path, "", canonicalHeaders, signedHeaders, hash].joined(separator: "\n")
        let message = "ACS3-HMAC-SHA256\n\(hex(SHA256.hash(data: Data(canonical.utf8))))"
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(credential.keys.secretAccessKey.utf8))))
        headers["authorization"] = "ACS3-HMAC-SHA256 Credential=\(credential.keys.accessKeyID),SignedHeaders=\(signedHeaders),Signature=\(signature)"
        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
    private static func hex<T: Sequence>(_ value: T) -> String where T.Element == UInt8 {
        value.map { String(format: "%02x", $0) }.joined()
    }
}

struct AlibabaTokenPlanProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let usageAPI = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage"
    private enum ConsoleError: Error { case notLogined }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        let scope: AlibabaTokenPlanCredential
        do { scope = try .init(envelope: credential) } catch { throw RefreshFailure.invalidCredential }
        do {
            for attempt in 0...1 {
                let token = try await generateToken(scope)
                do {
                    let request = try Self.usageRequest(scope: scope, token: token)
                    let data = try await send(request)
                    var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
                    snapshot.sourceCredentialFingerprint = scope.fingerprint
                    return .init(snapshot: snapshot, updatedCredential: nil)
                } catch ConsoleError.notLogined {
                    if attempt == 1 { throw RefreshFailure.invalidCredential }
                }
            }
            throw RefreshFailure.invalidCredential
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    private func generateToken(_ scope: AlibabaTokenPlanCredential) async throws -> String {
        let data = try await send(AlibabaTokenPlanSigner.request(credential: scope, date: now(), nonce: UUID().uuidString.lowercased()))
        let frame = try Self.unwrap(data)
        guard let token = frame["cliAccessToken"] as? String, !token.isEmpty,
              token.utf8.count <= 16384, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw RefreshFailure.unreadableResponse
        }
        return token
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == "https", response.url?.host == request.url?.host,
              response.url?.port == request.url?.port else { throw RefreshFailure.server }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        return data
    }
    static func usageRequest(scope: AlibabaTokenPlanCredential, token: String) throws -> URLRequest {
        var url = URLComponents(string: "https://\(scope.gatewayHost)/cli/api.json")!
        url.queryItems = [.init(name: "action", value: scope.gatewayAction), .init(name: "product", value: "sfm_bailian"), .init(name: "api", value: usageAPI)]
        let params: [String: Any] = ["Api": usageAPI, "V": "1.0", "Data": ["cornerstoneParam": ["protocol": "V2", "console": "ONE_CONSOLE", "productCode": "p_efm", "switchUserType": 3, "consoleSite": "BAILIAN_ALIYUN"]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        // URLSearchParams-compatible form escaping (space is '+').
        func form(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._"))!.replacingOccurrences(of: "%20", with: "+")
        }
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = Data("params=\(form(json))&region=\(form(scope.region.alibabaRegionID))".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }
    private static func unwrap(_ data: Data) throws -> [String: Any] {
        var frame = try ProviderHTTP.json(data)
        for depth in 0...5 {
            let code = (frame["errorCode"] ?? frame["Code"]) as? String
            if code?.contains("NotLogined") == true { throw ConsoleError.notLogined }
            if let code, !code.isEmpty {
                let lower = code.lowercased()
                if lower.contains("throttl") { throw RefreshFailure.rateLimited }
                if lower.contains("accessdenied") || lower.contains("signature") || lower.contains("invalidaccesskey") || lower.contains("forbidden") { throw RefreshFailure.invalidCredential }
                throw RefreshFailure.server
            }
            for key in ["success", "Success"] where frame[key] != nil {
                guard let flag = frame[key] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { throw RefreshFailure.unreadableResponse }
                if !flag.boolValue { throw RefreshFailure.server }
            }
            guard let nested = frame["DataV2"] ?? frame["data"] ?? frame["result"] else { return frame }
            guard depth < 5 else { throw RefreshFailure.unreadableResponse }
            if let object = nested as? [String: Any] { frame = object }
            else if let text = nested as? String { frame = try ProviderHTTP.json(Data(text.utf8)) }
            else { throw RefreshFailure.unreadableResponse }
        }
        throw RefreshFailure.unreadableResponse
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let frame = try unwrap(data)
        let rows: [(String, String, QuotaPeriod)] = [("per5Hour", "5 小时额度", .fiveHour), ("per1Week", "每周额度", .weekly)]
        let windows = try rows.compactMap { prefix, name, period -> QuotaWindow? in
            let percentage = frame[prefix + "Percentage"]
            let reset = frame[prefix + "ResetTime"]
            guard percentage != nil || reset != nil else { return nil }
            func number(_ value: Any?) throws -> Double? {
                guard let value, !(value is NSNull) else { return nil }
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw RefreshFailure.unreadableResponse }
                return number.doubleValue
            }
            let ratio = try number(percentage)
            guard ratio.map({ (0...1).contains($0) }) ?? true else { throw RefreshFailure.unreadableResponse }
            let millis = try number(reset)
            guard millis.map({ $0 >= 0 && $0 < 32_503_680_000_000 }) ?? true else { throw RefreshFailure.unreadableResponse }
            return QuotaWindow(id: "alibabaTokenPlan.\(period.rawValue)", name: name, scope: "Personal Token Plan", period: period,
                               isExhausted: nil, usedPercentage: ratio.map { $0 * 100 }, remainingCount: nil, totalCount: nil,
                               resetsAt: millis.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil })
        }
        // An empty personal response is valid but does not mean an unlimited plan.
        guard !windows.isEmpty || frame.isEmpty else { throw RefreshFailure.unreadableResponse }
        var snapshot = QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
        if windows.isEmpty { snapshot.quotaStatusText = "未提供个人 Token Plan 额度" }
        return snapshot
    }
}
