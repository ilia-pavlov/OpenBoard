import XCTest

/// Saved tournaments live in SwiftData, which is in-memory under `-mock`, so a
/// relaunch would wipe what the test just saved — these flows stay in one
/// launch and cross tabs instead.
final class SavedTournamentTests: Runner {
    /// Save from the detail screen and the tournament shows up under Watching.
    @MainActor
    func testSaveTournamentAppearsInWatching() {
        launch(.screen(.events))
        events.assertOnScreen().tapUpcoming(Sample.upcomingID)
        tournament.assertOnScreen()
            .assertSaved(false)
            .tapSave()
            .assertSaved(true)
            .goBack()

        events.selectTab("Watching")
        watching.assertOnScreen().assertSavedTournament(Sample.upcomingID)
    }

    /// Tapping Save again removes it, and the Watching row goes with it.
    @MainActor
    func testUnsaveRemovesItFromWatching() {
        launch(.screen(.events))
        events.assertOnScreen().tapUpcoming(Sample.upcomingID)
        tournament.assertOnScreen()
            .tapSave()
            .assertSaved(true)
            .tapSave()
            .assertSaved(false)
            .goBack()

        events.selectTab("Watching")
        watching.assertOnScreen().assertNoSavedTournament(Sample.upcomingID)
    }

    /// Two tournaments saved in one session both reach Watching, and the button
    /// flips to its filled state each time.
    ///
    /// The bookmark animates (symbol replace + bounce) on tap. XCUITest can't
    /// observe an animation, so what is asserted is the state it animates to:
    /// the button re-labels itself, which is what drives the filled symbol.
    @MainActor
    func testSavingTwoTournamentsBothReachWatching() {
        launch(.screen(.events))

        events.assertOnScreen().tapUpcoming(Sample.upcomingID)
        tournament.assertOnScreen()
            .assertSaved(false)
            .tapSave()
            .assertSaved(true)
            .goBack()

        events.assertOnScreen().tapUpcoming(Sample.upcomingID2)
        tournament.assertOnScreen()
            .assertSaved(false)
            .tapSave()
            .assertSaved(true)
            .goBack()

        events.selectTab("Watching")
        watching.assertOnScreen()
            .assertSavedTournament(Sample.upcomingID)
            .assertSavedTournament(Sample.upcomingID2)
    }

    /// Saving one leaves the other alone — the button reads per-tournament.
    @MainActor
    func testSavingOneDoesNotSaveTheOther() {
        launch(.screen(.events))

        events.assertOnScreen().tapUpcoming(Sample.upcomingID)
        tournament.assertOnScreen().tapSave().assertSaved(true).goBack()

        events.assertOnScreen().tapUpcoming(Sample.upcomingID2)
        tournament.assertOnScreen().assertSaved(false).goBack()

        events.selectTab("Watching")
        watching.assertOnScreen()
            .assertSavedTournament(Sample.upcomingID)
            .assertNoSavedTournament(Sample.upcomingID2)
    }

    /// The saved row opens the tournament it was saved from, still saved.
    @MainActor
    func testSavedRowOpensTheTournament() {
        launch(.screen(.events))
        events.assertOnScreen().tapUpcoming(Sample.upcomingID)
        tournament.assertOnScreen().tapSave().assertSaved(true).goBack()

        events.selectTab("Watching")
        watching.assertOnScreen().tapSavedTournament(Sample.upcomingID)
        tournament.assertOnScreen().assertSaved(true)
    }
}
