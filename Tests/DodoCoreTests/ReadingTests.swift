import Foundation
import Testing
@testable import DodoCore

@Test func readingAccumulatesSegmentsExcludingBreaksAndScoresOnce() throws {
    let day = "2026-09-21"
    let start = instant(day, 12)
    var journal = Journal(now: start)
    for (offset, expected) in [(0.0, CheckInResult.started), (300, .paused), (3600, .started), (4200, .paused)] {
        #expect(try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(offset), isRestDay: false, journal: &journal) == expected)
    }
    #expect(journal.record(.reading, day: day)?.readingDuration(at: start.addingTimeInterval(4700)) == 900)
    #expect(journal.selfScore(on: day) == 0)
    _ = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(4800), isRestDay: false, journal: &journal)
    let end = start.addingTimeInterval(4801)
    #expect(try CheckInEngine.tap(.reading, day: day, now: end, isRestDay: false, journal: &journal) == .completed)
    #expect(journal.record(.reading, day: day)?.readingDuration(at: end) == 901)
    #expect(journal.selfScore(on: day) == 2)
    #expect(journal.effectiveScore(on: day) == 2)
    _ = try settleFixtureRewards(day: day, password: "885802", now: end, journal: &journal)
    #expect(journal.effectiveScore(on: day) == 2)
    let stats = PeriodStatistics.calculate(journal: journal, interval: BeijingCalendar.month(containing: end), now: end)
    #expect(stats.count == 1)
    #expect(throws: CheckInError.alreadyFinished) {
        try CheckInEngine.tap(.reading, day: day, now: end, isRestDay: false, journal: &journal)
    }
}

@Test(arguments: [false, true])
func readingCancellationResetsAllSegments(complete: Bool) throws {
    let day = "2026-09-21"
    let start = instant(day, 12)
    var journal = Journal(now: start)
    for offset in [0.0, 300, 600, complete ? 1300 : 900] {
        _ = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(offset), isRestDay: false, journal: &journal)
    }
    let cancel = start.addingTimeInterval(1400)
    if complete { _ = try settleFixtureRewards(day: day, password: "885802", now: cancel, journal: &journal) }
    _ = try CheckInEngine.review(day: day, decisions: [.reading: .cancel], password: "885802", now: cancel, journal: &journal)
    #expect(journal.record(.reading, day: day)?.readingDuration(at: cancel) == 0)
    #expect(journal.effectiveScore(on: day) == 0)
    _ = try CheckInEngine.tap(.reading, day: day, now: cancel, isRestDay: false, journal: &journal)
    #expect(try CheckInEngine.tap(.reading, day: day, now: cancel.addingTimeInterval(300), isRestDay: false, journal: &journal) == .paused)
    #expect(journal.record(.reading, day: day)?.readingDuration(at: cancel.addingTimeInterval(1000)) == 300)
    #expect(journal.record(.reading, day: day)?.attempts.count == 3)
}

@Test(arguments: [false, true])
func readingIsSealedAtMidnightWithoutCarryingTime(running: Bool) throws {
    let day = "2026-09-21"
    let start = instant(day, 23)
    var journal = Journal(now: start)
    _ = try CheckInEngine.tap(.reading, day: day, now: start, isRestDay: false, journal: &journal)
    _ = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(600), isRestDay: false, journal: &journal)
    if running {
        _ = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(1200), isRestDay: false, journal: &journal)
    }
    let nextDay = "2026-09-22"
    let midnight = BeijingCalendar.date(nextDay)!
    CheckInEngine.reconcile(&journal, now: midnight)
    #expect(journal.record(.reading, day: day)?.readingDuration(at: midnight) == 600)
    #expect(journal.selfScore(on: day) == 0)
    #expect(throws: CheckInError.historical) {
        try CheckInEngine.tap(.reading, day: day, now: midnight, isRestDay: false, journal: &journal)
    }
    _ = try CheckInEngine.tap(.reading, day: nextDay, now: midnight, isRestDay: false, journal: &journal)
    #expect(journal.record(.reading, day: nextDay)?.readingDuration(at: midnight) == 0)
}

@Test @MainActor
func readingSegmentsSurviveDiskReopenPausedAndRunning() throws {
    let day = "2026-09-21"
    let start = instant(day, 12)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("reading.store")
    do {
        let store = try JournalPersistence(now: start, url: url)
        var journal = store.journal
        _ = try CheckInEngine.tap(.reading, day: day, now: start, isRestDay: false, journal: &journal)
        _ = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(300), isRestDay: false, journal: &journal)
        try store.commit(journal)
    }
    do {
        let store = try JournalPersistence(now: start.addingTimeInterval(3600), url: url)
        var journal = store.journal
        #expect(journal.record(.reading, day: day)?.readingDuration(at: start.addingTimeInterval(3600)) == 300)
        _ = try CheckInEngine.tap(.reading, day: day, now: start.addingTimeInterval(3600), isRestDay: false, journal: &journal)
        try store.commit(journal)
    }
    let end = start.addingTimeInterval(4201)
    let reopened = try JournalPersistence(now: end, url: url)
    var journal = reopened.journal
    #expect(journal.record(.reading, day: day)?.readingDuration(at: end) == 901)
    #expect(try CheckInEngine.tap(.reading, day: day, now: end, isRestDay: false, journal: &journal) == .completed)
}
