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

    @discardableResult
    func assertDirections(file: StaticString = #filePath, line: UInt = #line) -> Self {
        scrollTo(AccessibilityID.tournamentDirections, file: file, line: line)
    }
}
