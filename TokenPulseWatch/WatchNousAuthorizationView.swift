import SwiftUI

struct WatchNousAuthorizationView: View {
    let accountID: UUID
    let expectedIdentity: String
    let completion: (String) -> Void
    @StateObject private var login: NousDeviceLoginModel
    @Environment(\.dismiss) private var dismiss
    init(accountID: UUID, expectedIdentity: String, loginModel: NousDeviceLoginModel? = nil,
         completion: @escaping (String) -> Void) {
        self.accountID = accountID
        self.expectedIdentity = expectedIdentity
        self.completion = completion
        _login = StateObject(wrappedValue: loginModel ?? NousDeviceLoginModel())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("连接此 Watch").font(.headline)
                Text("请用与 iPhone 上相同的 Nous 账号授权。授权页可能显示 Hermes CLI。")
                    .font(.caption2).foregroundStyle(.secondary)
                if let session = login.session {
                    if let code = session.userCode {
                        Text(code).font(.title3.monospaced()).bold()
                            .lineLimit(1).minimumScaleFactor(0.5).id("watch-authorization-code")
                            .accessibilityLabel("授权码").accessibilityValue(code)
                    }
                    Link("打开授权页面", destination: session.authorizationURL)
                        .accessibilityHint(L10n.format("在浏览器中打开 %@", session.authorizationURL.host ?? "portal.nousresearch.com"))
                    Text(session.authorizationURL.host ?? "portal.nousresearch.com").font(.caption2)
                    if login.running { ProgressView("等待授权") }
                }
                if let message = login.message { Text(message).font(.caption2).foregroundStyle(.orange) }
                Button(login.session == nil ? L10n.text("开始授权") : L10n.text("重新授权")) {
                    login.start(accountID: accountID, expectedIdentity: expectedIdentity) { value in
                        completion(value); dismiss()
                    }
                }.disabled(login.running)
                Button("取消") { login.cancel(); dismiss() }
            }.padding()
        }
        .onDisappear { login.cancel() }
    }
}

#if DEBUG
extension WatchNousAuthorizationView {
    static func authorizationFixture() -> NousDeviceLoginModel {
        NousDeviceLoginModel(controller: ProviderAuthenticationController(transport: WatchNousFixtureTransport()),
                             sleep: { try await Task.sleep(for: .seconds(max(1, $0))) })
    }
}

private struct WatchNousFixtureTransport: ProviderTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let isBeginning = request.url?.path.hasSuffix("device/code") == true
        let body = isBeginning
            ? #"{"device_code":"watch-visual-fixture","user_code":"TEST-CODE","verification_uri":"https://portal.nousresearch.com/device","expires_in":900,"interval":1}"#
            : #"{"error":"authorization_pending"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: isBeginning ? 200 : 400, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }
}
#endif
