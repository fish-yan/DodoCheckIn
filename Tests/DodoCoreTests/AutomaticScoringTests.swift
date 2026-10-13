import Foundation
import Testing
@testable import DodoCore

@Test func childCompletionAwardsPointsAndRewardsWithoutParentAction() throws {
    let now = instant("2026-10-08", 12)
    let day = BeijingCalendar.key(now)
    var journal = Journal(now: now)
    try ConfigurationEngine.saveRewards(dailyGoal: 1, week: .init(days: 1, points: 10), month: .init(days: 1, points: 50, planetStep: 50), password: "885802", now: now, journal: &journal)
    _ = try CheckInEngine.tap(.toys, day: day, now: now, isRestDay: false, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 1)
    #expect(journal.isGoalMet(on: day))
    #expect(journal.rewards.map(\.points) == [10, 50])
    #expect(journal.reviews.isEmpty)
    #expect(journal.record(.toys, day: day)?.confirmedAt == nil)
    #expect(RewardEngine.settle(&journal, now: now).isEmpty)
    _ = try SpendingEngine.addManual(id: UUID(), name: "玩具", points: 100, now: now, journal: &journal)
    _ = try CheckInEngine.review(day: day, decisions: [.toys: .cancel], password: "885802", now: now, journal: &journal)
    #expect(journal.rewards.isEmpty)
    #expect(SpendingEngine.remainingPoints(in: journal, at: now) == -100)
}

@Test(arguments: ["missing", "failed", "running", "paused", "cancelled"])
func parentMakeupCoversEveryIncompleteStateAndIsIdempotent(state: String) throws {
    let day = "2026-10-08"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    ConfigurationEngine.adopt(&journal, now: now)
    let mission: Mission = state == "paused" ? .reading : .breakfast
    if state != "missing" {
        _ = try CheckInEngine.tap(mission, day: day, now: now, isRestDay: false, journal: &journal)
        if state == "failed" { CheckInEngine.reconcile(&journal, now: now.addingTimeInterval(1801)) }
        if state == "paused" { _ = try CheckInEngine.tap(mission, day: day, now: now.addingTimeInterval(60), isRestDay: false, journal: &journal) }
        if state == "cancelled" { _ = try CheckInEngine.review(day: day, decisions: [mission: .cancel], password: "885802", now: now, journal: &journal) }
    }
    let previous = journal.record(mission, day: day)?.attempts ?? []
    let end = now.addingTimeInterval(2400)
    let result = try CheckInEngine.review(day: day, decisions: [mission: .makeup], password: "885802", now: end, journal: &journal)
    #expect(result.confirmed == [mission])
    let record = try #require(journal.record(mission, day: day))
    #expect(record.effectivePoints == mission.points)
    #expect(record.attempts.count == previous.count + 1)
    #expect(record.latest?.isParentMakeup == true)
    #expect(record.latest?.startedAt == end)
    #expect(record.latest?.duration(at: end) == 0)
    if state == "failed" { #expect(record.attempts.first?.outcome == .failed) }
    if state == "cancelled" { #expect(record.attempts.first?.outcome == .cancelled) }
    let after = journal
    _ = try CheckInEngine.review(day: day, decisions: [mission: .makeup], password: "885802", now: end, journal: &journal)
    #expect(journal == after)
    #expect(journal.reviews.last?.kind == "makeup")
}

@Test func parentCanMakeUpLockedTaskButChildCannotBypassDependencies() throws {
    let day = "2026-10-08"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    #expect(throws: CheckInError.locked) {
        try CheckInEngine.tap(.promptness, day: day, now: now, isRestDay: false, journal: &journal)
    }
    #expect(throws: CheckInError.wrongPassword) {
        try CheckInEngine.review(day: day, decisions: [.promptness: .makeup], password: "000000", now: now, journal: &journal)
    }
    #expect(journal.records.isEmpty)
    _ = try CheckInEngine.review(day: day, decisions: [.promptness: .makeup], password: "885802", now: now, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 2)
    let before = journal
    #expect(throws: CheckInError.historical) {
        try CheckInEngine.review(day: day, decisions: [.toys: .makeup], password: "885802", now: instant("2026-10-09"), journal: &journal)
    }
    #expect(journal == before)
}

@Test func manualReadingCreditIsNotAddedAgainByLaterTimerSegments() throws {
    let day = "2026-10-08"
    let now = instant(day, 12)
    var journal = Journal(now: now)
    ConfigurationEngine.adopt(&journal, now: now)
    _ = try CheckInEngine.tap(.reading, day: day, now: now, isRestDay: false, journal: &journal)
    _ = try CheckInEngine.review(day: day, decisions: [.reading: .makeup], password: "885802", now: now.addingTimeInterval(300), journal: &journal)
    #expect(journal.effectiveScore(on: day) == 2)
    #expect(journal.record(.reading, day: day)?.readingDuration(at: now.addingTimeInterval(600)) == 300)
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(600), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(1200), isRestDay: false, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 2) // Total real time 15 min; makeup already covered it.
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(1300), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(2200), isRestDay: false, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 4)
    #expect(PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: now), now: now.addingTimeInterval(2200)).count == 1)
    _ = try CheckInEngine.review(day: day, decisions: [.reading: .cancel], password: "885802", now: now.addingTimeInterval(2300), journal: &journal)
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(2400), isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(2500), isRestDay: false, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 0)
    #expect(journal.record(.reading, day: day)?.parentMakeupPoints == nil)
}

@Test @MainActor
func legacyPendingAndPartialRecordsMigrateWithoutRewritingAttemptsOrSpending() throws {
    let day = "2026-10-08"
    let now = instant(day, 12)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("legacy.store")
    var legacy = Journal(now: instant("2026-10-07"))
    legacy.schemaVersion = 2
    addGoalDay("2026-10-07", to: &legacy, confirmed: false)
    ConfigurationEngine.adopt(&legacy, now: now)
    _ = try CheckInEngine.tap(.reading, day: day, now: now, isRestDay: false, journal: &legacy)
    _ = try CheckInEngine.tap(.reading, day: day, now: now.addingTimeInterval(1800), isRestDay: false, journal: &legacy)
    let index = legacy.records.count - 1
    legacy.records[index].confirmedPoints = 2 // Old pending increment of 2 points.
    legacy.records[index].confirmedAt = now
    _ = try SpendingEngine.addManual(id: UUID(), name: "历史消费", points: 30, now: now.addingTimeInterval(1800), journal: &legacy)
    let originalRecords = legacy.records
    let originalExpenses = legacy.spendingLedger.records
    do {
        let persistence = try JournalPersistence(now: now, url: url)
        try persistence.commit(legacy)
    }
    do {
        let persistence = try JournalPersistence(now: now, url: url)
        var migrated = persistence.journal
        CheckInEngine.adoptAutomaticScoring(&migrated, now: now.addingTimeInterval(1800))
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.effectiveScore(on: "2026-10-07") == 13)
        #expect(migrated.effectiveScore(on: day) == 4)
        #expect(migrated.records == originalRecords)
        #expect(migrated.spendingLedger.records == originalExpenses)
        #expect(SpendingEngine.remainingPoints(in: migrated, at: now.addingTimeInterval(1800)) == -13)
        try persistence.commit(migrated)
    }
    let reopened = try JournalPersistence(now: now.addingTimeInterval(1900), url: url)
    var stable = reopened.journal
    CheckInEngine.adoptAutomaticScoring(&stable, now: now.addingTimeInterval(2000))
    #expect(stable == reopened.journal)
}

@Test func legacyActiveCartoonBudgetIsIgnoredAndStartTimePreserved() throws {
    let now = instant("2026-10-08", 12)
    var journal = Journal(now: now)
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
    var spending = try #require(object["spending"] as? [String: Any])
    var session = try #require(spending["activeCartoon"] as? [String: Any])
    session["budget"] = 1
    spending["activeCartoon"] = session
    object["spending"] = spending
    let restored = try JSONDecoder().decode(Journal.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.spendingLedger.activeCartoon?.startedAt == now)
    #expect(restored.spendingLedger.activeCartoon?.points(at: now.addingTimeInterval(600)) == 5)
    #expect(SpendingEngine.remainingPoints(in: restored, at: now.addingTimeInterval(600)) == -5)
}
