import SwiftData
@testable import OpenBoard

/// A throwaway in-memory SwiftData store with the app's schema.
enum TestContainer {
    static func inMemory() throws -> ModelContainer {
        let schema = Schema([WatchedPlayer.self, CachedPayload.self, RecentSearch.self])
        return try ModelContainer(for: schema,
                                  configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}
