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
}
