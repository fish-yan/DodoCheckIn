import Foundation
import Testing
@testable import DodoCore

@Test func upgradingPreservesPastGoalsAndUsesDailyCatalogForRates() throws {
    let start = "2026-09-14"
    let upgradeDay = "2026-09-20" // Sunday: six legacy days plus one new day.
    let now = instant(upgradeDay, 20)
    var legacy = Journal(now: instant(start))
    for day in BeijingCalendar.days(in: BeijingCalendar.week(containing: now)) {
        addGoalDay(day, to: &legacy)
    }
    legacy.records.removeAll { $0.mission == .hygiene || $0.mission == .dressing }
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
    json.removeValue(forKey: "expandedRulesStartDay")
    json.removeValue(forKey: "listeningStartDay")
    var journal = try JSONDecoder().decode(Journal.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(journal.expandedRulesStartDay == nil)
    CheckInEngine.reconcile(&journal, now: now)
    #expect(journal.expandedRulesStartDay == upgradeDay)
    #expect(journal.isGoalMet(on: start))
    #expect(journal.isGoalMet(on: upgradeDay))
    #expect(journal.missions(on: start).count == 14)
    #expect(journal.missions(on: upgradeDay).count == 17)
    #expect(RewardEngine.settle(&journal, now: now).map(\.stage) == [.week])
    for mission in [Mission.hygiene, .dressing] {
        _ = try CheckInEngine.tap(mission, day: upgradeDay, now: now, isRestDay: false, journal: &journal)
    }
    let rewards = try settleFixtureRewards(day: upgradeDay, password: "885802", now: now, journal: &journal)
    #expect(rewards.isEmpty)
    let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.week(containing: now), now: now)
    #expect(stats.expectedCount == 6 * 14 + 17)
    #expect(stats.achievedDays == 7)
    #expect(stats.count == 7 * 11 + 2)
    var restored = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    CheckInEngine.reconcile(&restored, now: instant("2026-09-21"))
    #expect(restored.expandedRulesStartDay == upgradeDay)
    #expect(restored.rewards.count == 1)
}

@Test @MainActor
func legacyRuleAdoptionPersistsAcrossLaunches() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("legacy.store")
    do {
        let persistence = try JournalPersistence(now: instant("2026-09-18"), url: url)
        var legacy = persistence.journal
        legacy.expandedRulesStartDay = nil
        legacy.listeningStartDay = nil
        addGoalDay("2026-09-18", to: &legacy)
        legacy.records.removeAll { $0.mission == .hygiene || $0.mission == .dressing }
        try persistence.commit(legacy)
    }
    do {
        let upgraded = try JournalPersistence(now: instant("2026-09-19"), url: url)
        #expect(upgraded.journal.expandedRulesStartDay == "2026-09-19")
        #expect(upgraded.journal.isGoalMet(on: "2026-09-18"))
    }
    let reopened = try JournalPersistence(now: instant("2026-09-20"), url: url)
    #expect(reopened.journal.expandedRulesStartDay == "2026-09-19")
}

@Test(arguments: ["2027-02-01", "2028-02-01", "2026-04-01", "2026-05-01"])
func allMonthLengthsAwardOnlyOneHundred(start: String) throws {
    let first = instant(start)
    var journal = Journal(now: first)
    let days = BeijingCalendar.days(in: BeijingCalendar.month(containing: first))
    for (index, day) in days.enumerated() {
        addGoalDay(day, to: &journal)
        _ = RewardEngine.settle(&journal, now: instant(day, 21))
        let monthly = journal.rewards.filter { $0.stage != .week }
        #expect(monthly.reduce(0) { $0 + $1.points } == (index == days.count - 1 ? 100 : index >= 24 ? 50 : 0))
    }
    #expect(journal.rewards.filter { $0.stage == .month25 }.count == 1)
    #expect(journal.rewards.filter { $0.stage == .monthFull }.count == 1)
    let restored = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    journal = restored
    #expect(RewardEngine.settle(&journal, now: instant(days.last!, 22)).isEmpty)
}

@Test func missingDayStillAllowsTwentyFiveButNotFullMonth() {
    let first = instant("2026-09-01")
    var journal = Journal(now: first)
    let days = BeijingCalendar.days(in: BeijingCalendar.month(containing: first))
    for day in days where day != "2026-09-10" {
        addGoalDay(day, to: &journal)
        _ = RewardEngine.settle(&journal, now: instant(day, 21))
    }
    let monthly = journal.rewards.filter { $0.stage != .week }
    #expect(monthly.count == 1)
    #expect(monthly.first?.day == "2026-09-26")
    #expect(monthly.reduce(0) { $0 + $1.points } == 50)
}

@Test func weekCrossingMonthAwardsOnSundayOnly() {
    let monday = instant("2026-08-31")
    var journal = Journal(now: monday)
    let days = BeijingCalendar.days(in: BeijingCalendar.week(containing: monday))
    #expect(days.first == "2026-08-31")
    #expect(days.last == "2026-09-06")
    for (index, day) in days.enumerated() {
        addGoalDay(day, to: &journal)
        let new = RewardEngine.settle(&journal, now: instant(day, 21))
        #expect(new.count == (index == 6 ? 1 : 0))
    }
    #expect(journal.rewards.first?.points == 10)
    #expect(journal.rewards.first?.day == "2026-09-06")
    let september = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: instant("2026-09-06")), now: instant("2026-09-06", 22))
    #expect(september.rewardPoints == 10)
    let august = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: monday), now: instant("2026-09-06", 22))
    #expect(august.rewardPoints == 0)
}

@Test func launchMidWeekDoesNotProrateRewards() {
    let first = instant("2026-09-02")
    var journal = Journal(now: first)
    for day in ["2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06"] {
        addGoalDay(day, to: &journal)
        #expect(RewardEngine.settle(&journal, now: instant(day, 21)).isEmpty)
    }
}

@Test func launchMidMonthCanEarnTwentyFiveButNotFullMonth() {
    let first = instant("2026-05-07")
    var journal = Journal(now: first)
    for day in BeijingCalendar.days(in: BeijingCalendar.month(containing: first)) where day >= journal.firstDay {
        addGoalDay(day, to: &journal)
        _ = RewardEngine.settle(&journal, now: instant(day, 21))
    }
    #expect(journal.rewards.contains { $0.stage == .month25 })
    #expect(!journal.rewards.contains { $0.stage == .monthFull })
}

@Test func weekAndMonthCanAwardTogetherForValidRecords() throws {
    let first = instant("2026-05-01")
    var journal = Journal(now: first)
    for day in BeijingCalendar.days(in: BeijingCalendar.month(containing: first)) {
        addGoalDay(day, to: &journal, confirmed: day != "2026-05-31")
        if day != "2026-05-31" { _ = RewardEngine.settle(&journal, now: instant(day, 21)) }
    }
    let new = try settleFixtureRewards(day: "2026-05-31", password: "885802", now: instant("2026-05-31", 21), journal: &journal)
    #expect(Set(new.map(\.stage)) == Set([.week, .monthFull]))
    #expect(new.reduce(0) { $0 + $1.points } == 60)
}

@Test func statisticsIncludeAllPassedRecordsAndRespectFirstLaunch() throws {
    let first = instant("2026-09-18")
    var journal = Journal(now: first)
    addGoalDay("2026-09-18", to: &journal)
    addGoalDay("2026-09-19", to: &journal, confirmed: false)
    let now = instant("2026-09-20")
    let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: now), now: now)
    #expect(stats.count == 22)
    #expect(stats.expectedCount == 51)
    #expect(stats.effectivePoints == 26)
    #expect(stats.achievedDays == 2)
    #expect(stats.topMissions == [.wake, .breakfast, .lunch])
    #expect(abs(stats.rate - 22.0 / 51.0) < 0.0001)
    let empty = PeriodStatistics.calculate(journal: Journal(now: now), interval: BeijingCalendar.month(containing: now), now: now)
    #expect(empty.rate == 0)
    #expect(empty.topMissions.isEmpty)
}

@Test func holidayExceptionsAndWeekends() throws {
    let calendar = try #require(HolidayCalendar.bundled(year: 2026))
    #expect(calendar.isRestDay(instant("2026-09-25")))
    #expect(!calendar.isRestDay(instant("2026-09-20")))
    #expect(!calendar.isRestDay(instant("2026-01-04")))
    #expect(!calendar.isRestDay(instant("2026-02-14")))
    #expect(!calendar.isRestDay(instant("2026-02-28")))
    #expect(!calendar.isRestDay(instant("2026-05-09")))
    #expect(!calendar.isRestDay(instant("2026-10-10")))
    #expect(calendar.isRestDay(instant("2026-09-19")))
    #expect(!calendar.isRestDay(instant("2026-09-18")))
    #expect(HolidayCalendar.bundled(year: 2099) == nil)
}

@Test func holidayValidationRejectsMalformedAndUnpublishedCalendars() throws {
    var calendar = try #require(HolidayCalendar.bundled(year: 2026))
    #expect(throws: (any Error).self) { try HolidayCalendar.validated(JSONEncoder().encode(calendar), year: 2027) }
    calendar.days.append(calendar.days[0])
    #expect(throws: (any Error).self) { try HolidayCalendar.validated(JSONEncoder().encode(calendar), year: 2026) }
    calendar.days = []
    #expect(throws: (any Error).self) { try HolidayCalendar.validated(JSONEncoder().encode(calendar), year: 2026) }
}

@Test func ruleSnapshotSurvivesHolidayChanges() throws {
    let day = "2026-09-18"
    var journal = Journal(now: instant(day, 8))
    _ = try CheckInEngine.tap(.wake, day: day, now: instant(day, 8), isRestDay: true, journal: &journal)
    CheckInEngine.reconcile(&journal, now: instant(day, 9))
    #expect(journal.record(.wake, day: day)?.isRestDay == true)
    #expect(journal.record(.wake, day: day)?.isPassed == true)
    #expect(journal.record(.wake, day: day)?.ruleSnapshot == "休息日 08:30 前")
}

@Test @MainActor
func swiftDataDiskRoundTripPersistsReviewRewardAndTimer() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let day = "2026-09-18"
    let now = instant(day, 12)
    var expected: Journal
    do {
        let persistence = try JournalPersistence(now: now, url: url)
        var next = persistence.journal
        _ = try CheckInEngine.tap(.reading, day: day, now: now, isRestDay: false, journal: &next)
        _ = try CheckInEngine.tap(.honesty, day: day, now: now, isRestDay: false, journal: &next)
        _ = try settleFixtureRewards(day: day, password: "885802", now: now, journal: &next)
        next.rewards.append(Reward(period: day, stage: .week, awardedAt: now))
        try persistence.commit(next)
        expected = next
    }
    let reopened = try JournalPersistence(now: now.addingTimeInterval(1000), url: url)
    #expect(reopened.journal == expected)
    #expect(reopened.journal.record(.reading, day: day)?.latest?.duration(at: now.addingTimeInterval(1000)) == 1000)
    #expect(reopened.journal.effectiveScore(on: day) == 1)
    #expect(reopened.journal.rewards.count == 1)
    #expect(reopened.journal.reviews.count == 0)
}

@Test func monthlyExplorationKeepsEarningsAndIgnoresSpendingAcrossMonthAndYear() throws {
    for (previous, current, next) in [("2026-08-31", "2026-09-01", "2026-10-01"), ("2026-12-31", "2027-01-01", "2027-02-01")] {
        var journal = Journal(now: instant(previous))
        addGoalDay(previous, to: &journal)
        addGoalDay(current, to: &journal)
        addGoalDay(String(current.prefix(7)) + "-02", to: &journal, confirmed: false)
        journal.rewards.append(Reward(period: String(previous.prefix(7)), stage: .month25, awardedAt: instant(previous)))
        // A crossing-week reward belongs to the month in which it was awarded.
        journal.rewards.append(Reward(period: previous, stage: .week, awardedAt: instant(current)))
        #expect(journal.exploration(in: instant(previous)).points == 63)
        #expect(journal.exploration(in: instant(previous)).unlockedPlanets == 1)
        let exploration = journal.exploration(in: instant(current))
        #expect(exploration.month == String(current.prefix(7)))
        #expect(exploration.points == 36)
        #expect(exploration.unlockedPlanets == 0)
        let earned = journal.totalPoints
        _ = try SpendingEngine.addManual(id: UUID(), name: "奖励贴纸", points: 50, now: instant(current), journal: &journal)
        #expect(journal.exploration(in: instant(current)) == exploration)
        CheckInEngine.reconcile(&journal, now: instant(next, 0))
        #expect(journal.exploration(in: instant(next, 0)).points == 0)
        #expect(journal.exploration(in: instant(next, 0)).unlockedPlanets == 0)
        #expect(journal.exploration(in: instant(current)) == exploration)
        #expect(journal.totalPoints == earned)
        #expect(journal.spendingLedger.settledPoints == 50)
    }
}

@Test func monthlyPlanetsUnlockEveryFiftyPointsAndStopAtEight() {
    #expect(AppRules.pointsPerPlanet == 50)
    for (points, expected) in [(0, 0), (49, 0), (50, 1), (99, 1), (100, 2), (399, 7), (400, 8), (450, 8)] {
        #expect(MonthlyExploration(month: "2026-09", points: points).unlockedPlanets == expected)
    }
}

@Test @MainActor
func listeningAdoptionPreservesSixteenTaskHistoryAndPersists() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("sixteen-tasks.store")
    let start = "2026-09-18"
    let upgrade = "2026-09-20"
    do {
        let persistence = try JournalPersistence(now: instant(start), url: url)
        var legacy = persistence.journal
        addGoalDay(start, to: &legacy)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "listeningStartDay")
        legacy = try JSONDecoder().decode(Journal.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.listeningStartDay == nil)
        try persistence.commit(legacy)
    }
    do {
        let persistence = try JournalPersistence(now: instant(upgrade), url: url)
        let journal = persistence.journal
        #expect(journal.listeningStartDay == upgrade)
        #expect(journal.missions(on: start).count == 16)
        #expect(journal.missions(on: upgrade).count == 17)
        #expect(journal.effectiveScore(on: start) == 13)
        #expect(journal.isGoalMet(on: start))
        let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: instant(upgrade)), now: instant(upgrade))
        #expect(stats.expectedCount == 16 + 16 + 17)
    }
    let reopened = try JournalPersistence(now: instant("2026-09-21"), url: url)
    #expect(reopened.journal.listeningStartDay == upgrade)
    #expect(reopened.journal.missions(on: start).count == 16)
}
