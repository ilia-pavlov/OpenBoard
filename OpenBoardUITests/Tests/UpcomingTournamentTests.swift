import XCTest

final class UpcomingTournamentTests: Runner {
    private let quads = "/sample-saturday-quads"
    private let scholastic = "/sample-scholastic-fall-classic"
    private let recurring = "/sample-friday-night-rapid"

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

    /// Distance runs from 10 mi (dense cities) to 500 mi (big states).
    @MainActor
    func testDistanceRange() {
        launch(.screen(.events))
        events.assertOnScreen()
            .selectDistance(500, offering: [10, 25, 50, 100, 200, 300, 500])
            .assertDistance("500 mi")
    }

    /// Announcements keep the organizer's links and can be copied.
    @MainActor
    func testAnnouncementLinksAndCopy() {
        launch(.screen(.events))
        events.assertOnScreen()
            .tapUpcoming(scholastic)
        tournament.assertOnScreen()
            .assertAnnouncementLink("Register here")
            .copyAnnouncement()
    }

    /// Back from a tournament returns to the same spot, with that row marked.
    @MainActor
    func testBackKeepsPlace() {
        launch(.screen(.events))
        events.assertOnScreen()
            .assertUpcoming(quads)
            .assertBackKeepsPlace(of: AccessibilityID.upcoming(recurring))
    }
}

