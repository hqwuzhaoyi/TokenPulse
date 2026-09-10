import Foundation

enum ProviderHTTP {
    static func send(_ request: URLRequest, transport: any ProviderTransport) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderIntegrationError.network
            }
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue {
                throw CancellationError()
            }
            if let integration = error as? ProviderIntegrationError { throw integration }
            throw ProviderIntegrationError.network
        }
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderIntegrationError.unreadableResponse
        }
        return root
    }

    static func queryFailure(status: Int) -> RefreshFailure? {
        switch status {
        case 200..<300: nil
        case 401, 403: .invalidCredential
        case 429: .rateLimited
        default: .server
        }
    }

    static func integrationFailure(status: Int) -> ProviderIntegrationError? {
        switch status {
        case 200..<300: nil
        case 401, 403: .invalidCredential
        case 429: .rateLimited
        default: .server
        }
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func isoDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func windowName(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "额度窗口" }
        return switch seconds {
        case 5 * 3_600: "5 小时额度"
        case 7 * 86_400: "每周额度"
        case 28 * 86_400...31 * 86_400: "每月额度"
        default: "\(max(seconds / 3_600, 1)) 小时额度"
        }
    }

    static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = values.sorted { $0.key < $1.key }.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    static func refreshFailure(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let failure = error as? RefreshFailure { return failure }
        guard let integration = error as? ProviderIntegrationError else { return RefreshFailure.network }
        return switch integration {
        case .invalidCredential, .invalidCredentialData, .loginExpired: RefreshFailure.invalidCredential
        case .rateLimited: RefreshFailure.rateLimited
        case .network: RefreshFailure.network
        case .unreadableResponse: RefreshFailure.unreadableResponse
        case .noQuotaWindows: RefreshFailure.noQuotaWindows
        default: RefreshFailure.server
        }
    }
}
