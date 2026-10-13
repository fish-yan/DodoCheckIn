import Foundation

enum ExpenseKind: String, Codable, Sendable {
    case cartoon, manual
}

enum ExpenseEndReason: String, Codable, Sendable {
    case user, balanceExhausted
}

struct PointExpense: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: ExpenseKind
    var name: String
    var startedAt: Date
    var endedAt: Date
    var points: Int
    var endReason: ExpenseEndReason

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

struct CartoonSession: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    func duration(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }

    func points(at now: Date) -> Int {
        Int(duration(at: now) / SpendingEngine.secondsPerPoint)
    }

}

struct SpendingLedger: Codable, Equatable, Sendable {
    var records: [PointExpense] = []
    var activeCartoon: CartoonSession?
    var lastEventAt: Date?

    var settledPoints: Int { records.reduce(0) { $0 + $1.points } }

    func spentPoints(at now: Date) -> Int {
        settledPoints + (activeCartoon?.points(at: now) ?? 0)
    }
}

enum SpendingError: String, LocalizedError {
    case alreadyWatching = "已经在记录观看时间，请先结束当前这次观看。"
    case noActiveSession = "这次观看已经结束，请查看消耗记录。"
    case invalidName = "请输入 1 至 40 个字的消耗项目名称。"
    case invalidPoints = "请输入大于 0 的整数积分。"
    case duplicateRequest = "该笔消耗已经记录，请勿重复提交。"
    case clockChanged = "设备时间已回退，请恢复正确时间后再记录消耗。"

    var errorDescription: String? { rawValue }
}

enum SpendingEngine {
    static let secondsPerPoint: TimeInterval = 120

    static func remainingPoints(in journal: Journal, at now: Date) -> Int {
        journal.totalPoints - journal.spendingLedger.spentPoints(at: now)
    }

    private static func validateTime(_ now: Date, journal: Journal) throws {
        guard BeijingCalendar.key(now) >= journal.latestDay,
              now >= (journal.spendingLedger.lastEventAt ?? .distantPast),
              now >= (journal.spendingLedger.activeCartoon?.startedAt ?? .distantPast) else {
            throw SpendingError.clockChanged
        }
    }

    static func startCartoon(now: Date, journal: inout Journal) throws {
        try validateTime(now, journal: journal)
        var next = journal
        var ledger = next.spendingLedger
        guard ledger.activeCartoon == nil else { throw SpendingError.alreadyWatching }
        ledger.activeCartoon = CartoonSession(id: UUID(), startedAt: now)
        ledger.lastEventAt = now
        next.spending = ledger
        journal = next
    }

    @discardableResult
    static func stopCartoon(id: UUID, now: Date, journal: inout Journal) throws -> PointExpense {
        try validateTime(now, journal: journal)
        guard let session = journal.spendingLedger.activeCartoon, session.id == id else {
            throw SpendingError.noActiveSession
        }
        return finishCartoon(
            &journal, session: session, at: now, reason: .user
        )
    }

    @discardableResult
    static func addManual(id: UUID, name: String, points: Int, now: Date, journal: inout Journal) throws -> PointExpense {
        try validateTime(now, journal: journal)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 40 else { throw SpendingError.invalidName }
        guard points > 0 else { throw SpendingError.invalidPoints }
        guard journal.spendingLedger.activeCartoon?.id != id,
              !journal.spendingLedger.records.contains(where: { $0.id == id }) else { throw SpendingError.duplicateRequest }
        var next = journal
        var ledger = next.spendingLedger
        let expense = PointExpense(id: id, kind: .manual, name: name, startedAt: now, endedAt: now, points: points, endReason: .user)
        ledger.records.append(expense)
        ledger.lastEventAt = now
        next.spending = ledger
        journal = next
        return expense
    }

    private static func finishCartoon(
        _ journal: inout Journal, session: CartoonSession, at end: Date, reason: ExpenseEndReason
    ) -> PointExpense {
        let expense = PointExpense(
            id: session.id, kind: .cartoon, name: "看动画片", startedAt: session.startedAt,
            endedAt: end, points: session.points(at: end), endReason: reason
        )
        var ledger = journal.spendingLedger
        ledger.records.append(expense)
        ledger.activeCartoon = nil
        ledger.lastEventAt = max(ledger.lastEventAt ?? end, end)
        journal.spending = ledger
        return expense
    }
}
