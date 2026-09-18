import XCTest

final class CrosstableView: BaseView {
    override var rootID: String { AccessibilityID.Screen.crosstable }

    @discardableResult
    func assertStanding(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExists(AccessibilityID.standing(memberID), timeout: 10, file: file, line: line)
    }

    /// Expands (or collapses) a player's rounds.
    @discardableResult
    func tapStanding(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.standing(memberID), file: file, line: line)
    }

    /// In an expanded row: "View full profile".
    @discardableResult
    func tapViewFullProfile(
        _ memberID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.viewFullProfile(memberID), file: file, line: line)
    }

    @discardableResult
    func openSectionPicker(file: StaticString = #filePath, line: UInt = #line) -> Self {
        tap(AccessibilityID.sectionMenu, file: file, line: line)
    }

    /// In the section sheet: the option shows the section's full name.
    @discardableResult
    func assertSectionOption(
        _ index: Int,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let option = element(AccessibilityID.sectionOption(index)).assertExistence(file: file, line: line)
        XCTAssertTrue(option.label.contains(name), "Section \(index) label '\(option.label)' lacks '\(name)'",
                      file: file, line: line)
        return self
    }

    @discardableResult
    func chooseSection(
        _ index: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.sectionOption(index), file: file, line: line)
    }
}
