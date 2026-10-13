import Foundation
import Testing
@testable import DodoCore

func instant(_ day: String, _ hour: Int = 7, _ minute: Int = 0, _ second: Int = 0) -> Date {
    BeijingCalendar.time(on: day, hour: hour, minute: minute).addingTimeInterval(Double(second))
}

// Fixtures insert records directly; production taps settle rewards automatically.
func settleFixtureRewards(day: String, password: String, now: Date, journal: inout Journal) throws -> [Reward] {
    guard password == AppRules.parentPassword else { throw CheckInError.wrongPassword }
    try CheckInEngine.validateDay(day, now: now, journal: journal)
    return RewardEngine.settle(&journal, now: now)
}

func addGoalDay(_ day: String, to journal: inout Journal, confirmed: Bool = true, includingNewTasks: Bool = false) {
    let time = instant(day, 20)
    // Exactly 13 points; optionally include the two newer tasks for spending fixtures.
    for mission in Mission.allCases where ![Mission.kindness, .calmness, .promptness, .listening].contains(mission) {
        if !includingNewTasks && [Mission.hygiene, .dressing].contains(mission) { continue }
        journal.records.append(MissionRecord(
            day: day, mission: mission, points: mission.points,
            ruleSnapshot: mission.ruleDescription, isRestDay: false,
            attempts: [Attempt(startedAt: time, endedAt: time, closedAt: time, outcome: .passed)],
            confirmedAt: confirmed ? time : nil
        ))
    }
}

@Test func catalogAndFixedPassword() {
    #expect(Mission.allCases.count == 17)
    #expect(Mission.allCases.filter(\.isTimed).count == 5)
    #expect(Mission.allCases.reduce(0) { $0 + $1.points } == 23)
    #expect(Mission.honesty.points == 1)
    #expect(AppRules.dailyGoal == 13)
    #expect(AppRules.dailyMaximum == 23)
    #expect(AppRules.parentPassword == "885802")
}

@Test(arguments: [Mission.hygiene, .dressing, .listening])
func newSingleTasksScoreImmediatelyAndCanBeCancelled(mission: Mission) throws {
    let day = "2026-09-19"
    let now = instant(day, 23, 59)
    var journal = Journal(now: now)
    #expect(!mission.isTimed)
    #expect(mission.points == (mission == .listening ? 2 : 1))
    #expect(try CheckInEngine.tap(mission, day: day, now: now, isRestDay: true, journal: &journal) == .completed)
    #expect(journal.record(mission, day: day)?.latest?.endedAt == now)
    #expect(journal.selfScore(on: day) == mission.points)
    #expect(journal.effectiveScore(on: day) == mission.points)
    #expect(throws: CheckInError.alreadyFinished) {
        try CheckInEngine.tap(mission, day: day, now: now, isRestDay: true, journal: &journal)
    }
    _ = try CheckInEngine.review(day: day, decisions: [mission: .makeup], password: "885802", now: now, journal: &journal)
    #expect(journal.effectiveScore(on: day) == mission.points)
    _ = try CheckInEngine.review(day: day, decisions: [mission: .cancel], password: "885802", now: now, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 0)
    #expect(try CheckInEngine.tap(mission, day: day, now: now, isRestDay: true, journal: &journal) == .completed)
    #expect(journal.record(mission, day: day)?.attempts.count == 2)
    #expect(journal.effectiveScore(on: day) == mission.points)
}

@Test func goalRequiresThirteenValidPoints() throws {
    let day = "2026-09-19"
    let now = instant(day, 20)
    var journal = Journal(now: now)
    addGoalDay(day, to: &journal)
    journal.records.removeAll { $0.mission == .honesty }
    journal.rewards.append(Reward(period: "2026-09", stage: .month25, awardedAt: now))
    #expect(journal.effectiveScore(on: day) == 12)
    #expect(!journal.isGoalMet(on: day))
    _ = try CheckInEngine.tap(.honesty, day: day, now: now, isRestDay: true, journal: &journal)
    #expect(journal.selfScore(on: day) == 13)
    #expect(journal.isGoalMet(on: day))
    _ = try CheckInEngine.review(day: day, decisions: [.honesty: .makeup], password: "885802", now: now, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 13)
    #expect(journal.isGoalMet(on: day))
    _ = try CheckInEngine.tap(.hygiene, day: day, now: now, isRestDay: true, journal: &journal)
    _ = try CheckInEngine.review(day: day, decisions: [.hygiene: .makeup], password: "885802", now: now, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 14)
    #expect(journal.isGoalMet(on: day))
}

@Test(arguments: [false, true])
func wakeUsesStrictBoundary(rest: Bool) throws {
    let day = "2026-09-18"
    let boundary = instant(day, rest ? 8 : 7, 30)
    for offset in [-1.0, 0, 1] {
        var journal = Journal(now: boundary)
        let result = try CheckInEngine.tap(.wake, day: day, now: boundary.addingTimeInterval(offset), isRestDay: rest, journal: &journal)
        #expect(result == (offset < 0 ? .completed : .failed))
        #expect(journal.selfScore(on: day) == (offset < 0 ? 1 : 0))
    }
}

@Test(arguments: [Mission.washing, .sleeping])
func eveningAllowsExactBoundary(mission: Mission) throws {
    let day = "2026-09-18"
    let boundary = instant(day, 21, mission == .washing ? 0 : 30)
    for offset in [-1.0, 0, 1] {
        var journal = Journal(now: boundary)
        let result = try CheckInEngine.tap(mission, day: day, now: boundary.addingTimeInterval(offset), isRestDay: false, journal: &journal)
        #expect(result == (offset <= 0 ? .completed : .failed))
    }
}

@Test(arguments: [Mission.breakfast, .lunch, .dinner, .homework])
func timedLimitsAndSingleCount(mission: Mission) throws {
    let day = "2026-09-18"
    let start = instant(day, 12)
    var journal = Journal(now: start)
    #expect(try CheckInEngine.tap(mission, day: day, now: start, isRestDay: false, journal: &journal) == .started)
    #expect(journal.selfScore(on: day) == 0)
    let end = start.addingTimeInterval(mission.maximumDuration!)
    #expect(try CheckInEngine.tap(mission, day: day, now: end, isRestDay: false, journal: &journal) == .completed)
    #expect(journal.effectiveScore(on: day) == mission.points)
    _ = try settleFixtureRewards(day: day, password: "885802", now: end, journal: &journal)
    #expect(journal.effectiveScore(on: day) == mission.points)
    let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: start), now: end)
    #expect(stats.count == 1)
    #expect(throws: CheckInError.alreadyFinished) {
        try CheckInEngine.tap(mission, day: day, now: end, isRestDay: false, journal: &journal)
    }
}

@Test(arguments: [Mission.breakfast, .lunch, .dinner, .homework])
func overtimeIsNotACompletion(mission: Mission) throws {
    let day = "2026-09-18"
    let start = instant(day, 12)
    var journal = Journal(now: start)
    _ = try CheckInEngine.tap(mission, day: day, now: start, isRestDay: false, journal: &journal)
    CheckInEngine.reconcile(&journal, now: start.addingTimeInterval(mission.maximumDuration! + 1))
    #expect(journal.record(mission, day: day)?.latest?.outcome == .failed)
    #expect(journal.selfScore(on: day) == 0)
    #expect(journal.record(mission, day: day)?.latest?.endedAt == nil)
}

@Test(arguments: [899.0, 900, 901])
func readingCanStopBeforeStrictFifteenMinuteThreshold(seconds: TimeInterval) throws {
    let day = "2026-09-18"
    let start = instant(day, 18)
    var journal = Journal(now: start)
    _ = try CheckInEngine.tap(.reading, day: day, now: start, isRestDay: false, journal: &journal)
    let result = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(seconds), isRestDay: false, journal: &journal)
    #expect(result == (seconds > 900 ? .completed : .paused))
    #expect(journal.selfScore(on: day) == (seconds > 900 ? 2 : 0))
    #expect(journal.record(.reading, day: day)?.readingDuration(at: start.addingTimeInterval(5000)) == seconds)
}

@Test func homeworkRetryRequiresPasswordAndPreservesAttempt() throws {
    let day = "2026-09-18"
    let start = instant(day, 15)
    let restart = start.addingTimeInterval(3601)
    var journal = Journal(now: start)
    _ = try CheckInEngine.tap(.homework, day: day, now: start, isRestDay: false, journal: &journal)
    CheckInEngine.reconcile(&journal, now: restart)
    #expect(throws: CheckInError.wrongPassword) {
        try CheckInEngine.retryHomework(day: day, password: "000000", now: restart, journal: &journal)
    }
    try CheckInEngine.retryHomework(day: day, password: "885802", now: restart, journal: &journal)
    let end = restart.addingTimeInterval(1200)
    _ = try CheckInEngine.tap(.homework, day: day, now: end, isRestDay: false, journal: &journal)
    _ = try settleFixtureRewards(day: day, password: "885802", now: end, journal: &journal)
    #expect(journal.record(.homework, day: day)?.attempts.count == 2)
    #expect(journal.record(.homework, day: day)?.attempts.first?.outcome == .failed)
    #expect(journal.effectiveScore(on: day) == 2)
    #expect(throws: CheckInError.cannotRetry) {
        try CheckInEngine.retryHomework(day: day, password: "885802", now: end, journal: &journal)
    }
}

@Test func mealCannotRestart() throws {
    let day = "2026-09-18"
    let start = instant(day, 12)
    var journal = Journal(now: start)
    _ = try CheckInEngine.tap(.lunch, day: day, now: start, isRestDay: false, journal: &journal)
    let later = start.addingTimeInterval(1801)
    CheckInEngine.reconcile(&journal, now: later)
    #expect(throws: CheckInError.alreadyFinished) {
        try CheckInEngine.tap(.lunch, day: day, now: later, isRestDay: false, journal: &journal)
    }
    #expect(throws: CheckInError.cannotRetry) {
        try CheckInEngine.retryHomework(day: day, password: "885802", now: later, journal: &journal)
    }
}

@Test func promptnessUsesCompletedNotConfirmedPrerequisites() throws {
    let day = "2026-09-18"
    let time = instant(day, 18)
    var journal = Journal(now: time)
    #expect(throws: CheckInError.locked) {
        try CheckInEngine.tap(.promptness, day: day, now: time, isRestDay: false, journal: &journal)
    }
    for mission in Mission.prerequisites {
        _ = try CheckInEngine.tap(mission, day: day, now: time, isRestDay: false, journal: &journal)
        _ = try CheckInEngine.tap(mission, day: day, now: time.addingTimeInterval(600), isRestDay: false, journal: &journal)
    }
    #expect(journal.effectiveScore(on: day) == 5)
    #expect(try CheckInEngine.tap(.promptness, day: day, now: time.addingTimeInterval(601), isRestDay: false, journal: &journal) == .completed)
}

@Test func repeatedMakeupOfCompletedTaskDoesNotAddPoints() throws {
    let day = "2026-09-18"
    let now = instant(day)
    var journal = Journal(now: now)
    _ = try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: false, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 1)
    let original = journal
    #expect(throws: CheckInError.wrongPassword) {
        try CheckInEngine.review(day: day, decisions: [.toys: .makeup], password: "123456", now: now, journal: &journal)
    }
    for _ in 0..<2 {
        let result = try CheckInEngine.review(day: day, decisions: [.toys: .makeup], password: "885802", now: now, journal: &journal)
        #expect(result.confirmed.isEmpty)
    }
    #expect(journal == original)
}

@Test func midnightSealsRunningTasksAndKeepsEarnedPoints() throws {
    let day = "2026-09-18"
    let start = instant(day, 23, 50)
    var journal = Journal(now: start)
    _ = try CheckInEngine.tap(.reading, day: day, now: start, isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(.honesty, day: day, now: start, isRestDay: false, journal: &journal)
    let midnight = instant("2026-09-19", 0)
    CheckInEngine.reconcile(&journal, now: midnight)
    #expect(journal.record(.reading, day: day)?.latest?.outcome == .failed)
    #expect(journal.record(.reading, day: day)?.latest?.closedAt == midnight)
    #expect(throws: CheckInError.historical) {
        try settleFixtureRewards(day: day, password: "885802", now: midnight, journal: &journal)
    }
    #expect(throws: CheckInError.historical) {
        try CheckInEngine.tap(.reading, day: day, now: midnight, isRestDay: false, journal: &journal)
    }
    #expect(journal.effectiveScore(on: day) == 1)
}

@Test func backwardClockCannotReopenYesterday() throws {
    let day = "2026-09-18"
    var journal = Journal(now: instant(day))
    CheckInEngine.reconcile(&journal, now: instant("2026-09-19"))
    #expect(throws: CheckInError.clockChanged) {
        try CheckInEngine.tap(.honesty, day: day, now: instant(day), isRestDay: false, journal: &journal)
    }
}

@Test func passedRecordsDoNotNeedConfirmationAndBonusCannotReplaceCheckIns() {
    let day = "2026-09-18"
    var journal = Journal(now: instant(day))
    addGoalDay(day, to: &journal, confirmed: false)
    journal.rewards.append(Reward(period: "2026-09", stage: .month25, awardedAt: instant(day)))
    #expect(journal.selfScore(on: day) == 13)
    #expect(journal.effectiveScore(on: day) == 13)
    #expect(journal.isGoalMet(on: day))
    journal.records = []
    #expect(!journal.isGoalMet(on: day))
}

@Test func missionGroupsAndTimerDisplay() {
    #expect(Mission.allCases.filter { $0.group == "能量补给站" } == [.wake, .breakfast, .lunch, .dinner, .sleeping])
    #expect(Mission.allCases.filter { $0.group == "知识探索站" } == [.listening, .homework, .reading])
    #expect(Mission.allCases.filter { $0.group == "生活空间站" } == [.toys, .cleaning, .washing, .hygiene, .dressing])
    #expect(Mission.allCases.filter { $0.group == "勇气成长站" } == [.kindness, .calmness, .promptness, .honesty])
    #expect(Mission.breakfast.timerText(duration: 1511, isRunning: true) == "25:11")
    #expect(Mission.breakfast.timerText(duration: 1511, isRunning: false) == "25:11/30")
    #expect(Mission.homework.timerText(duration: 3600, isRunning: false) == "60:00/60")
    #expect(Mission.reading.timerText(duration: 900, isRunning: false) == "15:00/>15")
}
