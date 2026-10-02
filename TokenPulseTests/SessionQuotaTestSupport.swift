import Foundation
import XCTest
@testable import TokenPulse

actor SessionQuotaTransport: ProviderTransport {
    private var replies: [(Int, String)]
    private var received: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        received.append(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { received }
}

func sessionQuotaCookie(_ name: String, value: String = "fixture-value", domain: String, expires: Date? = nil) -> HTTPCookie {
    var fields: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"]
    if let expires { fields[.expires] = expires }
    return HTTPCookie(properties: fields)!
}
