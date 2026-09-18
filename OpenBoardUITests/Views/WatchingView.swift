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
