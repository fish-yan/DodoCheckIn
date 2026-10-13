import XCTest

final class AppUITests: XCTestCase {
    @MainActor
    func testMissionVisibilityAndDeletion() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.missions"].tap()
        let password = app.secureTextFields["settings.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("885802")
        app.buttons["settings.unlock"].tap()
        let checkbox = app.buttons["settings.enabled.wake"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        XCTAssertEqual(checkbox.value as? String, "已勾选")
        checkbox.tap()
        XCTAssertEqual(checkbox.value as? String, "未勾选")
        app.tabBars.buttons["今日打卡"].tap()
        XCTAssertFalse(app.buttons["mission.wake"].exists)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertEqual(checkbox.value as? String, "已勾选")
        app.tabBars.buttons["今日打卡"].tap()
        let wake = app.buttons["mission.wake"]
        for _ in 0..<5 where !wake.isHittable { app.swipeUp() }
        XCTAssertTrue(wake.exists)
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.edit.wake"].swipeLeft()
        let delete = app.buttons["settings.delete.wake"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(checkbox.exists)
        app.tabBars.buttons["今日打卡"].tap()
        XCTAssertFalse(app.buttons["mission.wake"].exists)
    }

    @MainActor
    func testSettingsPasswordAndNewMissionAppliesImmediately() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.missions"].tap()
        let password = app.secureTextFields["settings.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("000000")
        app.buttons["settings.unlock"].tap()
        XCTAssertTrue(app.staticTexts["家长密码不正确"].waitForExistence(timeout: 3))
        password.tap()
        password.typeText("885802")
        app.buttons["settings.unlock"].tap()
        XCTAssertTrue(app.buttons["settings.addMission"].waitForExistence(timeout: 5))
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "设置-默认打卡配置"
        list.lifetime = .keepAlways
        add(list)
        app.buttons["settings.addMission"].tap()
        let name = app.textFields["settings.mission.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("练琴UI")
        let points = app.textFields["settings.mission.points"]
        for _ in 0..<5 where !points.isHittable { app.swipeUp() }
        points.tap()
        points.typeText(XCUIKeyboardKey.delete.rawValue + "3")
        let save = app.buttons["settings.mission.save"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["settings.addMission"].waitForExistence(timeout: 5))
        let added = app.staticTexts["练琴UI"]
        for _ in 0..<5 where !added.isHittable { app.swipeUp() }
        XCTAssertTrue(added.exists)
        app.tabBars.buttons["今日打卡"].tap()
        for _ in 0..<8 where !app.staticTexts["练琴UI"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["练琴UI"].exists)
        let newMission = app.buttons.matching(NSPredicate(format: "label == %@", "练琴UI，打卡")).firstMatch
        for _ in 0..<3 where !newMission.isHittable { app.swipeUp() }
        newMission.tap()
        XCTAssertTrue(app.buttons["celebration.dismiss"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "练琴UI +3 分")).firstMatch.exists)
    }

    @MainActor
    func testRewardConfigurationValidationAndImmediateValues() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.rewards"].tap()
        let password = app.secureTextFields["settings.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("885802")
        app.buttons["settings.unlock"].tap()
        let goal = app.textFields["settings.reward.dailyGoal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "13")
        goal.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        goal.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "0")
        XCTAssertEqual(goal.value as? String, "0")
        let save = app.buttons["settings.rewards.save"]
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "日目标、奖励分数和星球步长须为")).firstMatch.waitForExistence(timeout: 3))
        for _ in 0..<5 where !goal.isHittable { app.swipeDown() }
        goal.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        goal.typeText(XCUIKeyboardKey.delete.rawValue + "15")
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["settings.rewards"].waitForExistence(timeout: 5))
        app.tabBars.buttons["今日打卡"].tap()
        XCTAssertTrue(app.staticTexts["/ 15 分"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.rewards"].tap()
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("885802")
        app.buttons["settings.unlock"].tap()
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.value as? String, "15")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "设置-奖励机制"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }


    @MainActor
    func testReadingCanPauseAndResumeBeforeFifteenMinutes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let reading = app.buttons["mission.reading"]
        for _ in 0..<12 where !reading.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reading.label.contains("开始"))
        reading.tap()
        XCTAssertTrue(reading.isEnabled)
        XCTAssertTrue(reading.label.contains("停止"))
        let detail = app.staticTexts["mission.detail.reading"]
        let ticking = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", "00:00"), object: detail
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ticking], timeout: 5), .completed)
        reading.tap()
        XCTAssertTrue(reading.label.contains("开始"))
        XCTAssertTrue(reading.isEnabled)
        XCTAssertTrue(detail.label.hasSuffix("/>15"))
        XCTAssertFalse(app.buttons["celebration.dismiss"].exists)
        let pausedTime = String(detail.label.split(separator: "/")[0])
        reading.tap()
        XCTAssertTrue(reading.label.contains("停止"))
        XCTAssertGreaterThanOrEqual(detail.label, pausedTime)
        reading.tap()
        XCTAssertTrue(reading.label.contains("开始"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "阅读分段暂停与累计时间"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testHomeKeepsTwoColumnsAndCapturesSections() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "每天一点点")).firstMatch
        for index in 0..<16 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = String(format: "native-home-scroll-%02d", index)
            attachment.lifetime = .keepAlways
            add(attachment)
            if footer.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(footer.isHittable)
        let kindness = app.buttons["mission.kindness"].frame
        let calmness = app.buttons["mission.calmness"].frame
        let honesty = app.buttons["mission.honesty"].frame
        XCTAssertEqual(kindness.minY, calmness.minY, accuracy: 1)
        XCTAssertEqual(kindness.width, calmness.width, accuracy: 1)
        XCTAssertEqual(calmness.minX, honesty.minX, accuracy: 1)
        XCTAssertLessThan(kindness.maxX, calmness.minX)
        XCTAssertLessThan(kindness.width, app.frame.width / 2)
    }

    @MainActor
    func testCompactTimedCardsShowDurationWithoutStateTags() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let breakfast = app.descendants(matching: .any).matching(identifier: "mission.breakfast").firstMatch
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(breakfast.isHittable)
        XCTAssertEqual(app.staticTexts["mission.detail.breakfast"].label, "30分钟")
        let idleTimerHeight = app.staticTexts["mission.detail.breakfast"].frame.height
        let title = app.staticTexts["mission.title.breakfast"].frame
        let points = app.staticTexts["mission.points.breakfast"].frame
        XCTAssertGreaterThan(points.minX, title.maxX)
        XCTAssertLessThan(abs(points.midY - title.midY), 6)
        XCTAssertFalse(app.staticTexts["mission.state.breakfast"].exists)
        breakfast.tap()
        XCTAssertTrue(breakfast.label.contains("结束"))
        XCTAssertGreaterThan(app.staticTexts["mission.detail.breakfast"].frame.height, idleTimerHeight)
        let departureMessage = app.staticTexts["吃早饭出发！完成后记得回来结束计时。"]
        let messageDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: departureMessage)
        XCTAssertEqual(XCTWaiter.wait(for: [messageDismissed], timeout: 6), .completed)
        let runningTimer = XCTAttachment(screenshot: app.screenshot())
        runningTimer.name = "突出显示运行计时器"
        runningTimer.lifetime = .keepAlways
        add(runningTimer)
        XCTAssertNotNil(app.staticTexts["mission.detail.breakfast"].label.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression))
        breakfast.tap()
        XCTAssertTrue(app.buttons["celebration.dismiss"].waitForExistence(timeout: 5))
        app.buttons["celebration.dismiss"].tap()
        XCTAssertNotNil(app.staticTexts["mission.detail.breakfast"].label.range(of: #"^00:\d{2}/30$"#, options: .regularExpression))
        XCTAssertTrue(breakfast.label.contains("待确认"))
        XCTAssertFalse(breakfast.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "精简计时卡片与完成用时"
        attachment.lifetime = .keepAlways
        add(attachment)
        let washing = app.staticTexts["mission.detail.washing"]
        for _ in 0..<12 where !washing.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertEqual(washing.label, "21:00前")
    }

    @MainActor
    func testListeningTaskAndSimplifiedSpending() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let listening = app.buttons["mission.listening"]
        for _ in 0..<12 where !listening.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(listening.isHittable)
        XCTAssertTrue(listening.label.contains("认真听讲，打卡"))
        let groups = XCTAttachment(screenshot: app.screenshot())
        groups.name = "知识探索站与认真听讲"
        groups.lifetime = .keepAlways
        add(groups)
        listening.tap()
        XCTAssertTrue(app.staticTexts["恭喜打卡成功！"].waitForExistence(timeout: 5))
        app.buttons["celebration.dismiss"].tap()
        XCTAssertTrue(listening.label.contains("已完成"))
        XCTAssertFalse(app.images["mission.stamp.listening"].exists)
        app.tabBars.buttons["积分消耗"].tap()
        XCTAssertTrue(app.staticTexts["spending.earned"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["spending.earned"].label, "2 分")
        XCTAssertFalse(app.staticTexts["锁屏或离开 App 仍计时，积分用完自动结束计时。"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["消耗记录"].exists)
        XCTAssertFalse(app.staticTexts["按结束时间倒序排列 · 北京时间"].exists)
        let spending = XCTAttachment(screenshot: app.screenshot())
        spending.name = "精简积分消耗页面"
        spending.lifetime = .keepAlways
        add(spending)
    }

    @MainActor
    func testCardScoresImmediatelyWithoutApprovalStamp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let task = app.buttons["mission.hygiene"]
        for _ in 0..<18 where !task.isHittable { app.swipeUp() }
        task.tap()
        XCTAssertTrue(app.buttons["celebration.dismiss"].waitForExistence(timeout: 5))
        app.buttons["celebration.dismiss"].tap()
        XCTAssertTrue(task.label.contains("已完成"))
        XCTAssertFalse(task.isEnabled)
        XCTAssertFalse(app.images["mission.stamp.hygiene"].exists)
        app.tabBars.buttons["积分消耗"].tap()
        XCTAssertTrue(app.staticTexts["spending.balance"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["spending.balance"].label, "1 分")
    }

    @MainActor
    func testParentCanSupplementMissingTaskCancelAndChildRedo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        app.buttons["parent.open"].tap()
        let selection = app.segmentedControls["review.breakfast"]
        for _ in 0..<8 where !selection.isHittable { app.swipeUp() }
        XCTAssertTrue(selection.buttons["暂不处理"].isSelected)
        selection.buttons["补打卡"].tap()
        let password = app.secureTextFields["parent.password"]
        password.tap()
        password.typeText("000000")
        app.buttons["parent.submit"].tap()
        XCTAssertTrue(app.staticTexts["parent.error"].waitForExistence(timeout: 3))
        password.tap()
        password.typeText("885802")
        app.buttons["parent.submit"].tap()
        XCTAssertTrue(app.buttons["celebration.dismiss"].waitForExistence(timeout: 5))
        app.buttons["celebration.dismiss"].tap()
        let breakfast = app.buttons["mission.breakfast"]
        for _ in 0..<8 where !breakfast.isHittable { app.swipeUp() }
        XCTAssertTrue(breakfast.label.contains("已完成"))
        XCTAssertEqual(app.staticTexts["mission.detail.breakfast"].label, "家长补打")
        app.buttons["parent.open"].tap()
        for _ in 0..<8 where !selection.isHittable { app.swipeUp() }
        XCTAssertTrue(selection.buttons["暂不处理"].isSelected)
        selection.buttons["取消打卡"].tap()
        password.tap()
        password.typeText("885802")
        app.buttons["parent.submit"].tap()
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        XCTAssertTrue(breakfast.isEnabled)
        breakfast.tap()
        XCTAssertTrue(breakfast.label.contains("结束"))
    }

    @MainActor
    func testLargeTextTaskAndCelebrationRemainUsable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let landing = XCTAttachment(screenshot: app.screenshot())
        landing.name = "最大辅助字体首页"
        landing.lifetime = .keepAlways
        add(landing)
        let mission = app.buttons["mission.toys"]
        for _ in 0..<30 where !mission.isHittable { app.swipeUp() }
        XCTAssertTrue(mission.isHittable)
        XCTAssertLessThan(mission.frame.width, app.frame.width * 0.55)
        mission.tap()
        let dismiss = app.buttons["celebration.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        for _ in 0..<5 where !dismiss.isHittable { app.swipeUp() }
        XCTAssertTrue(dismiss.isHittable)
        dismiss.tap()
    }

    @MainActor
    func testNegativeBalanceAllowsManualExpenseAndWatching() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["积分消耗"].waitForExistence(timeout: 10))
        app.tabBars.buttons["积分消耗"].tap()
        let start = app.buttons["spending.cartoon.start"]
        XCTAssertTrue(start.isEnabled)
        app.buttons["spending.manual.open"].tap()
        app.textFields["spending.manual.name"].tap()
        app.textFields["spending.manual.name"].typeText("贴纸")
        app.textFields["spending.manual.points"].tap()
        app.textFields["spending.manual.points"].typeText("5")
        app.buttons["spending.manual.submit"].tap()
        XCTAssertTrue(app.staticTexts["spending.balance"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["spending.balance"].label, "-5 分")
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.buttons["spending.cartoon.stop"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "负余额仍可记录观看"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["spending.cartoon.stop"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRulesCalendarAndHistoryAreAvailable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["parent.open"].waitForExistence(timeout: 10))
        let landing = XCTAttachment(screenshot: app.screenshot())
        landing.name = "今日打卡首页"
        landing.lifetime = .keepAlways
        add(landing)
        app.buttons["journey.open"].tap()
        XCTAssertTrue(app.staticTexts["水星"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["本月 50 分解锁"].exists)
        XCTAssertTrue(app.staticTexts["每月新旅程 · 每50分解锁一颗星球"].exists)
        let journey = XCTAttachment(screenshot: app.screenshot())
        journey.name = "八大行星探索旅程"
        journey.lifetime = .keepAlways
        add(journey)
        app.buttons["完成"].tap()
        app.buttons["计分规则"].tap()
        XCTAssertTrue(app.staticTexts["每天的小目标"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.tabBars.buttons["打卡统计"].tap()
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "等待点亮的统计页"
        empty.lifetime = .keepAlways
        add(empty)
        let detail = app.buttons["history.detail"]
        for _ in 0..<10 where !detail.isHittable { app.swipeUp() }
        XCTAssertTrue(detail.isHittable)
        detail.tap()
        XCTAssertTrue(app.staticTexts["任务记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["parent.submit"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "只读打卡详情"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
