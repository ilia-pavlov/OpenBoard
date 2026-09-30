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

    /// Empties the search bar so Recent shows again.
    @discardableResult
    func clearQuery(file: StaticString = #filePath, line: UInt = #line) -> Self {
        let field = app.searchFields.firstMatch.assertExistence(file: file, line: line)
        field.buttons.firstMatch.assertExistenceAndTap(file: file, line: line) // the field's clear (x) button
        return self
    }

    /// Searches for `text` (which saves it to Recent) and clears the bar again.
    @discardableResult
    func search(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        typeQuery(text, file: file, line: line)
        sleep(1) // the search is debounced and saves to Recent once it returns
        return clearQuery(file: file, line: line)
    }

    @discardableResult
    func assertRecent(
        _ query: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.recentSearch(query), file: file, line: line)
    }

    @discardableResult
    func assertNoRecent(
        _ query: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertNotExists(AccessibilityID.recentSearch(query), file: file, line: line)
    }

    /// Swipe a recent search away.
    @discardableResult
    func removeRecent(
        _ query: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(AccessibilityID.recentSearch(query)).assertExistence(file: file, line: line).swipeLeft()
        app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch
            .assertExistenceAndTap(file: file, line: line)
        return self
    }

    @discardableResult
    func clearRecents(file: StaticString = #filePath, line: UInt = #line) -> Self {
        tap(AccessibilityID.clearRecentSearches, file: file, line: line)
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
