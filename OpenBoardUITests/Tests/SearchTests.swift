import XCTest

final class SearchTests: Runner {
    /// Search by name → profile → History tab → event → crosstable.
    @MainActor
    func testSearchToProfileToCrosstable() {
        launch(.screen(.search))
        search.assertOnScreen()
            .typeQuery("rivera")
            .tapResult(Sample.playerID)
        profile.assertLoaded()
            .showHistory()
            .tapHistoryEvent(Sample.eventID)
        crosstable.assertOnScreen()
            .assertStanding(Sample.playerID)
    }
}

final class SearchTabTests: Runner {
    /// Join / renew US Chess sits under Top 100.
    @MainActor
    func testJoinUSChessRow() {
        launch(.screen(.search))
        search.assertOnScreen()
            .assertJoinUSChess()
    }

    /// Recent searches can be swiped away one by one, or cleared at once.
    /// (The newest is on top, clear of the keyboard.)
    @MainActor
    func testRemoveRecentSearches() {
        launch(.screen(.search))
        search.assertOnScreen()
            .search("rivera")
            .search("sterling")
            .search("brooks")
            .removeRecent("brooks")
            .assertNoRecent("brooks")
            .assertRecent("sterling")
            .assertRecent("rivera")
            .clearRecents()
            .assertNoRecent("sterling")
            .assertNoRecent("rivera")
    }
}
