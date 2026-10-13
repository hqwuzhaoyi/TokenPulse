import Foundation
import CoreFoundation

enum QwenCloudSession {
    static let origin = "https://home.qwencloud.com"
    static let page = URL(string: origin + "/billing/subscription/token-plan-individual")!
    static let policy = CookieWebSessionPolicy(domains: ["qwencloud.com"], path: "/data/api.json",
        names: ["login_qwencloud_ticket", "login_aliyunid_ticket", "qwen_sso_ticket", "login_current_pk", "login_aliyunid_pk", "login_aliyunid_csrf", "csrf", "cna", "sec_token"],
        requiredAnyNames: ["login_qwencloud_ticket", "login_aliyunid_ticket", "qwen_sso_ticket"])
    static var profile: WebProviderLoginProfile {
        .init(loginURL: page, allowedOrigins: [origin]) { cookies, _, accountID, now in
            let envelope = try WebProviderSession.cookieCredential(cookies: cookies, policy: policy, provider: .qwenCloud,
                origin: origin, accountID: accountID, now: now)
            return [.init(id: accountID.uuidString, title: "Qwen Cloud", credential: try envelope.encoded())]
        }
    }
}

struct QwenCloudProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let usageAPI = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage"
    static let subscriptionAPI = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/subscription"

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        do {
            try WebProviderSession.validate(credential, provider: .qwenCloud, accountID: accountID,
                origins: [QwenCloudSession.origin], now: now())
            let cookies = try QwenCloudSession.policy.values(in: credential.accessToken)
            let token = try await securityToken(credential, cookies: cookies)
            let usage = try await send(Self.request(api: Self.usageAPI, token: token, cookie: credential.accessToken, cookies: cookies))
            var snapshot = try Self.snapshot(usage, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.sourceCredentialIdentity
            if snapshot.windows.isEmpty { return .init(snapshot: snapshot, updatedCredential: nil) }
            do {
                let response = try await send(Self.request(api: Self.subscriptionAPI, token: token,
                    cookie: credential.accessToken, cookies: cookies))
                let frame = try Self.payload(response)
                if let code = frame["specCode"] as? String {
                    snapshot.providerPlanName = ["lite", "standard", "pro", "max"].contains(code.lowercased()) ? code.capitalized : code
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                // Optional tier discovery cannot discard freshly reported quota.
            }
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private func securityToken(_ credential: ProviderCredentialEnvelope, cookies: [String: String]) async throws -> String {
        var pageFailure: (any Error)?
        var page = Self.get(QwenCloudSession.page, cookie: credential.accessToken)
        page.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let data = try await send(page)
            let html = String(decoding: data, as: UTF8.self)
            if Self.isSignIn(html) { throw RefreshFailure.invalidCredential }
            if let token = Self.securityToken(inPage: html) { return token }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            let failure = error as? RefreshFailure
            if failure == .invalidCredential || failure == .rateLimited { throw error }
            pageFailure = error
        }
        if let token = cookies["sec_token"], Self.validToken(token) { return token }
        let info = try await send(Self.get(URL(string: QwenCloudSession.origin + "/tool/user/info.json")!, cookie: credential.accessToken))
        let frame = try Self.payload(info)
        for key in ["secToken", "sec_token", "csrfToken"] {
            if let token = frame[key] as? String, Self.validToken(token) { return token }
        }
        throw pageFailure ?? RefreshFailure.invalidCredential
    }
    static func securityToken(inPage html: String) -> String? {
        for key in ["secToken", "sec_token", "csrfToken"] {
            let pattern = "[\\\"']?" + key + "[\\\"']?\\s*[:=]\\s*[\\\"']([^\\\"'\\r\\n]+)[\\\"']"
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let token = String(html[range])
            if validToken(token) { return token }
        }
        return nil
    }
    private static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 16_384 && token.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
    private static func isSignIn(_ html: String) -> Bool {
        let text = html.lowercased()
        return ["passport.alibabacloud.com", "signin.aliyun.com", "account.alibabacloud.com/login", "login.qwencloud.com"].contains(where: text.contains)
            || (text.contains("login") && text.contains("password") && text.contains("sign in"))
    }
    private static func get(_ url: URL, cookie: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(QwenCloudSession.origin, forHTTPHeaderField: "Origin")
        request.setValue(QwenCloudSession.page.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    static func request(api: String, token: String, cookie: String, cookies: [String: String]) throws -> URLRequest {
        guard [usageAPI, subscriptionAPI].contains(api), validToken(token) else { throw RefreshFailure.invalidCredential }
        var url = URLComponents(string: "https://cs-data.qwencloud.com/data/api.json")!
        url.queryItems = [.init(name: "action", value: "IntlBroadScopeAspnGateway"), .init(name: "product", value: "sfm_bailian"),
                         .init(name: "api", value: api), .init(name: "_v", value: "undefined")]
        var cornerstone = ["feTraceId": UUID().uuidString.lowercased(), "feURL": QwenCloudSession.page.absoluteString,
            "protocol": "V2", "console": "ONE_CONSOLE", "productCode": "p_efm", "domain": "home.qwencloud.com",
            "consoleSite": "QWENCLOUD", "userNickName": "", "userPrincipalName": "", "xsp_lang": "en-US"]
        cornerstone["X-Anonymous-Id"] = cookies["cna"]
        var data: [String: Any] = ["cornerstoneParam": cornerstone]
        if api == subscriptionAPI { data["commodityCode"] = "sfm_tokenplansolo_public_intl" }
        let params = try JSONSerialization.data(withJSONObject: ["Api": api, "V": "1.0", "Data": data], options: [.sortedKeys])
        var request = get(url.url!, cookie: cookie)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let csrf = cookies["login_aliyunid_csrf"] ?? cookies["csrf"] {
            guard validToken(csrf) else { throw RefreshFailure.invalidCredential }
            request.setValue(csrf, forHTTPHeaderField: "x-xsrf-token"); request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        let fields = [("product", "sfm_bailian"), ("action", "IntlBroadScopeAspnGateway"), ("sec_token", token),
                      ("region", "ap-southeast-1"), ("language", "en-US"), ("params", String(decoding: params, as: UTF8.self))]
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(fields.map { $0.0 + "=" + $0.1.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
        return request
    }
    private func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.url?.scheme == "https", response.url?.host == request.url?.host,
              response.url?.port == request.url?.port else { throw RefreshFailure.invalidCredential }
        if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
        if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
        guard data.count <= 2_097_152 else { throw RefreshFailure.unreadableResponse }
        return data
    }

    /// Only known console wrappers are expanded; unrelated nested objects are never searched for quota.
    static func payload(_ data: Data) throws -> [String: Any] {
        guard data.count <= 2_097_152 else { throw RefreshFailure.unreadableResponse }
        let text = String(decoding: data.prefix(4096), as: UTF8.self)
        if text.lowercased().contains("<html"), isSignIn(text) { throw RefreshFailure.invalidCredential }
        var object: Any = try ProviderHTTP.json(data)
        for _ in 0..<10 {
            if let string = object as? String { object = try ProviderHTTP.json(Data(string.utf8)) }
            guard let frame = object as? [String: Any] else { throw RefreshFailure.unreadableResponse }
            var failed = false
            for key in ["success", "successResponse", "Success"] {
                if let raw = frame[key] {
                    guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw RefreshFailure.unreadableResponse }
                    failed = failed || !value.boolValue
                }
            }
            for key in ["code", "Code", "httpStatus", "httpStatusCode"] {
                guard let raw = frame[key], !(raw is NSNull) else { continue }
                let value: String
                if let string = raw as? String { value = string.lowercased() }
                else if let number = HostedWebHTTP.numeric(raw) { value = String(number) }
                else { throw RefreshFailure.unreadableResponse }
                if !["0", "0.0", "200", "200.0", "success", "ok"].contains(value) { failed = true }
            }
            if failed {
                let detail = String(decoding: try JSONSerialization.data(withJSONObject: frame), as: UTF8.self).lowercased()
                if detail.contains("workspace.notauthorised") { throw RefreshFailure.server }
                if ["consoleneedlogin", "tokenerror", "refresh page", "请求已经过期", "notauthorized", "forbidden", "401", "403"].contains(where: detail.contains) { throw RefreshFailure.invalidCredential }
                throw RefreshFailure.server
            }
            if let nested = frame["DataV2"] ?? frame["data"] ?? frame["Data"], !(nested is NSNull) { object = nested }
            else { return frame }
        }
        throw RefreshFailure.unreadableResponse
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let frame = try payload(data)
        let definitions: [(String,String,QuotaPeriod)] = [("per5Hour", "5 小时额度", .fiveHour), ("per1Week", "每周额度", .weekly), ("per1Month", "每月额度", .monthly)]
        let windows = try definitions.compactMap { prefix, name, period -> QuotaWindow? in
            guard let raw = frame[prefix + "Percentage"] else { return nil }
            guard let ratio = HostedWebHTTP.numeric(raw), ratio >= 0, (ratio * 100).isFinite else { throw RefreshFailure.unreadableResponse }
            let reset = HostedWebHTTP.epoch(HostedWebHTTP.numeric(frame[prefix + "ResetTime"]), millisecondsOnly: true)
            if let reset, reset <= collectedAt { return nil }
            return .init(id: "qwenCloud." + prefix, name: name, scope: nil, period: period, isExhausted: ratio >= 1,
                usedPercentage: ratio * 100, remainingCount: nil, totalCount: nil, resetsAt: reset)
        }
        if windows.isEmpty, HostedWebHTTP.numeric(frame["TotalCount"] ?? frame["totalCount"]) == 0 {
            return .init(accountID: accountID, windows: [], collectedAt: collectedAt, quotaStatusText: "当前账号没有 Qwen Cloud 套餐")
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
