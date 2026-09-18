import XCTest

final class RatingHistoryView: BaseView {
    override var rootID: String { AccessibilityID.Screen.ratingHistory }

    enum Rating: String { case regular, quick }
    enum Result: String { case all, up, down, even }

    @discardableResult
    func selectRating(
        _ rating: Rating,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        selectSegment("rating", rating.rawValue, file: file, line: line)
    }

    /// Result filter: gained / lost / no change / any.
    @discardableResult
    func filterResult(
        _ result: Result,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        selectFilter("result", result.rawValue, file: file, line: line)
    }

    @discardableResult
    func assertEvent(
        _ eventID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.ratingHistoryEvent(eventID), file: file, line: line)
    }

    @discardableResult
    func assertNoEvent(
        _ eventID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertNotExists(AccessibilityID.ratingHistoryEvent(eventID), file: file, line: line)
    }

    /// Opens the event's crosstable.
    @discardableResult
    func tapEvent(
        _ eventID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.ratingHistoryEvent(eventID), file: file, line: line)
    }
}
