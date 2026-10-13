import Foundation
import Testing
@testable import DodoCore

@Test func selectedCancellationLeavesOtherEarnedPointsAndAllowsRedoneCancellation() throws {
    let day = "2026-09-19"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    for mission in [Mission.toys, .cleaning, .honesty] {
        _ = try CheckInEngine.tap(mission, day: day, now: now, isRestDay: true, journal: &journal)
    }
    let result = try CheckInEngine.review(day: day, decisions: [.toys: .makeup, .cleaning: .cancel], password: "885802", now: now, journal: &journal)
    #expect(result.confirmed.isEmpty)
    #expect(result.cancelled == [.cleaning])
    #expect(journal.effectiveScore(on: day) == 2)
    #expect(journal.selfScore(on: day) == 2)
    #expect(journal.record(.honesty, day: day)?.confirmedAt == nil)
    #expect(journal.record(.cleaning, day: day)?.latest?.cancelledAt == now)
    #expect(try CheckInEngine.tap(.cleaning, day: day, now: now.addingTimeInterval(60), isRestDay: true, journal: &journal) == .completed)
    #expect(journal.record(.cleaning, day: day)?.attempts.count == 2)
    #expect(journal.record(.cleaning, day: day)?.attempts.first?.outcomeBeforeCancellation == .passed)
    #expect(journal.record(.cleaning, day: day)?.confirmedAt == nil)
    #expect(journal.effectiveScore(on: day) == 3)
}

@Test func cancellingMultipleConfirmedTasksRemovesTheirPointsAndCounts() throws {
    let day = "2026-09-19"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    for mission in [Mission.toys, .cleaning] {
        _ = try CheckInEngine.tap(mission, day: day, now: now, isRestDay: true, journal: &journal)
    }
    _ = try settleFixtureRewards(day: day, password: "885802", now: now, journal: &journal)
    let result = try CheckInEngine.review(day: day, decisions: [.toys: .cancel, .cleaning: .cancel], password: "885802", now: now, journal: &journal)
    #expect(result.cancelled.count == 2)
    #expect(journal.selfScore(on: day) == 0)
    #expect(journal.effectiveScore(on: day) == 0)
    #expect(PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: now), now: now).count == 0)
    _ = try CheckInEngine.tap(.toys, day: day, now: now.addingTimeInterval(1), isRestDay: true, journal: &journal)
    _ = try settleFixtureRewards(day: day, password: "885802", now: now.addingTimeInterval(1), journal: &journal)
    #expect(journal.effectiveScore(on: day) == 1)
}

@Test func reviewValidationIsAtomicAndRequiresExplicitSelection() throws {
    let day = "2026-09-19"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    _ = try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: true, journal: &journal)
    let original = journal
    #expect(throws: CheckInError.noSelection) {
        try CheckInEngine.review(day: day, decisions: [:], password: "885802", now: now, journal: &journal)
    }
    #expect(throws: CheckInError.wrongPassword) {
        try CheckInEngine.review(day: day, decisions: [.toys: .cancel], password: "000000", now: now, journal: &journal)
    }
    #expect(throws: CheckInError.staleSelection) {
        try CheckInEngine.review(day: day, decisions: [.toys: .cancel, Mission(rawValue: "missing-task"): .makeup], password: "885802", now: now, journal: &journal)
    }
    #expect(throws: CheckInError.historical) {
        try CheckInEngine.review(day: day, decisions: [.toys: .cancel], password: "885802", now: instant("2026-09-20"), journal: &journal)
    }
    #expect(journal == original)
}

@Test func parentCancellationReopensFailedMealsAndStopsRunningTimers() throws {
    let day = "2026-09-19"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    _ = try CheckInEngine.tap(.lunch, day: day, now: now, isRestDay: true, journal: &journal)
    let later = now.addingTimeInterval(1801)
    CheckInEngine.reconcile(&journal, now: later)
    _ = try CheckInEngine.review(day: day, decisions: [.lunch: .cancel], password: "885802", now: later, journal: &journal)
    #expect(try CheckInEngine.tap(.lunch, day: day, now: later, isRestDay: true, journal: &journal) == .started)
    #expect(journal.record(.lunch, day: day)?.latest?.startedAt == later)
    _ = try CheckInEngine.review(day: day, decisions: [.lunch: .cancel], password: "885802", now: later.addingTimeInterval(10), journal: &journal)
    #expect(journal.record(.lunch, day: day)?.latest?.duration(at: later.addingTimeInterval(100)) == 10)
    #expect(journal.record(.lunch, day: day)?.attempts.count == 2)
}

@Test func dependencyCancellationAlsoCancelsPromptness() throws {
    let day = "2026-09-19"
    let now = instant(day, 20)
    var journal = Journal(now: now)
    addGoalDay(day, to: &journal)
    _ = try CheckInEngine.tap(.promptness, day: day, now: now, isRestDay: true, journal: &journal)
    let result = try CheckInEngine.review(day: day, decisions: [.lunch: .cancel, .promptness: .makeup], password: "885802", now: now, journal: &journal)
    #expect(Set(result.cancelled) == [.lunch, .promptness])
    #expect(result.confirmed.isEmpty)
    #expect(!journal.isPromptnessUnlocked(on: day))
    #expect(throws: CheckInError.locked) {
        try CheckInEngine.tap(.promptness, day: day, now: now, isRestDay: true, journal: &journal)
    }
}

@Test func cancellationRevokesOnlyUnqualifiedRewardsAndReconfirmationRestoresOnce() throws {
    let day = "2026-05-31" // Sunday and month end.
    let now = instant(day, 21)
    var journal = Journal(now: instant("2026-05-01"))
    for date in BeijingCalendar.days(in: BeijingCalendar.month(containing: now)) {
        addGoalDay(date, to: &journal)
        _ = RewardEngine.settle(&journal, now: instant(date, 20))
    }
    let total = journal.totalPoints
    let result = try CheckInEngine.review(day: day, decisions: [.honesty: .cancel], password: "885802", now: now, journal: &journal)
    #expect(Set(result.revokedRewards.map(\.stage)) == [.week, .monthFull])
    #expect(journal.totalPoints == total - 61)
    #expect(journal.rewards.contains { $0.stage == .month25 })
    _ = try CheckInEngine.tap(.honesty, day: day, now: now, isRestDay: true, journal: &journal)
    let restored = try CheckInEngine.review(day: day, decisions: [.honesty: .makeup], password: "885802", now: now, journal: &journal)
    #expect(restored.rewards.isEmpty) // The child tap already restored the rewards.
    #expect(journal.totalPoints == total)
    #expect(RewardEngine.settle(&journal, now: now).isEmpty)
}

@Test func cancellationOnTwentyFifthDayWithdrawsMonthlyThresholdReward() throws {
    let day = "2026-09-25"
    let now = instant(day, 21)
    var journal = Journal(now: instant("2026-09-01"))
    for date in BeijingCalendar.days(in: BeijingCalendar.month(containing: now)) where date <= day {
        addGoalDay(date, to: &journal)
        _ = RewardEngine.settle(&journal, now: instant(date, 20))
    }
    let result = try CheckInEngine.review(day: day, decisions: [.honesty: .cancel], password: "885802", now: now, journal: &journal)
    #expect(result.revokedRewards.map(\.stage) == [.month25])
}

@Test func cancelledRecordsAndLegacyRecordsDecode() throws {
    let day = "2026-09-19"
    let now = instant(day)
    var journal = Journal(now: now)
    _ = try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: true, journal: &journal)
    let legacyData = try JSONEncoder().encode(journal)
    #expect(try JSONDecoder().decode(Journal.self, from: legacyData) == journal)
    _ = try CheckInEngine.review(day: day, decisions: [.toys: .cancel], password: "885802", now: now, journal: &journal)
    #expect(try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal)) == journal)
}
