import XCTest

final class WorkspaceLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsEmptyStatePrompt() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["workspace.empty.title"].waitForExistence(timeout: 5),
            "Expected the empty-state title to be visible after launch"
        )
        XCTAssertTrue(
            app.buttons["workspace.empty.openButton"].exists,
            "Expected the empty-state open button to be visible after launch"
        )
    }
}
