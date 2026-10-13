import Foundation
import CoreFoundation

struct QoderChinaProviderClient: Sendable {
    static let origin = "https://qoder.com.cn"
    static let loginURL = URL(string: origin + "/account/usage")!
    static let analytics = ["_ga","_gid","_gat","_gcl","_fbp","_fbc","_clck","_clsk","_hj","_uet","_tt_","_ttp","ajs_","amp_","mp_","hm_","hmaccount","intercom-","__stripe","_rdt","_pin"]
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["qoder.com.cn"], path: "/api/v2/me/usages/big_model_credits", includeAllNames: true, deniedPrefixes: analytics)
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    static func credential(cookies: [HTTPCookie], accountID: UUID, now: Date) throws -> String {
        let filtered = cookies.filter { cookie in !analytics.contains { cookie.name.lowercased().hasPrefix($0) } }
        return try WebProviderSession.cookieCredential(cookies: filtered, policy: cookiePolicy,
            provider: .qoderChina, origin: origin, accountID: accountID, now: now).encoded()
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        let collectedAt = now()
        try WebProviderSession.validate(credential, provider: .qoderChina, accountID: accountID, origins: [Self.origin], now: collectedAt)
        let cookies = try Self.cookiePolicy.values(in: credential.accessToken)
        guard !cookies.keys.contains(where: { name in Self.analytics.contains { name.lowercased().hasPrefix($0) } }) else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: Self.origin + "/api/v2/me/usages/big_model_credits")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        for (name,value) in ["Cookie":credential.accessToken,"Accept":"application/json, text/plain, */*","Origin":Self.origin,
                            "Referer":Self.loginURL.absoluteString,"X-Requested-With":"XMLHttpRequest","Bx-V":"2.5.35",
                            "User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"] {
            request.setValue(value,forHTTPHeaderField:name)
        }
        do {
            let (data,response)=try await ProviderHTTP.send(request,transport:transport)
            if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
            if let failure=ProviderHTTP.queryFailure(status:response.statusCode) { throw failure }
            var snapshot=try Self.snapshot(data,accountID:accountID,collectedAt:collectedAt)
            snapshot.sourceCredentialFingerprint=try WebProviderSession.fingerprint(credential)
            return .init(snapshot:snapshot,updatedCredential:nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Key: CodingKey { let stringValue:String; var intValue:Int? {nil}; init(_ value:String){stringValue=value}; init?(stringValue:String){self.stringValue=stringValue};init?(intValue:Int){return nil} }
    private static func either<T:Decodable>(_ container:KeyedDecodingContainer<Key>,_ type:T.Type,_ camel:String,_ snake:String)throws->T? {
        for key in [camel,snake] { if let value=try container.decodeIfPresent(type,forKey:Key(key)) { return value } }
        return nil
    }
    private struct Summary:Decodable {
        let used:WalletDecimalValue;let total:WalletDecimalValue;let remaining:WalletDecimalValue?;let unit:String?
        init(from decoder:any Decoder)throws {
            let c=try decoder.container(keyedBy:Key.self)
            guard let used=try either(c,WalletDecimalValue.self,"usedValue","used_value"),let total=try either(c,WalletDecimalValue.self,"limitValue","limit_value") else {throw RefreshFailure.unreadableResponse}
            self.used=used;self.total=total;remaining=try either(c,WalletDecimalValue.self,"remainingValue","remaining_value")
            unit=try c.decodeIfPresent(String.self,forKey:Key("unit"))
        }
    }
    private struct Detail:Decodable {
        let remaining:WalletDecimalValue?;let expiry:Date?;let active:Bool?
        init(from decoder:any Decoder)throws {
            let c=try decoder.container(keyedBy:Key.self)
            remaining=try? either(c,WalletDecimalValue.self,"remainingValue","remaining_value")
            active=try? either(c,Bool.self,"isActive","is_active")
            expiry=(try? either(c,Time.self,"expiresAt","expires_at"))?.date
        }
    }
    private struct Container:Decodable {
        let summary:Summary;let details:[Detail]
        init(from decoder:any Decoder)throws {
            let c=try decoder.container(keyedBy:Key.self)
            guard let summary=try either(c,Summary.self,"quotaSummary","quota_summary") else {throw RefreshFailure.unreadableResponse}
            self.summary=summary;details=(try? either(c,[Detail].self,"quotaDetail","quota_detail")) ?? []
        }
    }
    private struct Time:Decodable {
        let date:Date?
        init(from decoder:any Decoder)throws {
            let c=try decoder.singleValueContainer()
            if let text=try? c.decode(String.self),let iso=ProviderHTTP.isoDate(text) {date=iso;return}
            let epoch:Double?
            if let text=try? c.decode(String.self) {epoch=Double(text)} else {epoch=try? c.decode(Double.self)}
            guard let epoch,epoch.isFinite,epoch>0 else {date=nil;return}
            let seconds=epoch>=1_000_000_000_000 ? epoch/1000:epoch
            guard Int64(exactly:(seconds*1000).rounded()) != nil else {date=nil;return}
            date=Date(timeIntervalSince1970:seconds)
        }
    }
    private struct Reply:Decodable {
        let personal:Container;let team:Container?;let reset:Date?
        init(from decoder:any Decoder)throws {
            let c=try decoder.container(keyedBy:Key.self)
            guard let personal=try either(c,Container.self,"totalQuota","total_quota") else {throw RefreshFailure.unreadableResponse}
            self.personal=personal;team=try either(c,Container.self,"sharedQuota","shared_quota")
            reset=(try? either(c,Time.self,"nextResetAt","next_reset_at"))?.date
        }
    }
    static func snapshot(_ data:Data,accountID:UUID,collectedAt:Date)throws->QuotaSnapshot {
        guard let reply=try? JSONDecoder().decode(Reply.self,from:data) else {throw RefreshFailure.unreadableResponse}
        var windows:[QuotaWindow]=[]
        for (bucket,id,name) in [(reply.personal,"personal","个人额度（含资源包）"),(reply.team,"team","团队额度")] {
            guard let bucket else {continue}
            let used=bucket.summary.used.amount,total=bucket.summary.total.amount,remaining=bucket.summary.remaining?.amount
            guard used>=0,total>=0,remaining.map({$0>=0}) != false else {throw RefreshFailure.unreadableResponse}
            guard total>0 else {continue}
            windows.append(.init(id:"qoderChina.\(id)",name:name,scope:nil,period:.other,
                isExhausted:remaining.map{$0==0} ?? (used>=total),usedPercentage:try WalletDecimalArithmetic.percentage(used:used,total:total),
                remainingCount:nil,totalCount:nil,resetsAt:id=="personal" ? reply.reset.flatMap{$0>collectedAt ? $0:nil}:nil,
                unit:bucket.summary.unit ?? "credits",exactCounts:.init(used:used,remaining:remaining ?? max(total-used,0),total:total),
                resetSemantics:.nonResettingAllowance))
        }
        // An expiry names a subset of the personal total. Show it separately;
        // never imply that the whole personal pool expires or resets then.
        let expiring=reply.personal.details.compactMap { detail -> (Date,Decimal)? in
            guard detail.active != false,let amount=detail.remaining?.amount,amount>0,let date=detail.expiry,date>collectedAt else {return nil}
            return (date,amount)
        }
        if let earliest=expiring.map(\.0).min() {
            let amount=try expiring.filter{$0.0==earliest}.map(\.1).reduce(Decimal.zero) {try WalletDecimalArithmetic.add($0,$1)}
            windows.append(.init(id:"qoderChina.expiring",name:"即将到期资源包（个人额度子集）",scope:nil,
                usedPercentage:nil,remainingCount:nil,totalCount:nil,resetsAt:nil,unit:"credits",expiresAt:earliest,
                exactCounts:.init(remaining:amount),resetSemantics:.nonResettingAllowance))
        }
        let hasQuota=windows.contains{$0.usedPercentage != nil}
        return .init(accountID:accountID,windows:windows,collectedAt:collectedAt,
                     quotaStatusText:hasQuota ? nil:"当前没有已授予的个人或团队 credits")
    }
}
