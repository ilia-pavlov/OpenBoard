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
