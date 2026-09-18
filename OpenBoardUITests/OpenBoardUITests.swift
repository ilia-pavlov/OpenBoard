import XCTest

/// Happy path on the mock service: search → player profile → event crosstable.
final class OpenBoardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSearchToProfileToCrosstable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        // 1. Go to Search and find the sample player.
        app.tabBars.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("rivera")

        let result = app.descendants(matching: .any)["search-result-90000001"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "search result should appear")
        result.tap()

        // 2. Profile: watch toggle & history segment exist.
        let watchToggle = app.descendants(matching: .any)["watch-toggle"].firstMatch
        XCTAssertTrue(watchToggle.waitForExistence(timeout: 5), "profile should load")

        app.buttons["History"].firstMatch.tap()
        let eventRow = app.descendants(matching: .any)["history-event-900000000001"].firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5), "history should list the sample event")
        eventRow.tap()

        // 3. Crosstable: the sample player's highlighted standing row is present.
        let standing = app.descendants(matching: .any)["standing-90000001"].firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: 5), "crosstable should show the followed player")
    }

    @MainActor
    func testMyCardToRatingHistoryToCrosstable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-demoSeed"]
        app.launch()

        // 1. Tap the hero rating card on My Card.
        let hero = app.descendants(matching: .any)["hero-rating-card"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "My Card should load")
        hero.tap()

        // 2. Rating history lists every event; the result filter narrows the list.
        let latest = app.descendants(matching: .any)["rating-history-event-900000000001"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 5), "history should list the latest event")

        app.buttons["Result"].firstMatch.tap()
        app.buttons["Lost"].firstMatch.tap()
        let lost = app.descendants(matching: .any)["rating-history-event-900000000002"].firstMatch
        XCTAssertTrue(lost.waitForExistence(timeout: 5), "a rating-loss event should remain")
        XCTAssertFalse(latest.exists, "a rating-gain event should be filtered out")

        // 3. Switch to gains and open the latest event's crosstable.
        app.buttons["Lost"].firstMatch.tap()
        app.buttons["Gained"].firstMatch.tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        latest.tap()
        let standing = app.descendants(matching: .any)["standing-90000001"].firstMatch
        XCTAssertTrue(standing.waitForExistence(timeout: 5), "crosstable should show the followed player")
    }

    /// Any profile — even one reached several screens deep — opens its rating history.
    @MainActor
    func testOtherPlayersProfileOpensRatingHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-demoSeed"]
        app.launch()

        let hero = app.descendants(matching: .any)["hero-rating-card"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        hero.tap()

        let event = app.descendants(matching: .any)["rating-history-event-900000000001"].firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()

        // Expand another player's crosstable row and open their full profile.
        let rival = app.descendants(matching: .any)["standing-90000011"].firstMatch
        XCTAssertTrue(rival.waitForExistence(timeout: 5), "crosstable should load")
        rival.tap()
        let fullProfile = app.buttons["View full profile"].firstMatch
        XCTAssertTrue(fullProfile.waitForExistence(timeout: 5))
        fullProfile.tap()

        let ratingCard = app.descendants(matching: .any)["profile-rating-card"].firstMatch
        XCTAssertTrue(ratingCard.waitForExistence(timeout: 5), "rival's profile should load")
        ratingCard.tap()

        XCTAssertTrue(app.navigationBars["Rating History"].waitForExistence(timeout: 5),
                      "rating card should open the rival's rating history")
    }

    /// Long section names are chosen from a sheet instead of a truncating segmented control.
    @MainActor
    func testTournamentSectionPicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock", "-screen", "event"]
        app.launch()

        // Opens on the followed player's section.
        let followed = app.descendants(matching: .any)["standing-90000001"].firstMatch
        XCTAssertTrue(followed.waitForExistence(timeout: 5), "crosstable should load")

        let menu = app.descendants(matching: .any)["section-menu"].firstMatch
        XCTAssertTrue(menu.exists)
        menu.tap()

        let option = app.descendants(matching: .any)["section-option-1"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "section sheet should list sections")
        XCTAssertTrue(app.staticTexts["Section 2 Open U1200 G/45;d5 (K-12)"].exists,
                      "full section name should be shown")
        option.tap()

        let otherSection = app.descendants(matching: .any)["standing-90000020"].firstMatch
        XCTAssertTrue(otherSection.waitForExistence(timeout: 5), "picking a section shows its standings")
    }

    /// Events → Upcoming lists nearby tournaments; a tournament shows location and registration.
    @MainActor
    func testUpcomingTournamentDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-mock"]
        app.launch()

        app.tabBars.buttons["Events"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Near Somerville, NJ"].waitForExistence(timeout: 5))

        let row = app.buttons["upcoming-/sample-saturday-quads"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "nearby tournaments should load")
        row.tap()

        XCTAssertTrue(app.buttons["tournament-register"].waitForExistence(timeout: 5), "register link")
        XCTAssertTrue(app.staticTexts["495 E Main St, Somerville, NJ 08876"].exists, "venue address")
        XCTAssertTrue(app.buttons["Directions"].exists || app.links["Directions"].exists)
    }
}
