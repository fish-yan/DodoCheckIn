import XCTest

final class SpendingUITests: XCTestCase {
    @MainActor
    func testCartoonAndManualSpendingKeepEarnedPoints() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        app.tabBars.buttons["积分消耗"].tap()
        XCTAssertFalse(app.buttons["spending.cartoon.start"].isEnabled)
        XCTAssertEqual(app.staticTexts["spending.balance"].label, "0 分")

        app.tabBars.buttons["今日打卡"].tap()
        let toys = app.buttons["mission.toys"]
        for _ in 0..<12 where !toys.isHittable { app.swipeUp() }
        toys.tap()
        app.buttons["celebration.dismiss"].tap()
        app.buttons["mission.cleaning"].tap()
        app.buttons["celebration.dismiss"].tap()
        app.buttons["parent.open"].tap()
        XCTAssertTrue(app.segmentedControls["review.toys"].buttons["确认"].isSelected)
        XCTAssertTrue(app.segmentedControls["review.cleaning"].buttons["确认"].isSelected)
        XCTAssertEqual(app.buttons["parent.submit"].label, "提交审核（2 项）")
        let password = app.secureTextFields["parent.password"]
        password.tap()
        password.typeText("885802")
        app.buttons["parent.submit"].tap()
        app.buttons["celebration.dismiss"].tap()

        app.tabBars.buttons["积分消耗"].tap()
        XCTAssertEqual(app.staticTexts["spending.earned"].label, "2 分")
        XCTAssertEqual(app.staticTexts["spending.balance"].label, "2 分")
        app.buttons["spending.cartoon.start"].tap()
        XCTAssertTrue(app.buttons["spending.cartoon.stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["spending.cartoon.start"].exists)
        let running = XCTAttachment(screenshot: app.screenshot())
        running.name = "积分消耗与动画片计时"
        running.lifetime = .keepAlways
        add(running)
        app.tabBars.buttons["打卡统计"].tap()
        app.tabBars.buttons["积分消耗"].tap()
        XCTAssertTrue(app.buttons["spending.cartoon.stop"].exists)
        app.buttons["spending.cartoon.stop"].tap()
        XCTAssertEqual(app.staticTexts["spending.spent"].label, "0 分")
        app.buttons["spending.cartoon.start"].tap()
        app.buttons["spending.cartoon.stop"].tap()

        let addManual = app.buttons["spending.manual.open"]
        for _ in 0..<6 where !addManual.isHittable { app.swipeUp() }
        addManual.tap()
        XCTAssertFalse(app.buttons["spending.manual.submit"].isEnabled)
        app.textFields["spending.manual.name"].tap()
        app.textFields["spending.manual.name"].typeText("买贴纸")
        let points = app.textFields["spending.manual.points"]
        points.tap()
        points.typeText("3")
        app.buttons["spending.manual.submit"].tap()
        XCTAssertTrue(app.staticTexts["spending.manual.error"].waitForExistence(timeout: 5))
        points.tap()
        points.typeText(XCUIKeyboardKey.delete.rawValue + "1")
        app.buttons["spending.manual.submit"].tap()
        XCTAssertTrue(app.buttons["spending.manual.open"].waitForExistence(timeout: 5))
        let balance = app.staticTexts["spending.balance"]
        for _ in 0..<5 where !balance.isHittable { app.swipeDown() }
        XCTAssertEqual(balance.label, "1 分")
        XCTAssertEqual(app.staticTexts["spending.earned"].label, "2 分")
        XCTAssertEqual(app.staticTexts["spending.spent"].label, "1 分")
        app.swipeUp()
        app.swipeUp()
        let receipt = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "expense.", "买贴纸")).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        let records = XCTAttachment(screenshot: app.screenshot())
        records.name = "手动消耗及多次观看记录"
        records.lifetime = .keepAlways
        add(records)

        app.tabBars.buttons["今日打卡"].tap()
        let earned = app.staticTexts["today.effective"]
        for _ in 0..<10 where !earned.isHittable { app.swipeDown() }
        XCTAssertEqual(earned.label, "2")
        XCTAssertFalse(app.staticTexts["打卡满分 21 · 今日合计 2 分"].exists)
        app.tabBars.buttons["打卡统计"].tap()
        XCTAssertTrue(app.staticTexts["今日战绩"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "2").count, 3)
    }

    @MainActor
    func testLargeTextSpendingFormRejectsInvalidPoints() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["积分消耗"].tap()
        XCTAssertTrue(app.staticTexts["spending.balance"].waitForExistence(timeout: 10))
        let addManual = app.buttons["spending.manual.open"]
        for _ in 0..<12 where !addManual.isHittable { app.swipeUp() }
        XCTAssertTrue(addManual.isHittable)
        addManual.tap()
        app.textFields["spending.manual.name"].tap()
        app.textFields["spending.manual.name"].typeText("贴纸")
        let points = app.textFields["spending.manual.points"]
        for _ in 0..<4 where !points.isHittable { app.swipeUp() }
        points.tap()
        points.typeText("0")
        app.buttons["spending.manual.submit"].tap()
        XCTAssertTrue(app.staticTexts["spending.manual.error"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "积分消耗大字体表单"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["取消"].tap()
    }
}
