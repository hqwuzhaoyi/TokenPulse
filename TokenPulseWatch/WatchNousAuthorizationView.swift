import SwiftUI

struct WatchNousAuthorizationView: View {
    let accountID: UUID
    let expectedIdentity: String
    let completion: (String) -> Void
    @StateObject private var login = NousDeviceLoginModel()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("连接此 Watch").font(.headline)
                Text("请用与 iPhone 上相同的 Nous 账号授权。授权页可能显示 Hermes CLI。")
                    .font(.caption2).foregroundStyle(.secondary)
                if let session = login.session {
                    if let code = session.userCode { Text(code).font(.title3.monospaced()).bold() }
                    Link("打开授权页面", destination: session.authorizationURL)
                    Text(session.authorizationURL.host ?? "portal.nousresearch.com").font(.caption2)
                    if login.running { ProgressView("等待授权") }
                }
                if let message = login.message { Text(message).font(.caption2).foregroundStyle(.orange) }
                Button(login.session == nil ? "开始授权" : "重新授权") {
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
