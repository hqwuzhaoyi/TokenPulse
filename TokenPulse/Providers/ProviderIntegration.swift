import Foundation

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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

struct ProviderQuotaClient: QuotaQuerying {
    let provider: Provider
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date

    init(provider: Provider,
         transport: any ProviderTransport = URLSessionProviderTransport(),
         now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.transport = transport
        self.now = now
    }

    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        try await quotaResult(for: accountID, credential: credential).snapshot
    }

    func quotaResult(for accountID: UUID, credential: String) async throws -> ProviderQueryResult {
        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
        switch provider {
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
        case .zai:
            return try await ZaiProviderClient(transport: transport, now: now)
                .quota(accountID: accountID, credential: envelope)
        case .superGrok:
            return try await SuperGrokProviderClient(transport: transport, now: now)
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
        case .zai:
            return .init(provider: provider, method: .apiKey, credentialLabel: "Z.ai Coding Plan Key")
        case .openCodeGo:
            return .init(provider: provider, method: .apiKey, credentialLabel: "OpenCode Go API Key")
        case .codex:
            return .init(provider: provider, method: .deviceCode, credentialLabel: nil)
        case .claude:
            return .init(provider: provider, method: .webSession, credentialLabel: nil)
        case .superGrok:
            return .init(provider: provider, method: .deviceCode, credentialLabel: nil)
        }
    }

    func credential(provider: Provider, apiKey: String) throws -> String {
        guard provider == .miniMaxChina || provider == .zai || provider == .openCodeGo else {
            throw ProviderIntegrationError.unsupportedLogin("该提供商不使用直接 Key 登录")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ProviderIntegrationError.invalidCredentialData }
        if provider == .miniMaxChina { return key }
        return try ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: key).encoded()
    }

    func beginLogin(provider: Provider, callbackURL: URL? = nil) async throws -> ProviderLoginSession {
        switch provider {
        case .codex:
            return try await CodexProviderAuthenticator(transport: transport, now: now).begin()
        case .superGrok:
            return try await SuperGrokProviderAuthenticator(transport: transport, now: now).begin()
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
        case .miniMaxChina, .openCodeGo, .zai:
            throw ProviderIntegrationError.unsupportedLogin("该提供商使用直接 Key 配置")
        }
    }

    func continueLogin(_ session: ProviderLoginSession, callbackURL: URL? = nil) async throws -> ProviderLoginProgress {
        switch session.provider {
        case .codex:
            return try await CodexProviderAuthenticator(transport: transport, now: now).poll(session)
        case .superGrok:
            return try await SuperGrokProviderAuthenticator(transport: transport, now: now).poll(session)
        case .claude, .miniMaxChina, .openCodeGo, .zai:
            throw ProviderIntegrationError.unsupportedLogin("该提供商没有可继续的设备授权流程")
        }
    }

    func refreshCredentialIfNeeded(provider: Provider, credential: String) async throws -> ProviderCredentialRefresh {
        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
        switch provider {
        case .codex:
            return try await CodexProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .superGrok:
            return try await SuperGrokProviderAuthenticator(transport: transport, now: now).refreshIfNeeded(envelope)
        case .claude, .miniMaxChina, .openCodeGo, .zai:
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
