import XCTest

final class TopListsView: BaseView {
    override var rootID: String { AccessibilityID.Screen.topLists }

    enum Group: String { case open, women }

    /// Picks an age list by its US Chess list ID, e.g. "Regular9".
    @discardableResult
    func selectAge(
        _ listID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        selectFilter("age", listID, file: file, line: line)
    }

    @discardableResult
    func selectGroup(
        _ group: Group,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        selectFilter("list", group.rawValue, file: file, line: line)
    }

    @discardableResult
    func assertEntry(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollTo(AccessibilityID.topListEntry(memberID), file: file, line: line)
    }

    /// Opens the player's profile.
    @discardableResult
    func tapEntry(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.topListEntry(memberID), file: file, line: line)
    }
}
