import SwiftUI

/// The user deliberately supplies an official export for this device; the app never reads CLI state.
struct JetBrainsImportView: View {
    let accountID: UUID
    var expectedIdentity: String? = nil
    var bindCredential: (@MainActor (String) async -> Bool)? = nil
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var transfer = ""
    @State private var message: String?
    @State private var running = false
    @State private var completed = false
    @State private var attempted = false
    @State private var runID = UUID()
    @State private var task: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Text("在你控制的电脑中登录官方 JetBrains Central，选择个人 license，再运行 central login export。将导出值输入到此设备。")
                    .font(.footnote)
                Text("每台设备必须分别登录并导出新的独立授权；不要把手机使用的同一 export 输入 Watch。导出值包含凭证，只保存在此设备。")
                    .font(.footnote).foregroundStyle(.secondary)
                if bindCredential == nil {
                    Text("验证成功后请在账号表单点“保存”。未保存的授权不会替换现有账号，候选可在一小时内保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                SecureField("central-…", text: $transfer)
                    .disabled(running)
                Button("导入并读取额度") {
                    let run = UUID(); runID = run; running = true; attempted = true; message = nil
                    let input = transfer; transfer = ""
                    task = Task { @MainActor in
                        defer { if runID == run { running = false; task = nil } }
                        do {
                            let value = try await JetBrainsSessionCoordinator.shared.importTransfer(input, accountID: accountID,
                                vault: .shared, expectedIdentity: expectedIdentity, attemptID: run)
                            guard runID == run, !Task.isCancelled else { return }
                            if let bindCredential, !(await bindCredential(value)) {
                                try? await JetBrainsSessionCoordinator.shared.cancelImport(accountID: accountID, vault: .shared, attemptID: run)
                                message = "账号配置已改变，请重新打开此账号并导入匹配的独立授权。"
                                return
                            }
                            guard runID == run, !Task.isCancelled else { return }
                            completed = true; completion(value)
                            dismiss()
                        } catch {
                            guard runID == run, !Task.isCancelled else { return }
                            message = "尚未完成导入。可继续本次已保存的授权；若刷新结果不明或已关闭本页，请重新登录并导出独立授权。"
                        }
                    }
                }.disabled(running || transfer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if running { ProgressView("正在验证授权与额度") }
                if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .onDisappear {
            guard !completed, attempted else { return }
            let lease = runID
            runID = UUID(); task?.cancel(); task = nil
            Task { try? await JetBrainsSessionCoordinator.shared.cancelImport(accountID: accountID, vault: .shared, attemptID: lease) }
        }
    }
}
