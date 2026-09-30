import XCTest

/// Base for screen objects. Elements are found by accessibility identifier only
/// (`AccessibilityID`, shared with the app). Every action/assertion returns `Self`
/// so steps chain:
///
///     profile.assertOnScreen().selectSegment("profile", "history").tapHistoryEvent(id)
@MainActor
class BaseView {
    let app: XCUIApplication

    required init(_ app: XCUIApplication) {
        self.app = app
    }

    /// The screen's root container ID; subclasses override.
    var rootID: String { preconditionFailure("\(Self.self) must override rootID") }

    /// The element with this accessibility identifier (any type).
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    // MARK: - Screen

    @discardableResult
    func assertOnScreen(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(rootID).assertExistence(timeout: timeout, "\(Self.self) is not showing (\(rootID))",
                                        file: file, line: line)
        return self
    }

    @discardableResult
    func goBack(file: StaticString = #filePath, line: UInt = #line) -> Self {
        app.navigationBars.buttons[AccessibilityID.backButton].firstMatch
            .assertExistenceAndTap(file: file, line: line)
        return self
    }

    // MARK: - Elements by ID

    @discardableResult
    func assertExists(
        _ id: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(id).assertExistence(timeout: timeout, "Missing element '\(id)'", file: file, line: line)
        return self
    }

    @discardableResult
    func assertNotExists(
        _ id: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(id).assertNonExistence(timeout: timeout, "Unexpected element '\(id)'", file: file, line: line)
        return self
    }

    @discardableResult
    func tap(
        _ id: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(id).assertExistenceAndTap(timeout: timeout, "Can't tap missing element '\(id)'",
                                          file: file, line: line)
        return self
    }

    /// Swipes up until the element is on screen (for rows below the fold), then asserts it.
    @discardableResult
    func scrollTo(
        _ id: String,
        maxSwipes: Int = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let target = element(id)
        var swipes = 0
        while !(target.exists && target.isHittable), swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        target.assertExistence(timeout: 1, "Couldn't scroll to '\(id)'", file: file, line: line)
        return self
    }

    @discardableResult
    func scrollToAndTap(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollTo(id, file: file, line: line)
        element(id).tap()
        return self
    }

    /// Where the element sits on screen, to check a list kept its scroll position.
    func top(of id: String) -> CGFloat {
        element(id).frame.minY
    }

    /// The row opened last is marked selected when the user comes back to the list.
    @discardableResult
    func assertSelected(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let row = element(id).assertExistence(file: file, line: line)
        XCTAssertTrue(row.isSelected, "'\(id)' isn't marked as last opened", file: file, line: line)
        return self
    }

    @discardableResult
    func assertNotSelected(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let row = element(id).assertExistence(file: file, line: line)
        XCTAssertFalse(row.isSelected, "'\(id)' is still highlighted", file: file, line: line)
        return self
    }

    /// Opens the row, comes back, and checks the list didn't move and the row is
    /// marked: the "back keeps my place" behavior every event list shares.
    /// `choosing` names the menu item to pick when the row opens a menu;
    /// `marked: false` for rows that don't mark the last one opened.
    @discardableResult
    func assertBackKeepsPlace(
        of id: String,
        choosing menuItem: String? = nil,
        marked: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollTo(id, file: file, line: line)
        // Pull the row up to mid-screen so the list is really scrolled: at the
        // very top there is no position to lose.
        let screenHeight = app.windows.firstMatch.frame.height
        var drags = 0
        while top(of: id) > screenHeight * 0.45, drags < 6 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            drags += 1
        }
        let before = top(of: id)
        element(id).tap()
        if let menuItem { tap(menuItem, file: file, line: line) }
        goBack(file: file, line: line)
        element(id).assertExistence(file: file, line: line)
        XCTAssertEqual(top(of: id), before, accuracy: 1, "List moved after coming back", file: file, line: line)
        if marked { assertSelected(id, file: file, line: line) }
        return self
    }

    // MARK: - Best wins (My Card and player profiles)

    /// A Best wins row, found by the opponent's member ID; `mentions` are parts
    /// of its spoken label (name, rating, Top 100 rank).
    @discardableResult
    func assertBestWin(
        _ opponentID: String,
        mentions parts: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollTo(AccessibilityID.bestWin(opponentID), file: file, line: line)
        let label = element(AccessibilityID.bestWin(opponentID)).label
        for part in parts {
            XCTAssertTrue(label.contains(part), "Best win '\(label)' lacks '\(part)'", file: file, line: line)
        }
        return self
    }

    /// Taps a win and picks "Open tournament" from its menu.
    @discardableResult
    func tapBestWin(
        _ opponentID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.bestWin(opponentID), file: file, line: line)
        return tap(AccessibilityID.bestWinTournament, file: file, line: line)
    }

    /// Taps a win and picks "View <name>'s profile" from its menu.
    @discardableResult
    func tapBestWinProfile(
        _ opponentID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        scrollToAndTap(AccessibilityID.bestWin(opponentID), file: file, line: line)
        return tap(AccessibilityID.bestWinProfile, file: file, line: line)
    }

    @discardableResult
    func openBestWinsInfo(file: StaticString = #filePath, line: UInt = #line) -> Self {
        scrollToAndTap(AccessibilityID.bestWinsInfo, file: file, line: line)
        return assertExists(AccessibilityID.bestWinsInfoPopover, file: file, line: line)
    }

    // MARK: - Tabs

    /// Switches tabs by visible label. Tab bar buttons are the one documented
    /// exception to IDs-only lookup — SwiftUI won't set an identifier on them.
    /// Tests normally start on the tab they need via `-screen`; this is for the
    /// flows that have to cross tabs in a single launch, because the mock store
    /// is in-memory and a relaunch would wipe what the test just created.
    @discardableResult
    func selectTab(
        _ title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        app.buttons[title].firstMatch
            .assertExistenceAndTap(timeout: 10, "No tab button '\(title)'", file: file, line: line)
        return self
    }

    // MARK: - Shared controls

    /// Taps a segmented-control item, e.g. `selectSegment("profile", "history")`.
    @discardableResult
    func selectSegment(
        _ control: String,
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.segment(control, value), file: file, line: line)
    }

    /// Opens a filter chip and picks an option, e.g. `selectFilter("result", "down")`.
    @discardableResult
    func selectFilter(
        _ name: String,
        _ option: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        tap(AccessibilityID.filter(name), file: file, line: line)
        return tap(AccessibilityID.filterOption(name, option), file: file, line: line)
    }
}
