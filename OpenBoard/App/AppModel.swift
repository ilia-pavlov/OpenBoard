import Foundation
import SwiftData
import SwiftUI

/// Navigation destinations shared by iPhone tabs and iPad split view.
enum Destination: Hashable {
    case player(id: String)
    case event(id: String, highlight: String?)
    case ratingHistory(player: Player, system: RatingSystem)
    case upcomingTournament(id: String)
    case majorEvent(MajorEvent)
}

enum AppTab: String, CaseIterable, Identifiable {
    case myCard, search, events, watching
    var id: String { rawValue }

    var title: String {
        switch self {
        case .myCard: String(localized: "My Card")
        case .search: String(localized: "Search")
        case .events: String(localized: "Events")
        case .watching: String(localized: "Watching")
        }
    }

    var systemImage: String {
        switch self {
        case .myCard: "crown"
        case .search: "magnifyingglass"
        case .events: "trophy"
        case .watching: "heart"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let service: CachedRatingsService
    let tournaments: any TournamentsProviding
    let location: LocationProvider

    var selectedTab: AppTab = .myCard

    /// Defaults come from launch arguments; previews pass them explicitly since
    /// they can't set launch arguments.
    init(dataSource: AppEnvironment.DataSource = AppEnvironment.dataSource,
         demoSeed: Bool = AppEnvironment.demoSeed) {
        let mock = dataSource == .mock
        let schema = Schema([WatchedPlayer.self, CachedPayload.self, RecentSearch.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: mock)
        container = try! ModelContainer(for: schema, configurations: [config])

        let upstream: any RatingsProviding = mock ? MockRatingsService() : LiveRatingsService()
        service = CachedRatingsService(upstream: upstream, container: container)
        tournaments = mock ? MockTournamentsService() : LiveTournamentsService()
        location = LocationProvider(mock: mock)

        // No pre-seeded watchlist: the app launches empty. The user searches for
        // their own player (the first one watched becomes primary / "My Card")
        // and looks up tournaments by event ID.
        if demoSeed { seedDemoWatchlist() }
    }

    /// Screenshot/demo only (`-demoSeed`): populate the watchlist with synthetic
    /// sample players so My Card and Watching render with content.
    private func seedDemoWatchlist() {
        let ctx = container.mainContext
        guard ((try? ctx.fetchCount(FetchDescriptor<WatchedPlayer>())) ?? 0) == 0 else { return }
        let primary = MockRatingsService.samplePlayer
        ctx.insert(WatchedPlayer(memberID: primary.id, name: primary.name, state: primary.state,
                                 isPrimary: true, lastKnownRegular: primary.currentRegular,
                                 lastKnownQuick: primary.currentQuick,
                                 lastRatedDate: primary.events.first?.date, sortOrder: 0))
        let rivals = MockRatingsService.sampleEvent.sections[0].players
            .filter { $0.id != primary.id }.prefix(3)
        for (index, s) in rivals.enumerated() {
            ctx.insert(WatchedPlayer(memberID: s.id, name: s.name, state: s.state, isPrimary: false,
                                     lastKnownRegular: s.regular?.post, lastKnownQuick: s.quick?.post,
                                     lastRatedDate: MockRatingsService.sampleEvent.date,
                                     sortOrder: index + 1))
        }
        try? ctx.save()
    }

    // MARK: - Watchlist helpers

    var primaryMemberID: String? {
        var descriptor = FetchDescriptor<WatchedPlayer>(predicate: #Predicate { $0.isPrimary })
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first?.memberID
    }

    var watchedIDs: Set<String> {
        let rows = (try? container.mainContext.fetch(FetchDescriptor<WatchedPlayer>())) ?? []
        return Set(rows.map(\.memberID))
    }

    func isWatching(_ memberID: String) -> Bool {
        watchedIDs.contains(memberID)
    }

    func toggleWatch(_ player: Player) {
        let context = container.mainContext
        let id = player.id
        var descriptor = FetchDescriptor<WatchedPlayer>(predicate: #Predicate { $0.memberID == id })
        descriptor.fetchLimit = 1
        if let row = try? context.fetch(descriptor).first {
            context.delete(row)
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<WatchedPlayer>())) ?? 0
            let isFirst = count == 0
            context.insert(WatchedPlayer(memberID: player.id, name: player.name,
                                         state: player.state, isPrimary: isFirst,
                                         lastKnownRegular: player.currentRegular,
                                         lastKnownQuick: player.currentQuick,
                                         lastRatedDate: player.events.first?.date,
                                         sortOrder: count))
        }
        try? context.save()
    }

    func setPrimary(_ memberID: String) {
        let context = container.mainContext
        let rows = (try? context.fetch(FetchDescriptor<WatchedPlayer>())) ?? []
        for row in rows { row.isPrimary = row.memberID == memberID }
        try? context.save()
    }

    func rememberSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 1 else { return }
        let context = container.mainContext
        var descriptor = FetchDescriptor<RecentSearch>(predicate: #Predicate { $0.query == trimmed })
        descriptor.fetchLimit = 1
        if let row = try? context.fetch(descriptor).first {
            row.searchedAt = .now
        } else {
            context.insert(RecentSearch(query: trimmed))
        }
        try? context.save()
    }
}
