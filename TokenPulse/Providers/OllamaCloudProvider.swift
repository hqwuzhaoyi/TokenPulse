import Foundation

struct OllamaCloudProviderClient:Sendable {
    static let origin="https://ollama.com"
    static let loginURL=URL(string:origin+"/settings")!
    static let cookieNames=["wos-session","__Secure-session","__Secure-next-auth.session-token","next-auth.session-token"]
    static let cookiePolicy=CookieWebSessionPolicy(domains:["ollama.com"],path:"/settings",names:cookieNames,prefixes:cookieNames.map{$0+"."})
    let transport:any ProviderTransport
    let now:@Sendable()->Date

    static func recognizes(_ name:String)->Bool {
        cookieNames.contains {base in
            if name==base{return true}
            guard name.hasPrefix(base+".") else{return false}
            let suffix=name.dropFirst(base.count+1)
            return !suffix.isEmpty && suffix.utf8.allSatisfy{(48...57).contains($0)}
        }
    }
    static func credential(cookies:[HTTPCookie],accountID:UUID,now:Date)throws->String {
        try WebProviderSession.cookieCredential(cookies:cookies.filter{recognizes($0.name)},policy:cookiePolicy,
            provider:.ollamaCloud,origin:origin,accountID:accountID,now:now).encoded()
    }
    func quota(accountID:UUID,credential:ProviderCredentialEnvelope)async throws->ProviderQueryResult {
        let collectedAt=now()
        try WebProviderSession.validate(credential,provider:.ollamaCloud,accountID:accountID,origins:[Self.origin],now:collectedAt)
        let values=try Self.cookiePolicy.values(in:credential.accessToken)
        guard !values.isEmpty,values.keys.allSatisfy(Self.recognizes) else{throw RefreshFailure.invalidCredential}
        var request=URLRequest(url:Self.loginURL)
        request.httpMethod="GET";request.timeoutInterval=20;request.cachePolicy = .reloadIgnoringLocalCacheData;request.httpShouldHandleCookies=false
        request.setValue(credential.accessToken,forHTTPHeaderField:"Cookie")
        request.setValue("text/html",forHTTPHeaderField:"Accept")
        request.setValue("en-US,en;q=0.9",forHTTPHeaderField:"Accept-Language")
        do {
            let(data,response)=try await ProviderHTTP.send(request,transport:transport)
            if (300..<400).contains(response.statusCode){throw RefreshFailure.invalidCredential}
            if let failure=ProviderHTTP.queryFailure(status:response.statusCode){throw failure}
            guard response.url?.scheme=="https",response.url?.host=="ollama.com",response.url?.path=="/settings",response.mimeType=="text/html" else{throw RefreshFailure.unreadableResponse}
            return .init(snapshot:.init(accountID:accountID,windows:try OllamaUsagePage.windows(data),collectedAt:collectedAt,
                sourceCredentialFingerprint:try WebProviderSession.fingerprint(credential)),updatedCredential:nil)
        }catch{throw ProviderHTTP.refreshFailure(error)}
    }
}

/// A bounded, non-executing parser for the two visible settings-page meters.
/// It runs on iOS/watchOS without macOS-only XMLDocument or an external parser.
enum OllamaUsagePage {
    private final class Node {
        let tag:String;let attrs:[String:String];let hidden:Bool
        weak var parent:Node?
        var children:[Node]=[];var texts:[String]=[]
        init(_ tag:String,_ attrs:[String:String]=[:],parent:Node?=nil){self.tag=tag;self.attrs=attrs;self.parent=parent;hidden=(parent?.hidden ?? false)||["script","style","template"].contains(tag)}
        var descendants:[Node] {var found:[Node]=[],pending=[self];while let node=pending.popLast(){found.append(node);pending.append(contentsOf:node.children)};return found}
        var visibleTexts:[String]{descendants.filter{!$0.hidden}.flatMap(\.texts)}
    }
    static let maximumBytes=2*1024*1024
    static func windows(_ data:Data)throws->[QuotaWindow] {
        guard data.count<=maximumBytes,let html=String(data:data,encoding:.utf8),!html.localizedCaseInsensitiveContains("<!ENTITY") else{throw RefreshFailure.unreadableResponse}
        let root=try tree(html)
        let nodes=root.descendants.filter{!$0.hidden}
        if nodes.contains(where:{$0.tag=="form" && (($0.attrs["action"] ?? "").lowercased().contains("signin")||($0.attrs["action"] ?? "").lowercased().contains("login"))}){throw RefreshFailure.invalidCredential}
        return try [("Session usage","ollama.session","会话额度",QuotaPeriod.fiveHour),("Weekly usage","ollama.weekly","每周额度",QuotaPeriod.weekly)].map {label,id,name,period in
            let labels=nodes.filter{$0.texts.contains{normalized($0)==label}}
            guard labels.count==1,let labelNode=labels.first else{throw RefreshFailure.unreadableResponse}
            let other=label=="Session usage" ? "Weekly usage":"Session usage"
            var container=labelNode.parent,result:(Double,Date?)?
            while let node=container {
                if node.visibleTexts.contains(where:{normalized($0)==other}){break}
                let percentages=try node.visibleTexts.compactMap(percent)
                guard percentages.count<=1 else{throw RefreshFailure.unreadableResponse}
                if let value=percentages.first {
                    let times=node.descendants.filter{!$0.hidden}.compactMap{$0.attrs["data-time"]}
                    guard times.count<=1 else{throw RefreshFailure.unreadableResponse}
                    let date:Date?
                    if let time=times.first {guard let parsed=ProviderHTTP.isoDate(time) else{throw RefreshFailure.unreadableResponse};date=parsed}else{date=nil}
                    result=(value,date)
                    if node.attrs["data-usage-meter"] != nil{break}
                }
                container=node.parent
            }
            guard let result else{throw RefreshFailure.unreadableResponse}
            return .init(id:id,name:name,scope:nil,period:period,isExhausted:result.0>=100,usedPercentage:result.0,
                         remainingCount:nil,totalCount:nil,resetsAt:result.1)
        }
    }
    private static func normalized(_ text:String)->String {decode(text).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")}
    private static func percent(_ text:String)throws->Double? {
        let text=decode(text)
        let regex=try NSRegularExpression(pattern:#"^\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*used\s*$"#,options:.caseInsensitive)
        guard let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(match.range(at:1),in:text),let value=Double(text[range]) else{return nil}
        guard value.isFinite,(0...100).contains(value) else{throw RefreshFailure.unreadableResponse}
        return value
    }
    private static func decode(_ text:String)->String {
        var text=text
        for (entity,value) in [("&nbsp;"," "),("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'")] {text=text.replacingOccurrences(of:entity,with:value)}
        return text
    }
    private static func tree(_ html:String)throws->Node {
        let root=Node("root"),voidTags:Set<String>=["area","base","br","col","embed","hr","img","input","link","meta","param","source","track","wbr"]
        var stack=[root],index=html.startIndex,count=0
        let tagName=try NSRegularExpression(pattern:#"^<\s*(/?)\s*([A-Za-z][A-Za-z0-9:-]*)"#)
        let attr=try NSRegularExpression(pattern:#"([A-Za-z_:][A-Za-z0-9_:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s/>]+)))?"#)
        while index<html.endIndex {
            if let tag=stack.last?.tag,["script","style"].contains(tag) {
                guard let end=html.range(of:"</"+tag,options:.caseInsensitive,range:index..<html.endIndex) else{break}
                index=end.lowerBound
            }
            if html[index] != "<" {
                let end=html[index...].firstIndex(of:"<") ?? html.endIndex
                stack.last?.texts.append(String(html[index..<end]));index=end;continue
            }
            if html[index...].hasPrefix("<!--") {
                guard let end=html.range(of:"-->",range:index..<html.endIndex) else{throw RefreshFailure.unreadableResponse}
                index=end.upperBound;continue
            }
            var end=html.index(after:index),quote:Character?
            while end<html.endIndex {
                let char=html[end]
                if let current=quote {if char==current{quote=nil}}
                else if char=="\"" || char=="'"{quote=char}
                else if char==">"{break}
                end=html.index(after:end)
            }
            guard end<html.endIndex else{throw RefreshFailure.unreadableResponse}
            let raw=String(html[index...end]);index=html.index(after:end)
            guard let match=tagName.firstMatch(in:raw,range:NSRange(raw.startIndex...,in:raw)),let nameRange=Range(match.range(at:2),in:raw) else{continue}
            let tag=raw[nameRange].lowercased()
            if match.range(at:1).length>0 {
                if let position=stack.lastIndex(where:{$0.tag==tag}) {
                    // A malformed template cannot close a visible ancestor and
                    // expose fake scripted counters to the meter selector.
                    if let barrier=stack.lastIndex(where:{$0.tag=="template"}),position<barrier{throw RefreshFailure.unreadableResponse}
                    stack=Array(stack.prefix(position))
                }
                continue
            }
            guard stack.count<128,count<50_000,let parent=stack.last else{throw RefreshFailure.unreadableResponse}
            var attrs:[String:String]=[:]
            let tail=String(raw[nameRange.upperBound...])
            for item in attr.matches(in:tail,range:NSRange(tail.startIndex...,in:tail)) {
                guard let key=Range(item.range(at:1),in:tail) else{continue}
                let name=tail[key].lowercased();guard attrs[name]==nil else{throw RefreshFailure.unreadableResponse}
                let value=(2...4).compactMap{part in Range(item.range(at:part),in:tail).map{decode(String(tail[$0]))}}.first ?? ""
                attrs[name]=value
            }
            let node=Node(tag,attrs,parent:parent);parent.children.append(node);count+=1
            if !voidTags.contains(tag),!raw.hasSuffix("/>"){stack.append(node)}
        }
        return root
    }
}
