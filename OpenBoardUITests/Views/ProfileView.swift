import XCTest

final class ProfileView: BaseView {
    override var rootID: String { AccessibilityID.Screen.profile }

    /// Profile finished loading (the Watch button only appears with data).
    @discardableResult
    func assertLoaded(file: StaticString = #filePath, line: UInt = #line) -> Self {
        assertOnScreen(file: file, line: line)
        return assertExists(AccessibilityID.watchToggle, timeout: 10, file: file, line: line)
    }

    /// The Regular card; opens Rating History.
    @discardableResult
    func tapRatingCard(file: StaticString = #filePath, line: UInt = #line) -> Self {
        tap(AccessibilityID.profileRatingCard, file: file, line: line)
    }

    @discardableResult
    func showHistory(file: StaticString = #filePath, line: UInt = #line) -> Self {
        selectSegment("profile", "history", file: file, line: line)
    }

    @discardableResult
    func tapHistoryEvent(
        _ eventID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.historyEvent(eventID), file: file, line: line)
    }

    @discardableResult
    func assertTopBadge(
        _ listID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.topBadge(listID), file: file, line: line)
    }

    /// Opens the Top 100 list behind a badge.
    @discardableResult
    func tapTopBadge(
        _ listID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.topBadge(listID), file: file, line: line)
    }
}
