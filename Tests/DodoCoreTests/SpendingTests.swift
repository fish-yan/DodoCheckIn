import Foundation
import Testing
@testable import DodoCore

private func fundedJournal(on day: String = "2026-09-19") -> Journal {
    var journal = Journal(now: instant(day, 20))
    addGoalDay(day, to: &journal, includingNewTasks: true)
    return journal
}

@Test(arguments: [0.0, 119, 120, 121, 239, 240, 300])
func cartoonChargesOnlyCompleteTwoMinuteUnits(seconds: TimeInterval) throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    let earnings = journal.totalPoints
    let dailyScore = journal.effectiveScore(on: journal.firstDay)
    let before = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: now), now: now)
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    let session = try #require(journal.spendingLedger.activeCartoon)
    let end = now.addingTimeInterval(seconds)
    #expect(journal.spendingLedger.spentPoints(at: end) == Int(seconds / 120))
    let expense = try SpendingEngine.stopCartoon(id: session.id, now: end, journal: &journal)
    #expect(expense.points == Int(seconds / 120))
    #expect(expense.duration == seconds)
    #expect(expense.startedAt == now)
    #expect(expense.endedAt == end)
    #expect(journal.spendingLedger.activeCartoon == nil)
    #expect(journal.totalPoints == earnings)
    #expect(journal.effectiveScore(on: journal.firstDay) == dailyScore)
    #expect(journal.isGoalMet(on: journal.firstDay))
    #expect(PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: end), now: end) == before)
}

@Test func dailyRepeatedSessionsAreSeparateAndDoNotCombineRemainders() throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    for offset in [0.0, 200, 400] {
        let start = now.addingTimeInterval(offset)
        try SpendingEngine.startCartoon(now: start, journal: &journal)
        let session = try #require(journal.spendingLedger.activeCartoon)
        _ = try SpendingEngine.stopCartoon(id: session.id, now: start.addingTimeInterval(119), journal: &journal)
    }
    #expect(journal.spendingLedger.records.count == 3)
    #expect(Set(journal.spendingLedger.records.map(\.id)).count == 3)
    #expect(journal.spendingLedger.settledPoints == 0)
}

@Test func watchingContinuesIntoNegativeBalanceUntilExplicitStop() throws {
    let now = instant("2026-09-19", 20)
    var journal = Journal(now: now)
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    let session = try #require(journal.spendingLedger.activeCartoon)
    let later = now.addingTimeInterval(3600)
    #expect(SpendingEngine.remainingPoints(in: journal, at: later) == -30)
    #expect(journal.spendingLedger.activeCartoon != nil)
    let finished = try SpendingEngine.stopCartoon(id: session.id, now: later, journal: &journal)
    #expect(finished.duration == 3600)
    #expect(finished.points == 30)
    #expect(finished.endReason == .user)
    try SpendingEngine.startCartoon(now: later, journal: &journal)
    #expect(journal.spendingLedger.activeCartoon != nil)
}

@Test func manualConsumesBalanceWithoutChangingEarningsOrRewards() throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    journal.rewards.append(Reward(period: "2026-09", stage: .month25, awardedAt: now))
    #expect(journal.totalPoints == 65)
    let expense = try SpendingEngine.addManual(id: UUID(), name: "  买贴纸  ", points: 60, now: now, journal: &journal)
    #expect(expense.name == "买贴纸")
    #expect(expense.points == 60)
    #expect(expense.kind == .manual)
    #expect(expense.endedAt == now)
    #expect(journal.totalPoints == 65)
    #expect(journal.rewards.count == 1)
    #expect(SpendingEngine.remainingPoints(in: journal, at: now) == 5)
    _ = try SpendingEngine.addManual(id: UUID(), name: "玩具", points: 6, now: now, journal: &journal)
    #expect(SpendingEngine.remainingPoints(in: journal, at: now) == -1)
    #expect(journal.totalPoints == 65)
}

@Test func manualValidationAndDuplicateSubmissionAreAtomic() throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    let original = journal
    for name in ["  \n", String(repeating: "字", count: 41)] {
        #expect(throws: SpendingError.invalidName) {
            try SpendingEngine.addManual(id: UUID(), name: name, points: 1, now: now, journal: &journal)
        }
    }
    for points in [0, -1] {
        #expect(throws: SpendingError.invalidPoints) {
            try SpendingEngine.addManual(id: UUID(), name: "贴纸", points: points, now: now, journal: &journal)
        }
    }
    #expect(journal == original)
    let id = UUID()
    _ = try SpendingEngine.addManual(id: id, name: "贴纸", points: 1, now: now, journal: &journal)
    #expect(throws: SpendingError.duplicateRequest) {
        try SpendingEngine.addManual(id: id, name: "贴纸", points: 1, now: now, journal: &journal)
    }
    #expect(journal.spendingLedger.settledPoints == 1)
    #expect(journal.spendingLedger.records.count == 1)
}

@Test func zeroCreditCanStartButRepeatedTimerActionsAreRejected() throws {
    let now = instant("2026-09-19", 20)
    var empty = Journal(now: now)
    try SpendingEngine.startCartoon(now: now, journal: &empty)
    #expect(empty.spendingLedger.activeCartoon != nil)
    var journal = fundedJournal()
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    let session = try #require(journal.spendingLedger.activeCartoon)
    #expect(throws: SpendingError.alreadyWatching) {
        try SpendingEngine.startCartoon(now: now.addingTimeInterval(10), journal: &journal)
    }
    _ = try SpendingEngine.stopCartoon(id: session.id, now: now.addingTimeInterval(120), journal: &journal)
    #expect(throws: SpendingError.noActiveSession) {
        try SpendingEngine.stopCartoon(id: session.id, now: now.addingTimeInterval(121), journal: &journal)
    }
    #expect(journal.spendingLedger.records.count == 1)
}

@Test func manualExpenseDuringViewingCanOverdrawWithoutStopping() throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    let session = try #require(journal.spendingLedger.activeCartoon)
    let later = now.addingTimeInterval(300)
    _ = try SpendingEngine.addManual(id: UUID(), name: "玩具", points: 20, now: later, journal: &journal)
    #expect(SpendingEngine.remainingPoints(in: journal, at: later) == -7)
    #expect(journal.spendingLedger.activeCartoon?.id == session.id)
    let stopped = try SpendingEngine.stopCartoon(id: session.id, now: now.addingTimeInterval(500), journal: &journal)
    #expect(stopped.duration == 500)
    #expect(journal.spendingLedger.settledPoints == 24)
}

@Test func reachingZeroDoesNotEndWatching() throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    let later = now.addingTimeInterval(300)
    _ = try SpendingEngine.addManual(id: UUID(), name: "拼图", points: 13, now: later, journal: &journal)
    #expect(journal.spendingLedger.activeCartoon != nil)
    #expect(SpendingEngine.remainingPoints(in: journal, at: later) == 0)
    #expect(SpendingEngine.remainingPoints(in: journal, at: later.addingTimeInterval(60)) == -1)
}

@Test func cancellingEarningsKeepsWatchingAndPastExpenses() throws {
    let now = instant("2026-09-19", 20)
    var journal = fundedJournal()
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    let session = try #require(journal.spendingLedger.activeCartoon)
    let later = now.addingTimeInterval(300)
    journal.records = []
    #expect(journal.spendingLedger.activeCartoon?.id == session.id)
    #expect(SpendingEngine.remainingPoints(in: journal, at: later) == -2)
    _ = try SpendingEngine.addManual(id: UUID(), name: "贴纸", points: 1, now: later, journal: &journal)
    _ = try SpendingEngine.stopCartoon(id: session.id, now: later, journal: &journal)
    #expect(journal.spendingLedger.settledPoints == 3)
    #expect(SpendingEngine.remainingPoints(in: journal, at: later) == -3)
}

@Test func sessionSurvivesMidnightAndRejectsBackwardClock() throws {
    let now = instant("2026-09-19", 23, 59)
    var journal = fundedJournal()
    try SpendingEngine.startCartoon(now: now, journal: &journal)
    #expect(throws: SpendingError.clockChanged) {
        try SpendingEngine.stopCartoon(id: journal.spendingLedger.activeCartoon!.id, now: now.addingTimeInterval(-1), journal: &journal)
    }
    let restored = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
    journal = restored
    let end = instant("2026-09-20", 0, 4)
    CheckInEngine.reconcile(&journal, now: end)
    let result = try SpendingEngine.stopCartoon(id: journal.spendingLedger.activeCartoon!.id, now: end, journal: &journal)
    #expect(result.duration == 300)
    #expect(result.points == 2)
    #expect(BeijingCalendar.key(result.startedAt) == "2026-09-19")
    #expect(BeijingCalendar.key(result.endedAt) == "2026-09-20")
}

@Test func legacyJournalsDecodeWithEmptySpendingLedger() throws {
    let journal = fundedJournal()
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
    json.removeValue(forKey: "spending")
    let restored = try JSONDecoder().decode(Journal.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored.spendingLedger.records.isEmpty)
    #expect(restored.spendingLedger.activeCartoon == nil)
    #expect(restored.totalPoints == 15)
}

@Test @MainActor
func swiftDataSpendingRoundTripKeepsActiveSessionAndSettlesOnce() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("spending.store")
    let now = instant("2026-09-19", 20)
    do {
        let persistence = try JournalPersistence(now: now, url: url)
        var journal = fundedJournal()
        _ = try SpendingEngine.addManual(id: UUID(), name: "贴纸", points: 13, now: now, journal: &journal)
        try SpendingEngine.startCartoon(now: now, journal: &journal)
        try persistence.commit(journal)
    }
    do {
        let reopened = try JournalPersistence(now: now.addingTimeInterval(500), url: url)
        var journal = reopened.journal
        #expect(journal.spendingLedger.activeCartoon?.startedAt == now)
        let stopped = try SpendingEngine.stopCartoon(id: journal.spendingLedger.activeCartoon!.id, now: now.addingTimeInterval(500), journal: &journal)
        #expect(stopped.duration == 500)
        #expect(stopped.points == 4)
        try reopened.commit(journal)
    }
    let reopened = try JournalPersistence(now: now.addingTimeInterval(1000), url: url)
    let journal = reopened.journal
    #expect(journal.totalPoints == 15)
    #expect(journal.spendingLedger.records.count == 2)
    #expect(journal.spendingLedger.settledPoints == 17)
    #expect(journal.spendingLedger.activeCartoon == nil)
    #expect(SpendingEngine.remainingPoints(in: journal, at: now.addingTimeInterval(1000)) == -2)
}
