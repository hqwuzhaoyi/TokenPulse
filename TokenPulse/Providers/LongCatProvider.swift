import Foundation

struct LongCatProviderClient:Sendable {
    static let origin="https://longcat.chat"
    static let loginURL=URL(string:origin+"/platform/usage")!
    static let cookiePolicy=CookieWebSessionPolicy(domains:["longcat.chat"],path:"/api/",names:["passport_token","uid"],requiredNames:["passport_token"])
    let transport:any ProviderTransport
    let now:@Sendable()->Date
    static func credential(cookies:[HTTPCookie],accountID:UUID,now:Date)throws->String {
        try WebProviderSession.cookieCredential(cookies:cookies,policy:cookiePolicy,provider:.longCat,origin:origin,accountID:accountID,now:now).encoded()
    }
    func quota(accountID:UUID,credential:ProviderCredentialEnvelope)async throws->ProviderQueryResult {
        let date=now()
        try WebProviderSession.validate(credential,provider:.longCat,accountID:accountID,origins:[Self.origin],now:date)
        _ = try Self.cookiePolicy.values(in:credential.accessToken)
        do {
            // Required authentication proof. Its phone/session response is
            // checked then discarded; it is never copied into stored state.
            _ = try await ask("/api/v1/user-current",credential:credential)
            let packs=try await optional("/api/pay/quota/metering/token-packs/summary",method:"POST",credential:credential)
            let active=Self.activeLot(packs)
            let usage:Data?
            if active == nil {usage=try await ask("/api/lc-platform/v1/tokenUsage",credential:credential)}else{usage=nil}
            let fuel=try await optional("/api/lc-platform/v1/pending-fuel-packages",credential:credential)
            var snapshot=try Self.snapshot(packs:packs,usage:usage,fuel:fuel,accountID:accountID,collectedAt:date)
            snapshot.sourceCredentialFingerprint=try WebProviderSession.fingerprint(credential)
            return .init(snapshot:snapshot,updatedCredential:nil)
        }catch{throw ProviderHTTP.refreshFailure(error)}
    }
    private func optional(_ path:String,method:String="GET",credential:ProviderCredentialEnvelope)async throws->Data? {
        do{return try await ask(path,method:method,credential:credential)}catch is CancellationError{throw CancellationError()}catch{return nil}
    }
    private func ask(_ path:String,method:String="GET",credential:ProviderCredentialEnvelope)async throws->Data {
        var request=URLRequest(url:URL(string:Self.origin+path)!)
        request.httpMethod=method;request.timeoutInterval=15;request.cachePolicy = .reloadIgnoringLocalCacheData;request.httpShouldHandleCookies=false
        if method=="POST" {request.httpBody=Data("{}".utf8);request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        for(name,value)in ["Cookie":credential.accessToken,"Accept":"application/json, text/plain, */*","Origin":Self.origin,"Referer":Self.loginURL.absoluteString]{request.setValue(value,forHTTPHeaderField:name)}
        let(data,response)=try await ProviderHTTP.send(request,transport:transport)
        if (300..<400).contains(response.statusCode){throw RefreshFailure.invalidCredential}
        if let failure=ProviderHTTP.queryFailure(status:response.statusCode){throw failure}
        let frame=try Self.decode(Frame<Empty>.self,data:data);try Self.check(frame.code)
        guard frame.data != nil else{throw RefreshFailure.unreadableResponse}
        return data
    }
    private struct Empty:Decodable {}
    private struct Frame<T:Decodable>:Decodable {let code:Int;let data:T?}
    private struct Pack:Decodable {let currentLot:Lot?}
    private struct Lot:Decodable {let status:String?;let totalToken:WalletDecimalValue?;let consumedToken:WalletDecimalValue?}
    private struct Meter:Decodable {let totalToken:WalletDecimalValue?;let usedToken:WalletDecimalValue?;let availableToken:WalletDecimalValue?}
    private struct Usage:Decodable {
        let usage:Meter?;let totalToken:WalletDecimalValue?;let usedToken:WalletDecimalValue?;let availableToken:WalletDecimalValue?
        var meter:Meter {usage ?? .init(totalToken:totalToken,usedToken:usedToken,availableToken:availableToken)}
    }
    private struct Expiry:Decodable {
        let date:Date?
        init(from decoder:any Decoder)throws {
            let c=try decoder.singleValueContainer()
            if let text=try? c.decode(String.self),let iso=ProviderHTTP.isoDate(text){date=iso;return}
            let value=(try? c.decode(Double.self)) ?? (try? c.decode(String.self)).flatMap(Double.init)
            if let value,value.isFinite,value>0 {
                let seconds=value>=1_000_000_000_000 ? value/1000:value
                date=Int64(exactly:(seconds*1000).rounded()) == nil ? nil:Date(timeIntervalSince1970:seconds);return
            }
            if let text=try? c.decode(String.self) {
                let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd HH:mm:ss";formatter.isLenient=false
                if let parsed=formatter.date(from:text),formatter.string(from:parsed)==text{date=parsed;return}
            }
            date=nil
        }
    }
    private struct Fuel:Decodable {
        struct Entry:Decodable {let availableToken:WalletDecimalValue?;let expireTime:Expiry?}
        let totalQuota:WalletDecimalValue?;let list:[Entry]?
    }
    private static func activeLot(_ data:Data?)->Lot? {
        guard let data,let frame=try? decode(Frame<Pack>.self,data:data),[0,200].contains(frame.code),let lot=frame.data?.currentLot,
              lot.status?.uppercased()=="ACTIVE",let total=lot.totalToken?.amount,total>0 else{return nil}
        return lot
    }
    static func snapshot(packs:Data?,usage:Data?,fuel:Data?,accountID:UUID,collectedAt:Date)throws->QuotaSnapshot {
        var windows:[QuotaWindow]=[],status:String?
        if let lot=activeLot(packs),let total=lot.totalToken?.amount {
            let used=lot.consumedToken?.amount
            if let used,used<0{throw RefreshFailure.unreadableResponse}
            windows.append(try tokens(id:"tokens",name:"当前 Token 包",used:used,total:total,remaining:used.map{max(total-$0,0)}))
            if used==nil{status="当前 Token 包未提供消耗量"}
        } else if let usage {
            let frame=try decode(Frame<Usage>.self,data:usage);try check(frame.code)
            guard let meter=frame.data?.meter,let total=meter.totalToken?.amount,total>=0 else{throw RefreshFailure.unreadableResponse}
            if total>0 {
                let available=meter.availableToken?.amount
                guard available.map({$0>=0 && $0<=total}) != false,(meter.usedToken?.amount).map({$0>=0}) != false else{throw RefreshFailure.unreadableResponse}
                let used=meter.usedToken?.amount ?? available.map{total-$0}
                windows.append(try tokens(id:"tokens",name:"账户 Token 额度",used:used,total:total,remaining:available ?? used.map{max(total-$0,0)}))
                if used==nil{status="账户 Token 用量未提供"}
            }
        } else{throw RefreshFailure.unreadableResponse}
        if let fuel,let frame=try? decode(Frame<Fuel>.self,data:fuel),[0,200].contains(frame.code),let payload=frame.data,let total=payload.totalQuota?.amount,total>0 {
            let entries=payload.list ?? []
            let values=entries.compactMap{$0.availableToken?.amount}
            let complete = !entries.isEmpty && values.count==entries.count && values.allSatisfy{$0>=0}
            let remaining=complete ? try values.reduce(Decimal.zero){try WalletDecimalArithmetic.add($0,$1)}:nil
            // An unknown member is unknown aggregate consumption, not zero.
            let used=remaining.flatMap{$0<=total ? total-$0:nil}
            windows.append(try tokens(id:"fuel",name:"补充燃料包总额",used:used,total:total,remaining:remaining))
            let expiries=entries.compactMap {entry->(Date,Decimal)? in
                guard let date=entry.expireTime?.date,date>collectedAt,let amount=entry.availableToken?.amount,amount>0 else{return nil};return(date,amount)
            }
            if let earliest=expiries.map(\.0).min() {
                let amount=try expiries.filter{$0.0==earliest}.map(\.1).reduce(Decimal.zero){try WalletDecimalArithmetic.add($0,$1)}
                windows.append(.init(id:"longcat.fuel.expiring",name:"即将到期燃料包（补充包子集）",scope:nil,usedPercentage:nil,
                    remainingCount:nil,totalCount:nil,resetsAt:nil,unit:"tokens",expiresAt:earliest,exactCounts:.init(remaining:amount),resetSemantics:.nonResettingAllowance))
            }
        }
        if windows.isEmpty{status=fuel == nil ? "主 Token 额度未授予；补充包本次未取得":"当前没有已授予的 Token 包或燃料包"}
        else if fuel == nil {status=status.map{$0+"；补充燃料包本次未取得"} ?? "补充燃料包本次未取得"}
        return .init(accountID:accountID,windows:windows,collectedAt:collectedAt,quotaStatusText:status)
    }
    private static func tokens(id:String,name:String,used:Decimal?,total:Decimal,remaining:Decimal?)throws->QuotaWindow {
        .init(id:"longcat.\(id)",name:name,scope:nil,period:.other,isExhausted:remaining.map{$0==0} ?? used.map{$0>=total},
              usedPercentage:try used.map{try WalletDecimalArithmetic.percentage(used:$0,total:total)},remainingCount:nil,totalCount:nil,resetsAt:nil,
              unit:"tokens",exactCounts:.init(used:used,remaining:remaining,total:total),resetSemantics:.nonResettingAllowance)
    }
    private static func check(_ code:Int)throws {
        switch code{case 0,200:return;case 401,403:throw RefreshFailure.invalidCredential;case 429:throw RefreshFailure.rateLimited;default:throw RefreshFailure.server}
    }
    private static func decode<T:Decodable>(_ type:T.Type,data:Data)throws->T {
        guard let value=try? JSONDecoder().decode(type,from:data) else{throw RefreshFailure.unreadableResponse};return value
    }
}
