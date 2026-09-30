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
}
