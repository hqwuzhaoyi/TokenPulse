import Foundation
import CryptoKit

enum ProviderCredentialKind: String, Codable, Sendable {
    case apiKey
    case oauth
    case session
}

struct ProviderCredentialEnvelope: Codable, Equatable, Sendable {
    let provider: Provider
    let kind: ProviderCredentialKind
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var accountID: String?
    var metadata: [String: String]

    init(provider: Provider,
         kind: ProviderCredentialKind,
         accessToken: String,
         refreshToken: String? = nil,
         expiresAt: Date? = nil,
         accountID: String? = nil,
         metadata: [String: String] = [:]) {
        self.provider = provider
        self.kind = kind
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.metadata = metadata
    }

    func encoded() throws -> String {
        let data = try JSONEncoder.providerEncoder.encode(self)
        guard let value = String(data: data, encoding: .utf8) else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        return value
    }

    static func decode(_ value: String, expectedProvider: Provider) throws -> Self {
        guard let data = value.data(using: .utf8),
              let credential = try? JSONDecoder.providerDecoder.decode(Self.self, from: data),
              credential.provider == expectedProvider,
              !credential.accessToken.isEmpty else {
            throw ProviderIntegrationError.invalidCredentialData
        }
        return credential
    }
}

struct ProviderQueryResult: Equatable, Sendable {
    let snapshot: QuotaSnapshot
    /// Persist this value over the previous credential after a successful refresh.
    let updatedCredential: String?
}

enum ProviderLoginMethod: Equatable, Sendable {
    case apiKey
    case authorizationCode
    case deviceCode
    case webSession
    case unsupported(reason: String)
}

struct ProviderLoginConfiguration: Equatable, Sendable {
    let provider: Provider
    let method: ProviderLoginMethod
    let credentialLabel: String?
}

struct ProviderLoginSession: Codable, Equatable, Sendable {
    let provider: Provider
    let authorizationURL: URL
    let userCode: String?
    let deviceCode: String?
    let state: String?
    let codeVerifier: String?
    let callbackURL: URL?
    let pollingInterval: TimeInterval?
    let expiresAt: Date?
    let metadata: [String: String]
}

enum ProviderLoginProgress: Equatable, Sendable {
    case pending(retryAfter: TimeInterval)
    case completed(credential: String)
}

struct ProviderCredentialRefresh: Equatable, Sendable {
    let credential: String
    let changed: Bool
}

enum ProviderIntegrationError: Error, Equatable, Sendable {
    case unsupportedLogin(String)
    case invalidCredentialData
    case invalidCallback
    case loginExpired
    case loginPending(TimeInterval)
    case invalidCredential
    case rateLimited
    case network
    case server
    case unreadableResponse
    case noQuotaWindows
}

protocol ProviderTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionProviderTransport: ProviderTransport {
    let session: URLSession
    private let allowsSameOriginRedirects: Bool

    init(session: URLSession = .shared, allowsSameOriginRedirects: Bool = true) {
        self.session = session
        self.allowsSameOriginRedirects = allowsSameOriginRedirects
    }

    static func rejectingRedirects() -> Self {
        .init(session: URLSession(configuration: .ephemeral), allowsSameOriginRedirects: false)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request,
                               delegate: ProviderRedirectPolicy(origin: allowsSameOriginRedirects ? request.url : nil))
    }
}

struct ProviderQuotaClient: QuotaQuerying {
    let provider: Provider
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date

    init(provider: Provider,
         transport: (any ProviderTransport)? = nil,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        if let transport { self.transport = transport }
        else if provider.requiresGatewayAddress { self.transport = GatewayProviderTransport() }
        else if provider.webLoginProfile != nil || [.grokBot, .elevenLabs, .cursor, .volcengine, .xaiAPI, .ibmBob].contains(provider) { self.transport = URLSessionProviderTransport.rejectingRedirects() }
        else { self.transport = URLSessionProviderTransport() }
        self.now = now
    }

    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        try await quotaResult(for: accountID, credential: credential).snapshot
    }

    func quotaResult(for accountID: UUID, credential: String) async throws -> ProviderQueryResult {
        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
        switch provider {
        case .typeSafe:
            return try await TypeSafeProviderClient(transport: transport, now: now).quota(accountID: accountID, credential: envelope)
        case .qwenCloud:
            return try await QwenCloudProviderClient(transport: transport, now: now).quota(accountID: accountID, credential: envelope)
        case .raycastAI:
            return try await RaycastAIProviderClient(transport: transport, now: now).quota(accountID: accountID, credential: envelope)
        case .t3Chat:
            return try await T3ChatProviderClient(transport: transport, now: now).quota(accountID: accountID, credential: envelope)
        case .zoomMate:
            return try await ZoomMateProviderClient(transport: transport, now: now).quota(accountID: accountID, credential: envelope)
        case .miniMaxChina:
            throw ProviderIntegrationError.unsupportedLogin("MiniMax 由既有客户端处理")
        case .claude:
            return try await ClaudeProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .codex:
            return try await CodexProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .openCodeGo:
            return try await OpenCodeGoProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .miniMaxInternational:
            return try await MiniMaxInternationalProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .zai, .zhipu:
            return try await ZaiProviderClient(provider: provider, transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .superGrok:
            return try await SuperGrokProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .longCat:
            return try await LongCatProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .ollamaCloud:
            return try await OllamaCloudProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .qoderChina:
            return try await QoderChinaProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .xiaomiCodingPlan:
            return try await XiaomiCodingPlanProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .qoderInternational:
            return try await QoderProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .sakana:
            return try await SakanaProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .mistral:
            return try await MistralProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .replicate:
            return try await ReplicateProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .factory:
            return try await FactoryProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .huggingFace:
            return try await HuggingFaceProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .gitKraken:
            return try await GitKrakenProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .amp:
            return try await AmpProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .commandCode:
            return try await CommandCodeProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .zenMux:
            return try await ZenMuxProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .xKiro:
            return try await XKiroProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .v2ex:
            return try await V2EXProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .synthetic:
            return try await SyntheticProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .ibmBob:
            return try await IBMBobProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .xaiAPI:
            return try await XAIAPIProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .volcengine:
            return try await VolcengineProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .devPass:
            return try await DevPassProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .v0:
            return try await V0ProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .windsurf:
            return try await WindsurfProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .manus:
            return try await ManusProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .devin:
            return try await DevinProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .warp:
            return try await WarpProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .copilot:
            return try await CopilotProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .kimiCode:
            return try await KimiCodeProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .elevenLabs:
            return try await ElevenLabsProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .poe:
            return try await PoeProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .vercelAIGateway:
            return try await VercelAIGatewayProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .stepFun:
            return try await StepFunProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .llmProxy:
            return try await LLMProxyProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .liteLLM:
            return try await LiteLLMProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .bifrost:
            return try await BifrostProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .sub2api:
            return try await Sub2APIProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .newAPI:
            return try await NewAPIProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .codebuff:
            return try await CodebuffProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .neuralwatt:
            return try await NeuralwattProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .aixy:
            return try await AixyProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .clawRouter:
            return try await ClawRouterProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .clinePass:
            return try await ClinePassProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .moonshot:
            return try await MoonshotProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .atlasCloud:
            return try await AtlasCloudProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .kiloCode:
            return try await KiloCodeProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .deepInfra:
            return try await DeepInfraProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .hyper:
            return try await HyperProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .venice:
            return try await VeniceProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .grokBot:
            return try await GrokBotProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .zed:
            return try await ZedProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .augmentCode:
            return try await AugmentCodeProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .cursor:
            return try await CursorProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .chutes:
            return try await ChutesProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .alibabaCodingPlan:
            return try await AlibabaCodingPlanProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .abacus:
            return try await AbacusProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .perplexity:
            return try await PerplexityProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .notionAI:
            return try await NotionAIProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .deepSeek:
            return try await DeepSeekProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        }
    }
}

struct ProviderAuthenticationController: Sendable {
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date

    init(transport: any ProviderTransport = URLSessionProviderTransport(),
         now: @escaping @Sendable () -> Date = Date.init) {
        self.transport = transport
        self.now = now
    }

    func loginConfiguration(for provider: Provider) -> ProviderLoginConfiguration {
        switch provider {
        case .miniMaxChina:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Coding Plan Key")
        case .miniMaxInternational:
            return .init(provider: provider, method: .apiKey, credentialLabel: "MiniMax 国际版 Coding Plan Key")
        case .zhipu:
            return .init(provider: provider, method: .apiKey, credentialLabel: "智谱国内版 Coding Plan Key")
        case .zai:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Z.ai 国际版 Coding Plan Key")
        case .openCodeGo:
            return .init(provider: provider, method: .apiKey, credentialLabel: "OpenCode Go API Key")
        case .factory:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Factory API Key")
        case .huggingFace:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Hugging Face 用户 Token（需读取账单权限）")
        case .gitKraken:
            return .init(provider: provider, method: .apiKey, credentialLabel: "GitKraken 账户会话 Token")
        case .amp:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Amp Access Token")
        case .commandCode:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Command Code API Key")
        case .ibmBob:
            return .init(provider: provider, method: .apiKey, credentialLabel: "apikey:通用 Key 或 token:登录 JWT")
        case .xaiAPI:
            return .init(provider: provider, method: .apiKey, credentialLabel: "TeamID:ManagementKey")
        case .volcengine:
            return .init(provider: provider, method: .apiKey, credentialLabel: "AccessKeyID:SecretAccessKey")
        case .devPass:
            return .init(provider: provider, method: .apiKey, credentialLabel: "DevPass API Key")
        case .v0:
            return .init(provider: provider, method: .apiKey, credentialLabel: "v0 API Key")
        case .warp:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Warp API Key")
        case .llmProxy:
            return .init(provider: provider, method: .apiKey, credentialLabel: "LLM Proxy Key")
        case .liteLLM:
            return .init(provider: provider, method: .apiKey, credentialLabel: "LiteLLM 虚拟 Key（需读取预算权限）")
        case .bifrost:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Bifrost 虚拟 Key")
        case .sub2api:
            return .init(provider: provider, method: .apiKey, credentialLabel: "sub2api 分组 Key")
        case .newAPI:
            return .init(provider: provider, method: .apiKey, credentialLabel: "New API Key")
        case .codebuff:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Codebuff API Key")
        case .neuralwatt:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Neuralwatt API Key")
        case .aixy:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Aixy API Key")
        case .clawRouter:
            return .init(provider: provider, method: .apiKey, credentialLabel: "ClawRouter API Key")
        case .clinePass:
            return .init(provider: provider, method: .apiKey, credentialLabel: "ClinePass API Key")
        case .moonshot:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Moonshot 开放平台 API Key")
        case .atlasCloud:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Atlas Cloud API Key（需余额读取权限）")
        case .kiloCode:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Kilo Code API Key")
        case .deepInfra:
            return .init(provider: provider, method: .apiKey, credentialLabel: "DeepInfra API Key")
        case .hyper:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Hyper API Key")
        case .venice:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Venice API Key")
        case .chutes:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Chutes API Key")
        case .alibabaCodingPlan:
            return .init(provider: provider, method: .apiKey, credentialLabel: "百炼 Coding Plan Key（Key 查询兼容性待验证）")
        case .deepSeek:
            return .init(provider: provider, method: .apiKey, credentialLabel: "DeepSeek API Key")
        case .elevenLabs:
            return .init(provider: provider, method: .apiKey, credentialLabel: "ElevenLabs API Key（需 user_read 权限）")
        case .poe:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Poe API Key")
        case .synthetic:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Synthetic API Key")
        case .v2ex:
            return .init(provider: provider, method: .apiKey, credentialLabel: "V2EX Personal Access Token")
        case .xKiro:
            return .init(provider: provider, method: .apiKey, credentialLabel: "xKiro API Key")
        case .zenMux:
            return .init(provider: provider, method: .apiKey, credentialLabel: "ZenMux Management Key（非推理 Key）")
        case .vercelAIGateway:
            return .init(provider: provider, method: .apiKey, credentialLabel: "AI Gateway API Key")
        case .codex, .kimiCode, .copilot:
            return .init(provider: provider, method: .deviceCode, credentialLabel: nil)
        case .claude, .stepFun, .cursor, .raycastAI, .t3Chat, .zoomMate, .qwenCloud, .typeSafe, .devin, .manus, .windsurf, .replicate, .mistral, .sakana, .xiaomiCodingPlan, .qoderChina, .ollamaCloud, .longCat, .abacus, .perplexity, .notionAI, .augmentCode, .zed, .grokBot:
            return .init(provider: provider, method: .webSession, credentialLabel: nil)
        case .superGrok:
            return .init(provider: provider, method: .deviceCode, credentialLabel: nil)
        case .qoderInternational:
            return .init(provider: provider, method: .deviceCode, credentialLabel: nil)
        }
    }

    func credential(provider: Provider, apiKey: String, serverAddress: String? = nil, region: ProviderRegion? = nil, organizationID: String? = nil) throws -> String {
        if provider.requiresGatewayAddress { return try GatewayCredentials.make(provider: provider, key: apiKey, server: serverAddress ?? "").encoded() }
        if provider == .ibmBob { return try IBMBobCredential(apiKey).envelope().encoded() }
        if provider == .xaiAPI { return try XAIManagementCredential(apiKey).envelope().encoded() }
        if provider == .volcengine { return try VolcengineAccessKeys(apiKey).envelope().encoded() }
        if provider == .gitKraken {
            var envelope = try GitKrakenSessionCredential.envelope(token: apiKey, organizationID: organizationID)
            let identityData = try JSONEncoder().encode([provider.rawValue, envelope.accessToken, envelope.metadata["organizationID"] ?? ""])
            envelope.metadata["sourceCredentialFingerprint"] = SHA256.hash(data: identityData).map { String(format: "%02x", $0) }.joined()
            return try envelope.encoded()
        }
        guard provider == .miniMaxChina || provider == .zai || provider == .openCodeGo || provider == .deepSeek || provider == .elevenLabs || provider == .poe || provider == .vercelAIGateway || provider == .miniMaxInternational || provider == .zhipu || provider == .newAPI || provider == .moonshot || provider == .clinePass || provider == .factory || provider == .codebuff || provider == .neuralwatt || provider == .aixy || provider == .clawRouter || [.atlasCloud, .kiloCode, .deepInfra, .hyper, .venice].contains(provider) || [.commandCode, .amp, .huggingFace].contains(provider) || [.synthetic, .v2ex, .xKiro, .zenMux].contains(provider) || [.alibabaCodingPlan, .chutes].contains(provider) || [.devPass, .v0, .warp].contains(provider) else {
            throw ProviderIntegrationError.unsupportedLogin("该提供商不使用直接 Key 登录")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ProviderIntegrationError.invalidCredentialData }
        if provider == .miniMaxChina { return key }
        if provider.requiresRegion, region == nil { throw ProviderIntegrationError.invalidCredentialData }
        var metadata: [String: String] = provider == .newAPI
            ? ["serverAddress": try GatewayServerAddress(serverAddress ?? "").value]
            : provider.requiresRegion ? ["region": region!.rawValue] : [:]
        if [.clinePass, .codebuff, .neuralwatt, .aixy, .clawRouter].contains(provider) {
            metadata["sourceCredentialFingerprint"] = try KeyQuotaRequest.fingerprint(provider: provider, key: key)
        }
        if provider == .commandCode || provider == .amp || provider == .huggingFace {
            let identityData = try JSONEncoder().encode([provider.rawValue, key])
            metadata["sourceCredentialFingerprint"] = SHA256.hash(data: identityData).map { String(format: "%02x", $0) }.joined()
        }
        var credential = ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: key, metadata: metadata)
        if [Provider.synthetic, .v2ex, .xKiro, .zenMux].contains(provider) {
            guard let fingerprint = credential.apiKeySourceFingerprint else { throw ProviderIntegrationError.invalidCredentialData }
            credential.metadata["sourceCredentialFingerprint"] = fingerprint
        }
        return try credential.encoded()
    }

    func beginLogin(provider: Provider, callbackURL: URL? = nil) async throws -> ProviderLoginSession {
        switch provider {
        case .copilot:
            return try await CopilotProviderAuthenticator(transport: transport, now: now).begin()
        case .kimiCode:
            return try await KimiCodeProviderAuthenticator(transport: transport, now: now).begin()
        case .codex:
            return try await CodexProviderAuthenticator(transport: transport, now: now).begin()
        case .superGrok:
            return try await SuperGrokProviderAuthenticator(transport: transport, now: now).begin()
        case .qoderInternational:
            return try QoderProviderAuthenticator(transport: transport, now: now).begin()
        case .claude:
            return ProviderLoginSession(
                provider: .claude,
                authorizationURL: URL(string: "https://claude.ai/login")!,
                userCode: nil,
                deviceCode: nil,
                state: nil,
                codeVerifier: nil,
                callbackURL: callbackURL,
                pollingInterval: nil,
                expiresAt: nil,
                metadata: ["completion": "ClaudeSessionLoginView"]
            )
        case .grokBot:
            throw ProviderIntegrationError.unsupportedLogin("请在账号专用浏览器中通过 Cursor 账号授权 Grok Bot")
        case .zed:
            throw ProviderIntegrationError.unsupportedLogin("请在此账号的临时浏览器中登录 Zed 网页账户")
        case .augmentCode:
            throw ProviderIntegrationError.unsupportedLogin("请在此账号的临时浏览器中登录 Augment Code")
        case .windsurf:
            throw ProviderIntegrationError.unsupportedLogin("请在账号专用临时浏览器中登录 Windsurf")
        case .manus:
            throw ProviderIntegrationError.unsupportedLogin("请在账号专用临时浏览器中登录 Manus")
        case .devin:
            throw ProviderIntegrationError.unsupportedLogin("请在账号专用临时浏览器中登录 Devin 并选择组织")
        case .xiaomiCodingPlan, .qoderChina, .ollamaCloud, .longCat:
            throw ProviderIntegrationError.unsupportedLogin("请在隔离控制台浏览器中登录")
        case .cursor, .abacus, .perplexity, .notionAI:
            throw ProviderIntegrationError.unsupportedLogin("请在账号专用临时浏览器中完成登录")
        case .replicate, .mistral, .sakana, .stepFun, .raycastAI, .t3Chat, .zoomMate, .qwenCloud, .typeSafe:
            throw ProviderIntegrationError.unsupportedLogin("请在账号专用浏览器中选择站点并登录")
        case .miniMaxChina, .openCodeGo, .zai, .deepSeek, .elevenLabs, .poe, .vercelAIGateway, .miniMaxInternational, .zhipu, .newAPI, .sub2api, .bifrost, .liteLLM, .llmProxy, .clinePass, .moonshot, .factory, .codebuff, .neuralwatt, .aixy, .clawRouter, .atlasCloud, .kiloCode, .deepInfra, .hyper, .venice, .commandCode, .amp, .gitKraken, .huggingFace, .synthetic, .v2ex, .xKiro, .zenMux, .alibabaCodingPlan, .chutes, .volcengine, .xaiAPI, .ibmBob, .devPass, .v0, .warp:
            throw ProviderIntegrationError.unsupportedLogin("该提供商使用直接 Key 配置")
        }
    }

    func continueLogin(_ session: ProviderLoginSession, callbackURL: URL? = nil) async throws -> ProviderLoginProgress {
        switch session.provider {
        case .replicate, .mistral, .sakana:
            throw ProviderIntegrationError.unsupportedLogin("Use the account-isolated web login view")
        case .copilot:
            return try await CopilotProviderAuthenticator(transport: transport, now: now).poll(session)
        case .kimiCode:
            return try await KimiCodeProviderAuthenticator(transport: transport, now: now).poll(session)
        case .codex:
            return try await CodexProviderAuthenticator(transport: transport, now: now).poll(session)
        case .superGrok:
            return try await SuperGrokProviderAuthenticator(transport: transport, now: now).poll(session)
        case .qoderInternational:
            return try await QoderProviderAuthenticator(transport: transport, now: now).poll(session)
        case .typeSafe, .qwenCloud, .raycastAI, .t3Chat, .zoomMate, .claude, .miniMaxChina, .openCodeGo, .zai, .deepSeek, .elevenLabs, .poe, .vercelAIGateway, .miniMaxInternational, .zhipu, .stepFun, .newAPI, .clinePass, .moonshot, .factory, .codebuff, .neuralwatt, .aixy, .clawRouter, .atlasCloud, .kiloCode, .deepInfra, .hyper, .venice, .commandCode, .amp, .gitKraken, .huggingFace, .synthetic, .v2ex, .xKiro, .zenMux, .alibabaCodingPlan, .chutes, .cursor, .volcengine, .xaiAPI, .ibmBob, .devPass, .v0, .warp, .devin, .manus, .windsurf, .sub2api, .bifrost, .liteLLM, .llmProxy, .xiaomiCodingPlan, .qoderChina, .ollamaCloud, .longCat, .abacus, .perplexity, .notionAI, .augmentCode, .zed, .grokBot:
            throw ProviderIntegrationError.unsupportedLogin("该提供商没有可继续的设备授权流程")
        }
    }

    func refreshCredentialIfNeeded(provider: Provider, credential: String) async throws -> ProviderCredentialRefresh {
        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
        switch provider {
        case .copilot:
            return try CopilotProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .kimiCode:
            return try await KimiCodeProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .codex:
            return try await CodexProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .superGrok:
            return try await SuperGrokProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .qoderInternational:
            return try QoderProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .typeSafe, .qwenCloud, .raycastAI, .t3Chat, .zoomMate, .claude, .miniMaxChina, .openCodeGo, .zai, .deepSeek, .elevenLabs, .poe, .vercelAIGateway, .miniMaxInternational, .zhipu, .stepFun, .newAPI, .clinePass, .moonshot, .factory, .codebuff, .neuralwatt, .aixy, .clawRouter, .atlasCloud, .kiloCode, .deepInfra, .hyper, .venice, .commandCode, .amp, .gitKraken, .huggingFace, .synthetic, .v2ex, .xKiro, .zenMux, .alibabaCodingPlan, .chutes, .cursor, .volcengine, .xaiAPI, .ibmBob, .devPass, .v0, .warp, .devin, .manus, .windsurf, .replicate, .mistral, .sakana, .sub2api, .bifrost, .liteLLM, .llmProxy, .xiaomiCodingPlan, .qoderChina, .ollamaCloud, .longCat, .abacus, .perplexity, .notionAI, .augmentCode, .zed, .grokBot:
            return .init(credential: credential, changed: false)
        }
    }
}

extension JSONEncoder {
    fileprivate static var providerEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var providerDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
