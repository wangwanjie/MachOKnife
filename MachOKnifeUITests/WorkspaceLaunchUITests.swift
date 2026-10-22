import XCTest

final class WorkspaceLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsEmptyStatePrompt() throws {
        let app = XCUIApplication()
        // 忽略窗口状态恢复：若上次退出时打开过文件，恢复的窗口可能不显示空状态，导致用例偶发失败。
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["workspace.empty.title"].waitForExistence(timeout: 10),
            "Expected the empty-state title to be visible after launch"
        )
        // 按钮与标题可能不在同一帧完成布局，用 waitForExistence 代替立即读取 exists，避免时序抖动。
        let openButton = app.buttons["workspace.empty.openButton"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 5),
            "Expected the empty-state open button to be visible after launch"
        )
        XCTAssertTrue(openButton.isEnabled, "Expected the empty-state open button to be enabled")
    }
}
