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
