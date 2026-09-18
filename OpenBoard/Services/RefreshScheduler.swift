import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData

/// Background polling of watched players (~2×/day) + local notifications
/// when a stored rating differs from the freshly fetched one.
enum RefreshScheduler {
    static let taskIdentifier = "com.iliapavlov.openboard.refresh"

    static func register(container: ModelContainer, service: any RatingsProviding) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            scheduleNext() // keep the chain alive
            // BGAppRefreshTask isn't Sendable, but completing it from the worker
            // task is the documented pattern; the system object is thread-safe.
            nonisolated(unsafe) let bgTask = refresh
            let work = Task {
                let changed = await checkWatchlist(container: container, service: service)
                bgTask.setTaskCompleted(success: changed != nil)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60) // ~2×/day
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Compares stored vs fetched ratings for every watched player, updates the
    /// store, fires notifications. Returns the number of changed players, or
    /// nil if the check failed entirely.
    @discardableResult
    static func checkWatchlist(container: ModelContainer, service: any RatingsProviding) async -> Int? {
        let store = WatchlistChecker(modelContainer: container)
        return await store.run(service: service)
    }
}

@ModelActor
actor WatchlistChecker {
    func run(service: any RatingsProviding) async -> Int? {
        guard let watched = try? modelContext.fetch(FetchDescriptor<WatchedPlayer>()) else { return nil }
        var changes = 0
        for row in watched {
            guard let player = try? await service.player(id: row.memberID) else { continue }
            let newRegular = player.currentRegular
            let old = row.lastKnownRegular
            if let newRegular, newRegular != old {
                changes += 1
                if old != nil { // don't notify on first-ever fill-in
                    notify(name: player.firstName, old: old, new: newRegular)
                }
                row.lastKnownRegular = newRegular
                row.lastRatedDate = player.events.first?.date ?? .now
            }
            row.lastKnownQuick = player.currentQuick ?? row.lastKnownQuick
        }
        try? modelContext.save()
        return changes
    }

    private func notify(name: String, old: Int?, new: Int) {
        let content = UNMutableNotificationContent()
        let delta = old.map { new - $0 }
        let deltaText = delta.map { $0 >= 0 ? " (+\($0))" : " (\($0))" } ?? ""
        let cheer = (delta ?? 0) >= 0 ? " 🎉" : ""
        content.title = "Rating update"
        content.body = "\(name)'s new rating: \(new)\(deltaText)\(cheer)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
