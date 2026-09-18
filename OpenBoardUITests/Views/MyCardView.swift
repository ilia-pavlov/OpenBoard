import XCTest

final class MyCardView: BaseView {
    override var rootID: String { AccessibilityID.Screen.myCard }

    /// The big Regular card; opens Rating History.
    @discardableResult
    func tapHeroCard(file: StaticString = #filePath, line: UInt = #line) -> Self {
        tap(AccessibilityID.heroRatingCard, file: file, line: line)
    }

    @discardableResult
    func assertTopBadge(
        _ listID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.topBadge(listID), file: file, line: line)
    }
}
