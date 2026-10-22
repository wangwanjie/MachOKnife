//
//  MachOKnifeUITestsLaunchTests.swift
//  MachOKnifeUITests
//
//  Created by VanJay on 2026/3/21.
//

import XCTest

final class MachOKnifeUITestsLaunchTests: XCTestCase {
    // 模板默认对每种外观 / 语言配置各启动一次应用，耗时成倍增加却没有任何断言；
    // 这里只在默认配置下启动一次，并真正校验主窗口出现后再截图。
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() throws {
        let app = XCUIApplication()
        // 忽略上次退出时保存的窗口状态，保证每次都从干净的启动状态开始。
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Expected the main window to appear after launch"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
