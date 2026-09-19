import Foundation
import SwiftData

// MARK: - SwiftData models

@Model
final class CachedPayload {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String, payload: Data, updatedAt: Date = .now) {
        self.key = key
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class WatchedPlayer {
    @Attribute(.unique) var memberID: String
    var name: String
    var state: String?
    var isPrimary: Bool
    var lastKnownRegular: Int?
    var lastKnownQuick: Int?
    var lastRatedDate: Date?
    var addedAt: Date
    var sortOrder: Int

    init(memberID: String, name: String, state: String? = nil, isPrimary: Bool = false,
         lastKnownRegular: Int? = nil, lastKnownQuick: Int? = nil,
         lastRatedDate: Date? = nil, sortOrder: Int = 0) {
        self.memberID = memberID
        self.name = name
        self.state = state
        self.isPrimary = isPrimary
        self.lastKnownRegular = lastKnownRegular
        self.lastKnownQuick = lastKnownQuick
        self.lastRatedDate = lastRatedDate
        self.addedAt = .now
        self.sortOrder = sortOrder
    }
}

/// A tournament the user saved for later from its detail screen. The fields are
/// the ones the Watching row needs, copied at save time: the announcement feed
/// drops events once they pass, and a saved row should survive that.
@Model
final class SavedTournament {
    /// Announcement site path, e.g. "/sample-saturday-quads" — the same id the
    /// detail screen and `Destination.upcomingTournament` use.
    @Attribute(.unique) var id: String
    var name: String
    var location: String?
    var startDate: Date?
    var endDate: Date?
    var savedAt: Date

    init(
        id: String,
        name: String,
        location: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.savedAt = .now
    }
}

@Model
final class RecentSearch {
    @Attribute(.unique) var query: String
    var searchedAt: Date

    init(query: String, searchedAt: Date = .now) {
        self.query = query
        self.searchedAt = searchedAt
    }
}

// MARK: - Cache actor

/// Serialized access to the response cache, off the main thread.
@ModelActor
actor CacheStore {
    struct Entry<T: Codable & Sendable>: Sendable {
        var value: T
        var updatedAt: Date
        var isFresh: Bool
    }

    func read<T: Codable & Sendable>(_ type: T.Type, key: String,
                                     ttl: TimeInterval = AppEnvironment.cacheTTL) -> Entry<T>? {
        var descriptor = FetchDescriptor<CachedPayload>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let row = try? modelContext.fetch(descriptor).first,
              let value = try? JSONDecoder().decode(T.self, from: row.payload) else { return nil }
        return Entry(value: value, updatedAt: row.updatedAt,
                     isFresh: Date.now.timeIntervalSince(row.updatedAt) < ttl)
    }

    func write<T: Codable & Sendable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        var descriptor = FetchDescriptor<CachedPayload>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.payload = data
            existing.updatedAt = .now
        } else {
            modelContext.insert(CachedPayload(key: key, payload: data))
        }
        try? modelContext.save()
    }
}

// MARK: - Caching decorator (stale-while-revalidate)

/// Wraps any provider with a SwiftData-backed cache:
/// fresh (< TTL) → served instantly with no network;
/// stale → network refresh, falling back to the stale copy when offline.
/// Views can also grab `cached(...)` synchronously-ish for instant paint,
/// then await the throwing call for the revalidated result.
final class CachedRatingsService: RatingsProviding, Sendable {
    let upstream: any RatingsProviding
    let cache: CacheStore

    init(upstream: any RatingsProviding, container: ModelContainer) {
        self.upstream = upstream
        self.cache = CacheStore(modelContainer: container)
    }

    func player(id: String) async throws -> Player {
        try await cachedFetch(key: "player-\(id)") { try await self.upstream.player(id: id) }
    }

    func search(_ query: String) async throws -> [PlayerSummary] {
        // Searches are interactive; don't cache result lists.
        try await upstream.search(query)
    }

    func event(id: String) async throws -> ChessEvent {
        try await cachedFetch(key: "event-\(id)") { try await self.upstream.event(id: id) }
    }

    /// Top lists change monthly; half a day keeps them fresh without refetching all ~70.
    private static let topListTTL: TimeInterval = 12 * 60 * 60

    func topListDefinitions() async throws -> [TopListDefinition] {
        try await cachedFetch(key: "toplists", ttl: Self.topListTTL) { try await self.upstream.topListDefinitions() }
    }

    func topList(_ definition: TopListDefinition) async throws -> TopList {
        try await cachedFetch(key: "toplist-\(definition.id)", ttl: Self.topListTTL) {
            try await self.upstream.topList(definition)
        }
    }

    /// Last stored copy regardless of freshness, plus its timestamp — for
    /// instant paint and the "showing cached from 3:12 PM" error state.
    func cachedPlayer(id: String) async -> (Player, Date)? {
        await cache.read(Player.self, key: "player-\(id)").map { ($0.value, $0.updatedAt) }
    }

    func cachedEvent(id: String) async -> (ChessEvent, Date)? {
        await cache.read(ChessEvent.self, key: "event-\(id)").map { ($0.value, $0.updatedAt) }
    }

    private func cachedFetch<T: Codable & Sendable>(key: String, ttl: TimeInterval = AppEnvironment.cacheTTL,
                                                    fetch: @Sendable () async throws -> T) async throws -> T {
        if let entry = await cache.read(T.self, key: key, ttl: ttl), entry.isFresh {
            return entry.value
        }
        do {
            let fresh = try await fetch()
            await cache.write(fresh, key: key)
            return fresh
        } catch {
            if let stale = await cache.read(T.self, key: key) { return stale.value }
            throw error
        }
    }
}
