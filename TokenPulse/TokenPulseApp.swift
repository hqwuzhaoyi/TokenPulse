import SwiftUI

@main
struct TokenPulseApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var runtime: AppRuntime

    init() {
        let runtime = AppRuntime()
        runtime.registerBackgroundRefresh()
        _runtime = StateObject(wrappedValue: runtime)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: runtime.monitor, runtime: runtime)
                .id(runtime.isDemoMode)
                .task { await runtime.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await runtime.scheduleBackgroundRefresh() } }
                }
        }
    }
}
