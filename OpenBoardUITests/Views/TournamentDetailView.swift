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

    @discardableResult
    func assertDirections(file: StaticString = #filePath, line: UInt = #line) -> Self {
        scrollTo(AccessibilityID.tournamentDirections, file: file, line: line)
    }
}
