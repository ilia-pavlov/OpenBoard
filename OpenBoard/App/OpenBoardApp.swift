import SwiftUI
import SwiftData
import UserNotifications

@main
struct OpenBoardApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        if AppEnvironment.dataSource == .live {
            RefreshScheduler.register(container: model.container, service: model.service)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .tint(.obGold)
                .task {
                    // The app no longer badges its icon; clear any count left by older builds.
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                    // Background refresh + notifications only matter with live
                    // data; mock/demo/screenshot runs skip the permission prompt.
                    if AppEnvironment.dataSource == .live {
                        RefreshScheduler.requestNotificationAuthorization()
                        RefreshScheduler.scheduleNext()
                    }
                }
        }
    }
}

// Previews always run on mock data with an in-memory store (no network, no
// background refresh, no notification prompt).

#Preview("Demo watchlist") {
    let model = AppModel(dataSource: .mock, demoSeed: true)
    RootView()
        .environment(model)
        .modelContainer(model.container)
        .tint(.obGold)
}

#Preview("First launch") {
    let model = AppModel(dataSource: .mock, demoSeed: false)
    RootView()
        .environment(model)
        .modelContainer(model.container)
        .tint(.obGold)
}
