import XCTest

/// Best wins in demo mode: Alex Rivera beat Owen Price (374, #81 Age 9 in demo
/// data) and Ivy Nguyen (106) in the sample event.
final class BestWinsTests: Runner {
    private let owen = "90000013"
    private let ivy = "90000014"

    /// My Card shows the best wins, strongest first, with the opponent's Top 100 badge.
    @MainActor
    func testMyCardShowsBestWins() {
        launch(.demoSeed)
        myCard.assertOnScreen()
            .assertBestWin(owen, mentions: ["Owen Price", "374", "52 points above", "number 81"])
            .assertBestWin(ivy, mentions: ["Ivy Nguyen", "106"])
    }

    /// A win opens that event's crosstable; back returns to the same spot, row marked.
    @MainActor
    func testWinOpensCrosstableAndBackKeepsPlace() {
        launch(.demoSeed)
        myCard.assertOnScreen()
            .tapBestWin(owen)
        crosstable.assertOnScreen()
            .goBack()
        myCard.assertSelected(AccessibilityID.bestWin(owen))
            .assertBackKeepsPlace(of: AccessibilityID.bestWin(owen))
    }

    /// ⓘ explains the card in plain words.
    @MainActor
    func testInfoExplainsBestWins() {
        launch(.demoSeed)
        myCard.assertOnScreen()
            .openBestWinsInfo()
    }

    /// Other players' profiles show their best wins too.
    @MainActor
    func testProfileShowsBestWins() {
        launch(.screen(.profile, arg: Sample.playerID))
        profile.assertOnScreen()
            .assertBestWin(owen, mentions: ["Owen Price"])
    }

    /// Back from a Recent events crosstable keeps My Card where it was, even with
    /// Best wins above the list.
    @MainActor
    func testRecentEventsBackKeepsPlace() {
        launch(.demoSeed)
        myCard.assertOnScreen()
            .assertBestWin(owen)
            .assertBackKeepsPlace(of: AccessibilityID.recentEvent(Sample.eventID))
    }
}
