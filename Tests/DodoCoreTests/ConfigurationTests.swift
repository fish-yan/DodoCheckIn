import Foundation
import Testing
@testable import DodoCore

private func customTask(_ id: String = "custom-exercise", rule: MissionRuleConfiguration = .init(), points: Int = 3) -> MissionConfiguration {
    MissionConfiguration(id: id, name: "运动", iconID: "reading", group: "勇气成长站", rule: rule, points: points)
}

@Test func legacyConfigurationsDefaultToEnabled() throws {
    let data = try JSONEncoder().encode(MissionConfiguration.defaults)
    // Optional visibility is omitted when encoding an untouched legacy configuration.
    #expect(!String(decoding: data, as: UTF8.self).contains("isHidden"))
    let configurations = try JSONDecoder().decode([MissionConfiguration].self, from: data)
    #expect(configurations.count == 17)
    #expect(configurations.allSatisfy { $0.isEnabled })
}

@Test func genericIconCanBeSavedWithoutAddingADefaultMission() throws {
    let now = instant("2026-10-08")
    var journal = Journal(now: now)
    var configuration = customTask()
    configuration.iconID = Mission.genericIcon.rawValue
    try ConfigurationEngine.saveMission(configuration, password: "885802", now: now, journal: &journal)
    journal = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    let task = try #require(journal.visibleMissions(on: "2026-10-08").first { $0.rawValue == configuration.id })
    #expect(task.configuration?.iconID == "generic")
    #expect(Mission.selectableIcons.contains(.genericIcon))
    #expect(MissionConfiguration.defaults.count == 17)
    #expect(!Mission.allCases.contains(.genericIcon))
    _ = try CheckInEngine.tap(task, day: "2026-10-08", now: now, isRestDay: false, journal: &journal)
    #expect(journal.effectiveScore(on: "2026-10-08") == 3)
}

@Test func hidingAndDeletingMissionsPreservesRecordsAndScores() throws {
    let day = "2026-10-08"
    let now = instant(day, 12)
    var journal = Journal(now: instant("2026-10-07"))
    ConfigurationEngine.adopt(&journal, now: instant("2026-10-07"))
    _ = try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: false, journal: &journal)
    let original = journal.records
    let score = journal.totalPoints
    try ConfigurationEngine.setMissionEnabled("toys", enabled: false, password: "885802", now: now, journal: &journal)
    #expect(!journal.visibleMissions(on: day).contains(.toys))
    #expect(journal.missions(on: day).contains(.toys))
    #expect(journal.visibleMissions(on: "2026-10-07").contains(.toys))
    #expect(journal.records == original)
    #expect(journal.totalPoints == score)
    #expect(throws: CheckInError.unavailable) {
        try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: false, journal: &journal)
    }
    journal = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    #expect(!journal.visibleMissions(on: day).contains(.toys))
    try ConfigurationEngine.setMissionEnabled("toys", enabled: true, password: "885802", now: now, journal: &journal)
    #expect(journal.visibleMissions(on: day).contains(.toys))
    #expect(journal.record(.toys, day: day)?.isEffective == true)
    try ConfigurationEngine.deleteMission("toys", password: "885802", now: now, journal: &journal)
    #expect(journal.records == original)
    #expect(journal.totalPoints == score)
    #expect(!journal.visibleMissions(on: day).contains(.toys))
    #expect(!journal.visibleMissions(on: "2026-10-09").contains(.toys))
    #expect(journal.missions(on: day).contains(.toys))
    #expect(journal.visibleMissions(on: "2026-10-07").contains(.toys))
    let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: now), now: now)
    #expect(stats.count == 1)
    #expect(stats.topMissions == [.toys])
    _ = try CheckInEngine.review(day: day, decisions: [.toys: .cancel], password: "885802", now: now, journal: &journal)
    #expect(journal.totalPoints == 0)
}

@Test func deletingAllMissionsKeepsEmptyCatalogAfterReloadAndRequiresPassword() throws {
    let now = instant("2026-10-08")
    var journal = Journal(now: now)
    ConfigurationEngine.adopt(&journal, now: now)
    let original = journal
    #expect(throws: CheckInError.wrongPassword) {
        try ConfigurationEngine.deleteMission("toys", password: "000000", now: now, journal: &journal)
    }
    #expect(throws: CheckInError.wrongPassword) {
        try ConfigurationEngine.setMissionEnabled("toys", enabled: false, password: "000000", now: now, journal: &journal)
    }
    #expect(journal == original)
    for task in Mission.allCases {
        try ConfigurationEngine.deleteMission(task.rawValue, password: "885802", now: now, journal: &journal)
    }
    journal = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    #expect(journal.visibleMissions(on: "2026-10-08").isEmpty)
    #expect(journal.visibleMissions(on: "2026-10-09").isEmpty)
}

@Test func configurationAppliesImmediatelyAndKeepsExistingCatalogAndScores() throws {
    let today = instant("2026-10-07", 12)
    var journal = Journal(now: today)
    _ = try CheckInEngine.tap(.toys, day: "2026-10-07", now: today, isRestDay: false, journal: &journal)
    _ = try CheckInEngine.review(day: "2026-10-07", decisions: [.toys: .makeup], password: "885802", now: today, journal: &journal)
    ConfigurationEngine.adopt(&journal, now: today)
    var toy = try #require(MissionConfiguration.defaults.first { $0.id == "toys" })
    toy.name = "整理房间"
    toy.points = 8
    toy.group = "知识探索站"
    try ConfigurationEngine.saveMission(toy, password: "885802", now: today, journal: &journal)
    try ConfigurationEngine.saveMission(customTask(), password: "885802", now: today, journal: &journal)
    try ConfigurationEngine.saveRewards(dailyGoal: 1, week: .init(days: 3, points: 20), month: .init(days: 10, points: 80, planetStep: 20), password: "885802", now: today, journal: &journal)
    #expect(journal.missions(on: "2026-10-07").count == 18)
    #expect(journal.missions(on: "2026-10-08").count == 18)
    #expect(journal.record(.toys, day: "2026-10-07")?.mission.title == "收拾玩具")
    #expect(journal.effectiveScore(on: "2026-10-07") == 1)
    #expect(journal.dailyGoal(on: "2026-10-07") == 1)
    #expect(journal.dailyGoal(on: "2026-10-08") == 1)
    #expect(journal.weeklyReward(on: "2026-10-07")?.days == 3)
    #expect(journal.weeklyReward(on: "2026-10-12")?.days == 3)
    #expect(journal.monthlyReward(on: "2026-10-07")?.planetStep == 20)
    #expect(journal.monthlyReward(on: "2026-11-01")?.planetStep == 20)
    _ = try CheckInEngine.tap(.toys, day: "2026-10-08", now: instant("2026-10-08", 12), isRestDay: false, journal: &journal)
    #expect(journal.record(.toys, day: "2026-10-08")?.mission.title == "整理房间")
    #expect(journal.record(.toys, day: "2026-10-08")?.points == 8)
    let custom = Mission(rawValue: "custom-exercise")
    _ = try CheckInEngine.tap(custom, day: "2026-10-08", now: instant("2026-10-08", 12), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.review(day: "2026-10-08", decisions: [custom: .makeup], password: "885802", now: instant("2026-10-08", 12), journal: &journal)
    let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: today), now: instant("2026-10-08", 12))
    #expect(stats.count == 3)
    #expect(stats.effectivePoints == 12)
    #expect(stats.expectedCount == 36)
    #expect(stats.topMissions.contains(custom))
    #expect(journal.totalPoints == 12)
}

@Test func accumulatingTimerKeepsPriorPointsAndImmediatelyAwardsIncrement() throws {
    let setup = instant("2026-10-07")
    let day = "2026-10-08"
    let start = instant(day, 12)
    var journal = Journal(now: setup)
    var rule = MissionRuleConfiguration(kind: .timer)
    rule.comparison = .greater
    rule.minutes = 15
    try ConfigurationEngine.saveMission(customTask(rule: rule, points: 2), password: "885802", now: setup, journal: &journal)
    let task = Mission(rawValue: "custom-exercise")
    #expect(try CheckInEngine.tap(task, day: day, now: start, isRestDay: false, journal: &journal) == .started)
    #expect(try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(600), isRestDay: false, journal: &journal) == .paused)
    _ = try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(3600), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(3900), isRestDay: false, journal: &journal)
    #expect(journal.selfScore(on: day) == 2) // Exactly 15 accumulated minutes, excluding the break.
    #expect(journal.effectiveScore(on: day) == 2)
    _ = try CheckInEngine.review(day: day, decisions: [task: .makeup], password: "885802", now: start.addingTimeInterval(3900), journal: &journal)
    // A completed custom timer remains restartable after loading saved data.
    journal = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    #expect(try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(4000), isRestDay: false, journal: &journal) == .started)
    #expect(journal.effectiveScore(on: day) == 2)
    #expect(journal.totalPoints == 2)
    journal = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    #expect(try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(5900), isRestDay: false, journal: &journal) == .completed)
    #expect(journal.selfScore(on: day) == 6) // 2800 / 900 floors to 3.
    #expect(journal.effectiveScore(on: day) == 6)
    #expect(journal.record(task, day: day)?.pendingPoints == 0)
    #expect(journal.record(task, day: day)?.isEffective == true)
    _ = try CheckInEngine.review(day: day, decisions: [task: .makeup], password: "885802", now: start.addingTimeInterval(5900), journal: &journal)
    #expect(journal.effectiveScore(on: day) == 6)
    #expect(PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: start), now: start.addingTimeInterval(6000)).count == 1)
    let unchanged = journal
    _ = try CheckInEngine.review(day: day, decisions: [task: .makeup], password: "885802", now: start.addingTimeInterval(6000), journal: &journal)
    #expect(journal == unchanged)
    _ = try CheckInEngine.review(day: day, decisions: [task: .cancel], password: "885802", now: start.addingTimeInterval(6000), journal: &journal)
    #expect(journal.totalPoints == 0)
    _ = try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(6100), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(task, day: day, now: start.addingTimeInterval(6400), isRestDay: false, journal: &journal)
    #expect(journal.record(task, day: day)?.readingDuration(at: start.addingTimeInterval(7000)) == 300)
    #expect(journal.selfScore(on: day) == 0)
}

@Test(arguments: [1799, 1800, 1859, 1860])
func configuredEqualityUsesWholeMinutes(seconds: Int) throws {
    var journal = Journal(now: instant("2026-10-07"))
    var rule = MissionRuleConfiguration(kind: .timer)
    rule.comparison = .equal
    rule.minutes = 30
    try ConfigurationEngine.saveMission(customTask(rule: rule), password: "885802", now: instant("2026-10-07"), journal: &journal)
    let start = instant("2026-10-08", 12)
    let task = Mission(rawValue: "custom-exercise")
    _ = try CheckInEngine.tap(task, day: "2026-10-08", now: start, isRestDay: false, journal: &journal)
    _ = try? CheckInEngine.tap(task, day: "2026-10-08", now: start.addingTimeInterval(Double(seconds)), isRestDay: false, journal: &journal)
    #expect(journal.selfScore(on: "2026-10-08") == ((1800..<1860).contains(seconds) ? 3 : 0))
}

@Test(arguments: [false, true])
func configuredLessBoundaryAndLegacyDefaults(inclusive: Bool) throws {
    var journal = Journal(now: instant("2026-10-07"))
    var rule = MissionRuleConfiguration(kind: .timer)
    rule.includesTimerLimit = inclusive
    try ConfigurationEngine.saveMission(customTask(rule: rule), password: "885802", now: instant("2026-10-07"), journal: &journal)
    let start = instant("2026-10-08", 12)
    let task = Mission(rawValue: "custom-exercise")
    _ = try CheckInEngine.tap(task, day: "2026-10-08", now: start, isRestDay: false, journal: &journal)
    _ = try? CheckInEngine.tap(task, day: "2026-10-08", now: start.addingTimeInterval(1800), isRestDay: false, journal: &journal)
    #expect(journal.selfScore(on: "2026-10-08") == (inclusive ? 3 : 0))
    #expect(MissionConfiguration.defaults.first { $0.id == "breakfast" }?.rule.includesTimerLimit == true)
}

@Test(arguments: [30540, 30600, 32400, 32401])
func configuredTimeWindowBounds(seconds: Int) throws {
    var journal = Journal(now: instant("2026-10-07"))
    var rule = MissionRuleConfiguration(kind: .timeWindow)
    rule.startMinute = 8 * 60 + 30
    rule.endMinute = 9 * 60
    try ConfigurationEngine.saveMission(customTask(rule: rule), password: "885802", now: instant("2026-10-07"), journal: &journal)
    _ = try CheckInEngine.tap(Mission(rawValue: "custom-exercise"), day: "2026-10-08", now: BeijingCalendar.date("2026-10-08")!.addingTimeInterval(Double(seconds)), isRestDay: false, journal: &journal)
    #expect(journal.selfScore(on: "2026-10-08") == ((30600...32400).contains(seconds) ? 3 : 0))
}

@Test func configuredRewardsApplyImmediatelyAndSnapshotAmounts() throws {
    let setup = instant("2026-09-30")
    var journal = Journal(now: instant("2026-09-01"))
    let old = Reward(period: "2026-09", stage: .month25, awardedAt: setup)
    journal.rewards.append(old)
    try ConfigurationEngine.saveRewards(dailyGoal: 13, week: .init(days: 2, points: 23), month: .init(days: 2, points: 77, planetStep: 20), password: "885802", now: setup, journal: &journal)
    for day in ["2026-10-05", "2026-10-06"] { addGoalDay(day, to: &journal) }
    let now = instant("2026-10-06", 22)
    let granted = RewardEngine.settle(&journal, now: now)
    #expect(Set(granted.map(\.points)) == [23, 77])
    #expect(granted.allSatisfy { $0.stage != .monthFull })
    #expect(RewardEngine.settle(&journal, now: now).isEmpty)
    #expect(journal.rewards.first?.points == 50)
    #expect(journal.exploration(in: now).step == 20)
    try ConfigurationEngine.saveRewards(dailyGoal: 100, week: .init(days: 7, points: 300), month: .init(days: 25, points: 400, planetStep: 100), password: "885802", now: now, journal: &journal)
    #expect(journal.rewards.map(\.points) == [50, 23, 77])
    #expect(RewardEngine.revokeUnqualifiedToday(&journal, now: now).isEmpty)
    #expect(journal.exploration(in: now).step == 100)
    #expect(journal.exploration(in: instant("2026-11-01")).step == 100)
    #expect(journal.dailyGoal(on: "2026-10-05") == 13)
    #expect(journal.dailyGoal(on: "2026-10-06") == 100)
    let restored = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    #expect(restored == journal)
}

@Test(arguments: ["2027-02-01", "2028-02-01", "2026-04-01", "2026-05-01"])
func configuredMonthlyRewardIsSingleAndCapsDaysAtMonthLength(firstDay: String) throws {
    let first = BeijingCalendar.date(firstDay)!
    let setup = first.addingTimeInterval(-3600)
    var journal = Journal(now: setup)
    try ConfigurationEngine.saveRewards(dailyGoal: 13, week: .init(), month: .init(days: 31, points: 80, planetStep: 50), password: "885802", now: setup, journal: &journal)
    let days = BeijingCalendar.days(in: BeijingCalendar.month(containing: first))
    for day in days {
        addGoalDay(day, to: &journal)
        _ = RewardEngine.settle(&journal, now: instant(day, 21))
    }
    let monthly = journal.rewards.filter { $0.stage != .week }
    #expect(monthly.count == 1)
    #expect(monthly.first?.points == 80)
    #expect(monthly.first?.day == days.last)
}

@Test func configurationValidationAndRepeatedSavesAreAtomic() throws {
    let now = instant("2026-10-07")
    var journal = Journal(now: now)
    let original = journal
    #expect(throws: CheckInError.wrongPassword) {
        try ConfigurationEngine.saveMission(customTask(), password: "wrong", now: now, journal: &journal)
    }
    #expect(journal == original)
    var invalid = customTask()
    invalid.points = 0
    #expect(throws: ConfigurationError.invalidMission) {
        try ConfigurationEngine.saveMission(invalid, password: "885802", now: now, journal: &journal)
    }
    #expect(journal == original)
    try ConfigurationEngine.saveMission(customTask(), password: "885802", now: now, journal: &journal)
    var edited = customTask()
    edited.points = 4
    try ConfigurationEngine.saveMission(edited, password: "885802", now: now, journal: &journal)
    #expect(journal.configuration?.missions.count == 1)
    #expect(journal.missions(on: "2026-10-08").count == 18)
    #expect(throws: ConfigurationError.duplicateName) {
        try ConfigurationEngine.saveMission(customTask("custom-other"), password: "885802", now: now, journal: &journal)
    }
}

@Test @MainActor
func configuredTimerAndLegacyDataSurviveDiskReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("journal.store")
    let setup = instant("2026-10-07")
    let start = instant("2026-10-08", 12)
    do {
        let persistence = try JournalPersistence(now: setup, url: url)
        var journal = persistence.journal
        addGoalDay("2026-10-07", to: &journal)
        ConfigurationEngine.adopt(&journal, now: setup)
        _ = try CheckInEngine.tap(.reading, day: "2026-10-08", now: start, isRestDay: false, journal: &journal)
        _ = try CheckInEngine.tap(.reading, day: "2026-10-08", now: start.addingTimeInterval(900), isRestDay: false, journal: &journal)
        _ = try CheckInEngine.review(day: "2026-10-08", decisions: [.reading: .makeup], password: "885802", now: start.addingTimeInterval(900), journal: &journal)
        _ = try CheckInEngine.tap(.reading, day: "2026-10-08", now: start.addingTimeInterval(1800), isRestDay: false, journal: &journal)
        try persistence.commit(journal)
    }
    let persistence = try JournalPersistence(now: start.addingTimeInterval(2700), url: url)
    var reopened = persistence.journal
    #expect(reopened.schemaVersion == 2)
    #expect(reopened.isGoalMet(on: "2026-10-07"))
    #expect(reopened.effectiveScore(on: "2026-10-08") == 2)
    _ = try CheckInEngine.tap(.reading, day: "2026-10-08", now: start.addingTimeInterval(2700), isRestDay: false, journal: &reopened)
    #expect(reopened.selfScore(on: "2026-10-08") == 4)
    #expect(reopened.effectiveScore(on: "2026-10-08") == 4)
    _ = try CheckInEngine.tap(.reading, day: "2026-10-08", now: instant("2026-10-08", 23, 58), isRestDay: false, journal: &reopened)
    CheckInEngine.reconcile(&reopened, now: instant("2026-10-09", 0))
    #expect(reopened.selfScore(on: "2026-10-08") == 4)
    #expect(reopened.effectiveScore(on: "2026-10-08") == 4)
}

@Test func immediateEditsPreserveRunningPausedAndConfirmedSnapshots() throws {
    let now = instant("2026-10-07", 12)
    let day = BeijingCalendar.key(now)
    var journal = Journal(now: now)
    var rule = MissionRuleConfiguration(kind: .timer)
    rule.comparison = .greater
    rule.minutes = 15
    var task = customTask(rule: rule, points: 2)
    try ConfigurationEngine.saveMission(task, password: "885802", now: now, journal: &journal)
    let mission = Mission(rawValue: task.id)
    _ = try CheckInEngine.tap(mission, day: day, now: now, isRestDay: false, journal: &journal)
    let original = journal.record(mission, day: day)
    task.name = "新运动"
    task.rule.minutes = 1
    task.points = 10
    try ConfigurationEngine.saveMission(task, password: "885802", now: now.addingTimeInterval(1), journal: &journal)
    #expect(journal.record(mission, day: day) == original)
    #expect(journal.missions(on: day).first { $0 == mission }?.title == "运动")
    _ = try CheckInEngine.tap(mission, day: day, now: now.addingTimeInterval(600), isRestDay: false, journal: &journal)
    #expect(journal.selfScore(on: day) == 0)
    #expect(journal.record(mission, day: day)?.latest?.outcome == .paused)
    _ = try CheckInEngine.tap(mission, day: day, now: now.addingTimeInterval(700), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(mission, day: day, now: now.addingTimeInterval(1000), isRestDay: false, journal: &journal)
    #expect(journal.selfScore(on: day) == 2)
    _ = try CheckInEngine.review(day: day, decisions: [mission: .makeup], password: "885802", now: now.addingTimeInterval(1000), journal: &journal)
    let confirmed = journal.record(mission, day: day)
    task.points = 20
    try ConfigurationEngine.saveMission(task, password: "885802", now: now.addingTimeInterval(1001), journal: &journal)
    #expect(journal.record(mission, day: day) == confirmed)
    #expect(journal.effectiveScore(on: day) == 2)
    #expect(journal.missions(on: "2026-10-08").first { $0 == mission }?.points == 20)
    let restored = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    #expect(restored.record(mission, day: day)?.mission.configuration?.rule.minutes == 15)
}

@Test func immediateRewardsSettleValidPointsAndKeepAwardedRulesUntilCancellation() throws {
    let now = instant("2026-10-07", 12)
    let day = BeijingCalendar.key(now)
    var journal = Journal(now: now)
    _ = try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: false, journal: &journal)
    try ConfigurationEngine.saveRewards(dailyGoal: 1, week: .init(days: 1, points: 10), month: .init(days: 1, points: 50, planetStep: 20), password: "885802", now: now, journal: &journal)
    #expect(journal.rewards.map(\.points) == [10, 50])
    _ = try CheckInEngine.review(day: day, decisions: [.toys: .makeup], password: "885802", now: now, journal: &journal)
    #expect(journal.rewards.map(\.points) == [10, 50])
    let awarded = journal.rewards
    try ConfigurationEngine.saveRewards(dailyGoal: 100, week: .init(days: 7, points: 99), month: .init(days: 25, points: 200, planetStep: 100), password: "885802", now: now, journal: &journal)
    #expect(journal.rewards == awarded)
    _ = try CheckInEngine.tap(.cleaning, day: day, now: now, isRestDay: false, journal: &journal)
    _ = try CheckInEngine.review(day: day, decisions: [.cleaning: .makeup], password: "885802", now: now, journal: &journal)
    #expect(journal.rewards == awarded)
    #expect(journal.effectiveScore(on: day) == 2)
    _ = try CheckInEngine.review(day: day, decisions: [.cleaning: .cancel, .toys: .cancel], password: "885802", now: now, journal: &journal)
    #expect(journal.rewards.isEmpty)
}

@Test func savingImmediateConfigurationReplacesPendingVersionsWithoutChangingHistory() throws {
    let now = instant("2026-10-07", 12)
    var journal = Journal(now: instant("2026-10-06"))
    addGoalDay("2026-10-06", to: &journal)
    var pending = MissionConfiguration.defaults
    pending.append(customTask("pending-exercise"))
    journal.configuration = ConfigurationSchedule(
        missions: [.init(effectiveDay: "2026-10-08", value: pending)],
        dailyGoals: [.init(effectiveDay: "2026-10-08", value: 50)],
        weeks: [.init(effectiveDay: "2026-10-12", value: .init(days: 6, points: 60))],
        months: [.init(effectiveDay: "2026-11-01", value: .init(days: 20, points: 100, planetStep: 70))])
    let history = journal.records
    var newTask = customTask("new-task")
    newTask.name = "新项目"
    try ConfigurationEngine.saveMission(newTask, password: "885802", now: now, journal: &journal)
    #expect(journal.missions(on: "2026-10-07").count == 19)
    #expect(journal.missions(on: "2026-10-08").count == 19)
    try ConfigurationEngine.saveRewards(dailyGoal: 1, week: .init(days: 1, points: 20), month: .init(days: 1, points: 40, planetStep: 10), password: "885802", now: now, journal: &journal)
    #expect(journal.records == history)
    #expect(journal.dailyGoal(on: "2026-10-06") == 13)
    #expect(journal.dailyGoal(on: "2026-10-07") == 1)
    #expect(journal.dailyGoal(on: "2026-10-08") == 1)
    #expect(journal.weeklyReward(on: "2026-10-12")?.points == 20)
    #expect(journal.monthlyReward(on: "2026-11-01")?.planetStep == 10)
    #expect(journal.rewards.map(\.points) == [20, 40])
    let rewards = journal.rewards
    try ConfigurationEngine.saveRewards(dailyGoal: 1, week: .init(days: 1, points: 20), month: .init(days: 1, points: 40, planetStep: 10), password: "885802", now: now, journal: &journal)
    #expect(journal.rewards == rewards)
}
