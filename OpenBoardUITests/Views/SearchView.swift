import XCTest

final class SearchView: BaseView {
    override var rootID: String { AccessibilityID.Screen.search }

    /// Types into the search bar. SwiftUI's `.searchable` field can't take an
    /// accessibility identifier, so this is the one lookup by type (there's
    /// only ever one search field on screen).
    @discardableResult
    func typeQuery(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let field = app.searchFields.firstMatch.assertExistenceAndTap(file: file, line: line)
        field.typeText(text)
        return self
    }

    @discardableResult
    func tapResult(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.searchResult(memberID), file: file, line: line)
    }

    /// The Join / renew US Chess row under Top 100 (opens Safari, so not tapped).
    @discardableResult
    func assertJoinUSChess(file: StaticString = #filePath, line: UInt = #line) -> Self {
        assertExists(AccessibilityID.browseJoinUSChess, file: file, line: line)
    }

    @discardableResult
    func tapTop100(file: StaticString = #filePath, line: UInt = #line) -> Self {
        tap(AccessibilityID.browseTop100, file: file, line: line)
    }
}
