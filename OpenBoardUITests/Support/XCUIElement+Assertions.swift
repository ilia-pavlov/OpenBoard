import XCTest

extension XCUIElement {
    /// Waits for the element and fails the test (at the caller's line) if it never appears.
    @MainActor
    @discardableResult
    func assertExistence(
        timeout: TimeInterval = 5,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let text = message()
        XCTAssertTrue(waitForExistence(timeout: timeout),
                      text.isEmpty ? "Expected to exist: \(description)" : text,
                      file: file, line: line)
        return self
    }

    /// `assertExistence`, then tap.
    @MainActor
    @discardableResult
    func assertExistenceAndTap(
        timeout: TimeInterval = 5,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExistence(timeout: timeout, message(), file: file, line: line)
        tap()
        return self
    }

    /// Fails if the element is (still) present after `timeout`.
    @MainActor
    @discardableResult
    func assertNonExistence(
        timeout: TimeInterval = 2,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        let text = message()
        XCTAssertTrue(waitForNonExistence(timeout: timeout),
                      text.isEmpty ? "Expected not to exist: \(description)" : text,
                      file: file, line: line)
        return self
    }

    /// Fails unless the element exists and its label is `expected`.
    @MainActor
    @discardableResult
    func assertLabel(
        _ expected: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        assertExistence(timeout: timeout, file: file, line: line)
        XCTAssertEqual(label, expected, file: file, line: line)
        return self
    }
}
