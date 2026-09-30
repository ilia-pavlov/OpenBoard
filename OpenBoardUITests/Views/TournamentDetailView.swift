import XCTest

final class TournamentDetailView: BaseView {
    override var rootID: String { AccessibilityID.Screen.tournament }

    @discardableResult
    func assertRegister(file: StaticString = #filePath, line: UInt = #line) -> Self {
        assertExists(AccessibilityID.tournamentRegister, timeout: 10, file: file, line: line)
    }

    @discardableResult
    func assertAddress(
        _ address: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(AccessibilityID.tournamentAddress).assertLabel(address, file: file, line: line)
        return self
    }

    /// Taps Save / Saved.
    @discardableResult
    func tapSave(file: StaticString = #filePath, line: UInt = #line) -> Self {
        tap(AccessibilityID.tournamentSave, timeout: 10, file: file, line: line)
    }

    /// The button reports its state in its accessibility label.
    @discardableResult
    func assertSaved(
        _ saved: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        element(AccessibilityID.tournamentSave)
            .assertLabel(saved ? "Saved for later" : "Save for later", timeout: 10, file: file, line: line)
        return self
    }

    /// Organizer links in the announcement stay tappable links.
    @discardableResult
    func assertAnnouncementLink(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let link = app.links[text].firstMatch
        var swipes = 0
        while !link.exists, swipes < 5 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        link.assertExistence(timeout: 1, "No '\(text)' link in the announcement", file: file, line: line)
        return self
    }

    /// Taps Copy on the announcement and checks it confirms.
    @discardableResult
    func copyAnnouncement(file: StaticString = #filePath, line: UInt = #line) -> Self {
        scrollToAndTap(AccessibilityID.copyAnnouncement, file: file, line: line)
        let button = element(AccessibilityID.copyAnnouncement)
        let copied = NSPredicate(format: "value == 'Copied'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: copied, object: button)],
                                      timeout: 3),
                       .completed, "Copy didn't confirm", file: file, line: line)
        return self
    }

    @discardableResult
    func assertDirections(file: StaticString = #filePath, line: UInt = #line) -> Self {
        scrollTo(AccessibilityID.tournamentDirections, file: file, line: line)
    }
}
