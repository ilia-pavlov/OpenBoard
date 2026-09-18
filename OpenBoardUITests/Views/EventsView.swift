import XCTest

final class EventsView: BaseView {
    override var rootID: String { AccessibilityID.Screen.events }

    enum Mode: String { case upcoming, results }
    enum TournamentType: String { case any, scholastic, quads, grandPrix }

    @discardableResult
    func selectMode(
        _ mode: Mode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        selectSegment("events", mode.rawValue, file: file, line: line)
    }

    /// The "Near …" row shows the search origin.
    @discardableResult
    func assertLocation(
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let row = element(AccessibilityID.upcomingLocation).assertExistence(timeout: 10, file: file, line: line)
        XCTAssertTrue(row.label.contains(label), "Location row '\(row.label)' lacks '\(label)'",
                      file: file, line: line)
        return self
    }

    @discardableResult
    func filterType(
        _ type: TournamentType,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        selectFilter("type", type.rawValue, file: file, line: line)
    }

    @discardableResult
    func assertUpcoming(
        _ listingID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.upcoming(listingID), timeout: 10, file: file, line: line)
    }

    @discardableResult
    func assertNoUpcoming(
        _ listingID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertNotExists(AccessibilityID.upcoming(listingID), file: file, line: line)
    }

    @discardableResult
    func tapUpcoming(
        _ listingID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.upcoming(listingID), file: file, line: line)
    }
}
