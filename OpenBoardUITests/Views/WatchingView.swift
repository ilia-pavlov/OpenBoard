import XCTest

final class WatchingView: BaseView {
    override var rootID: String { AccessibilityID.Screen.watching }

    @discardableResult
    func assertRow(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.watchRow(memberID), file: file, line: line)
    }

    @discardableResult
    func assertSavedTournament(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.savedTournament(id), timeout: 10, file: file, line: line)
    }

    @discardableResult
    func assertNoSavedTournament(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertNotExists(AccessibilityID.savedTournament(id), file: file, line: line)
    }

    /// Opens the saved tournament's detail screen.
    @discardableResult
    func tapSavedTournament(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.savedTournament(id), file: file, line: line)
    }

    /// Edit → drag `memberID`'s handle onto `targetID`'s row → Done.
    @discardableResult
    func drag(
        _ memberID: String,
        onto targetID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.watchlistEdit, file: file, line: line)
        scrollTo(AccessibilityID.watchRow(targetID), file: file, line: line)
        let row = element(AccessibilityID.watchRow(memberID)).assertExistence(file: file, line: line)
        let target = element(AccessibilityID.watchRow(targetID)).assertExistence(file: file, line: line)
        // The row's reorder handle: the "Reorder" button level with the row.
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).allElementsBoundByIndex
        guard let handle = handles.first(where: { abs($0.frame.midY - row.frame.midY) < row.frame.height / 2 }) else {
            XCTFail("No reorder handle for '\(memberID)'", file: file, line: line)
            return self
        }
        handle.press(forDuration: 0.6, thenDragTo: target)
        return tap(AccessibilityID.watchlistEdit, file: file, line: line)
    }

    /// `upper` is listed above `lower`.
    @discardableResult
    func assertOrder(
        _ upper: String,
        above lower: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollTo(AccessibilityID.watchRow(lower), file: file, line: line)
        let top = element(AccessibilityID.watchRow(upper)).assertExistence(file: file, line: line)
        let bottom = element(AccessibilityID.watchRow(lower)).assertExistence(file: file, line: line)
        XCTAssertLessThan(top.frame.minY, bottom.frame.minY, "'\(upper)' isn't above '\(lower)'",
                          file: file, line: line)
        return self
    }

    /// Opens the player's profile.
    @discardableResult
    func tapRow(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.watchRow(memberID), file: file, line: line)
    }
}
