import Foundation

/// Explicit session headers must never travel to an unrelated origin on a redirect.
final class ProviderRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    let origin: URL?
    init(origin: URL?) { self.origin = origin }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.permits(origin: origin, target: request.url) ? request : nil)
    }

    static func permits(origin: URL?, target: URL?) -> Bool {
        guard let origin, let target else { return false }
        return origin.scheme == target.scheme && origin.host == target.host && origin.port == target.port
    }
}
