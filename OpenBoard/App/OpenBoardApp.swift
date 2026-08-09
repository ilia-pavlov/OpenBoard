import SwiftUI
import SwiftData

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
