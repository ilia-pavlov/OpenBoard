import XCTest

final class RatingHistoryTests: Runner {
    /// My Card's rating card → history; the Result filter narrows the list; events open crosstables.
    @MainActor
    func testMyCardToRatingHistoryToCrosstable() {
        launch(.demoSeed)
        myCard.assertOnScreen()
            .tapHeroCard()
        ratingHistory.assertOnScreen()
            .assertEvent(Sample.eventID)
            .filterResult(.down)
            .assertEvent(Sample.lossEventID)
            .assertNoEvent(Sample.eventID)
            .filterResult(.up)
            .tapEvent(Sample.eventID)
        crosstable.assertOnScreen()
            .assertStanding(Sample.playerID)
    }

    /// Quick shows only events with a Quick rating.
    @MainActor
    func testQuickShowsOnlyQuickRatedEvents() {
        launch(.screen(.history))
        ratingHistory.assertOnScreen()
            .assertEvent(Sample.lossEventID)
            .selectRating(.quick)
            .assertEvent(Sample.eventID)
            .assertNoEvent(Sample.lossEventID) // regular-only event
    }

    /// Any profile — even several screens deep — opens its rating history.
    @MainActor
    func testOtherPlayersProfileOpensRatingHistory() {
        launch(.demoSeed)
        myCard.assertOnScreen()
            .tapHeroCard()
        ratingHistory.assertOnScreen()
            .tapEvent(Sample.eventID)
        crosstable.assertOnScreen()
            .tapStanding(Sample.rivalID)
            .tapViewFullProfile(Sample.rivalID)
        profile.assertLoaded()
            .tapRatingCard()
        ratingHistory.assertOnScreen()
    }
}
