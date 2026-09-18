import XCTest

final class TopListsTests: Runner {
    /// Search → Top 100 → Age 9 → player → profile shows the badge.
    @MainActor
    func testBrowseToProfile() {
        launch(.screen(.search))
        search.assertOnScreen()
            .tapTop100()
        topLists.assertOnScreen()
            .selectAge(Sample.age9ListID)
            .tapEntry(Sample.playerID)
        profile.assertLoaded()
            .assertTopBadge(Sample.age9ListID)
    }

    /// A profile badge opens its list with the player on it.
    @MainActor
    func testProfileBadgeOpensList() {
        launch(.screen(.profile))
        profile.assertLoaded()
            .tapTopBadge(Sample.age9ListID)
        topLists.assertOnScreen()
            .assertEntry(Sample.playerID)
    }

    /// Girls lists are separate from the open lists.
    @MainActor
    func testGirlsList() {
        launch(.screen(.search))
        search.assertOnScreen()
            .tapTop100()
        topLists.assertOnScreen()
            .selectGroup(.women)
            .selectAge(Sample.girlsListID)
            .assertEntry("90000010") // Ava Sterling, #12 Girls Age 8
    }
}
