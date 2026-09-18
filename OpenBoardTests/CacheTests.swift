import Testing
import Foundation
@testable import OpenBoard

@Suite("Cache TTL")
struct CacheTests {
    @MainActor
    private func makeStore() throws -> CacheStore {
        let container = try TestContainer.inMemory()
        return CacheStore(modelContainer: container)
    }

    @Test @MainActor func freshWithinTTL() async throws {
        let store = try makeStore()
        await store.write(MockRatingsService.samplePlayer, key: "player-x")
        let entry = try #require(await store.read(Player.self, key: "player-x"))
        #expect(entry.isFresh)
        #expect(entry.value.id == MockRatingsService.samplePlayerID)
    }

    @Test @MainActor func staleBeyondTTL() async throws {
        let store = try makeStore()
        await store.write(MockRatingsService.samplePlayer, key: "player-y")
        // A zero TTL makes any stored entry stale immediately.
        let entry = try #require(await store.read(Player.self, key: "player-y", ttl: 0))
        #expect(!entry.isFresh)
    }

    @Test @MainActor func missingKeyReturnsNil() async throws {
        let store = try makeStore()
        let entry = await store.read(Player.self, key: "never-written")
        #expect(entry == nil)
    }

    @Test @MainActor func staleServedWhenUpstreamFails() async throws {
        struct FailingService: RatingsProviding {
            func player(id: String) async throws -> Player { throw RatingsError.offline(underlying: "test") }
            func search(_ query: String) async throws -> [PlayerSummary] { [] }
            func event(id: String) async throws -> ChessEvent { throw RatingsError.offline(underlying: "test") }
            func topListDefinitions() async throws -> [TopListDefinition] { [] }
            func topList(_ definition: TopListDefinition) async throws -> TopList {
                throw RatingsError.offline(underlying: "test")
            }
        }
        let container = try TestContainer.inMemory()
        let service = CachedRatingsService(upstream: FailingService(), container: container)

        // Seed the cache, then verify the failing upstream still yields the copy.
        let id = MockRatingsService.samplePlayerID
        await service.cache.write(MockRatingsService.samplePlayer, key: "player-\(id)")
        let player = try await service.player(id: id)
        #expect(player.id == id)
        #expect(player.ratings.regular?.value == 383)
    }
}
