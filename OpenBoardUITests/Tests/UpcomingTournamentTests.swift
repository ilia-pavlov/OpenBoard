import XCTest

final class UpcomingTournamentTests: Runner {
    private let quads = "/sample-saturday-quads"
    private let scholastic = "/sample-scholastic-fall-classic"

    /// Events → Upcoming lists nearby tournaments; one shows register, address and directions.
    @MainActor
    func testUpcomingTournamentDetail() {
        launch(.screen(.events))
        events.assertOnScreen()
            .assertLocation("Somerville, NJ")
            .tapUpcoming(quads)
        tournament.assertOnScreen()
            .assertRegister()
            .assertAddress("495 E Main St, Somerville, NJ 08876")
            .assertDirections()
    }

    /// The Type filter keeps only matching tournaments.
    @MainActor
    func testTypeFilter() {
        launch(.screen(.events))
        events.assertOnScreen()
            .assertUpcoming(scholastic)
            .filterType(.quads)
            .assertUpcoming(quads)
            .assertNoUpcoming(scholastic)
    }
}
