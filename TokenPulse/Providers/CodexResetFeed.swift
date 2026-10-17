import Foundation

actor CodexResetFeed {
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date
    private var cached: CodexResetStatus?
    private var lastRequestSucceeded = false
    private var etag: String?
    private var nextRequestAt = Date.distantPast
    private var inFlight: Task<CodexResetStatus, Error>?

    init(transport: any ProviderTransport = URLSessionProviderTransport(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    func status() async throws -> CodexResetStatus {
        if let inFlight { return try await inFlight.value }
        guard now() >= nextRequestAt else {
            if lastRequestSucceeded, let cached { return cached }
            throw URLError(.resourceUnavailable)
        }
        var request = URLRequest(url: URL(string: "https://codex-resets.com/api/v1/status")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        let task = Task { try await self.fetch(request) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func fetch(_ request: URLRequest) async throws -> CodexResetStatus {
        // One public request per five minutes, shared by all Codex accounts, including on failure.
        lastRequestSucceeded = false
        nextRequestAt = now().addingTimeInterval(300)
        let (data, rawResponse) = try await transport.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 304, let cached {
            lastRequestSucceeded = true
            return cached
        }
        if response.statusCode == 429 {
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
            if delay.isFinite { nextRequestAt = now().addingTimeInterval(max(300, delay)) }
        }
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let status = try CodexResetStatus.decode(data)
        lastRequestSucceeded = true
        cached = status
        etag = response.value(forHTTPHeaderField: "ETag")
        return status
    }
}
