import Foundation
import Observation

struct Celebration: Identifiable {
    var id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var isReward = false
}

enum ParentAction: String, Identifiable {
    case manage, retryHomework
    var id: String { rawValue }
}

@MainActor
@Observable
final class AppStore {
    private(set) var journal: Journal
    private(set) var now: Date
    private(set) var holidayCalendars: [Int: HolidayCalendar] = [:]
    private(set) var holidayUpdateMessage = ""
    var celebration: Celebration?
    var errorMessage: String?
    var toast: String?
    private let persistence: JournalPersistence
    private var lastHolidayRequest: Date?
    private var isUpdatingHolidays = false
    private let cacheDirectory: URL?

    init(persistence: JournalPersistence, now: Date = Date()) {
        self.persistence = persistence
        journal = persistence.journal
        self.now = now
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HolidayCalendars", isDirectory: true)
        loadHolidayCalendars()
        refresh(at: now)
    }

    var today: String { BeijingCalendar.key(now) }
    var currentYear: Int { BeijingCalendar.calendar.component(.year, from: now) }
    var isRestDay: Bool {
        holidayCalendars[currentYear]?.isRestDay(now) ?? BeijingCalendar.calendar.isDateInWeekend(now)
    }
    var hasHolidayCalendar: Bool { holidayCalendars[currentYear] != nil }
    var spentPoints: Int { journal.spendingLedger.spentPoints(at: now) }
    var remainingPoints: Int { SpendingEngine.remainingPoints(in: journal, at: now) }
    var missions: [Mission] { journal.visibleMissions(on: today) }
    var dailyGoal: Int { journal.dailyGoal(on: today) }
    var editableMissions: [MissionConfiguration] {
        journal.configuration.flatMap { ConfigurationEngine.editableValue(in: $0.missions) } ?? MissionConfiguration.defaults
    }
    var monthlyExploration: MonthlyExploration { journal.exploration(in: now) }

    func refresh(at date: Date = Date()) {
        now = date
        var next = journal
        CheckInEngine.reconcile(&next, now: date)
        if BeijingCalendar.key(date) >= next.latestDay { ConfigurationEngine.adopt(&next, now: date) }
        CheckInEngine.adoptAutomaticScoring(&next, now: date)
        if next != journal {
            do {
                try save(next)
            } catch { errorMessage = "保存失败，请重试。\n\(error.localizedDescription)" }
        }
    }

    func tap(_ mission: Mission, day: String) {
        refresh()
        do {
            var next = journal
            let previousRecord = journal.record(mission, day: day)
            let previousPoints = previousRecord?.isPassed == true ? previousRecord?.points ?? 0 : 0
            let result = try CheckInEngine.tap(mission, day: day, now: now, isRestDay: isRestDay, journal: &next)
            let previousRewardIDs = Set(journal.rewards.map(\.id))
            let rewards = next.rewards.filter { !previousRewardIDs.contains($0.id) }
            try save(next)
            switch result {
            case .started:
                toast = mission.usesSegmentedTimer ? "\(mission.title)开始！停止后会保存累计时间。" : "\(mission.title)出发！完成后记得回来结束计时。"
            case .paused:
                let duration = next.record(mission, day: day)?.readingDuration(at: now) ?? 0
                toast = "\(mission.title)已暂停，累计 \(BeijingCalendar.durationText(duration))，稍后可以继续。"
            case .completed:
                let gained = mission.isAccumulating ? max(0, (next.record(mission, day: day)?.points ?? 0) - previousPoints) : next.record(mission, day: day)?.points ?? mission.points
                if gained > 0 {
                    celebration = Celebration(title: "恭喜打卡成功！", subtitle: "\(mission.title) +\(gained) 分，星星点亮啦！", symbol: "star.fill")
                } else {
                    toast = "累计时间已保存，继续努力就能再得分啦！"
                }
            case .failed: toast = "这次未达到时间要求，可以请家长检查并补打。"
            }
            if !rewards.isEmpty {
                celebration = Celebration(title: "星球奖励到达！",
                    subtitle: rewards.map { "\($0.title) +\($0.points) 分" }.joined(separator: "\n"),
                    symbol: "globe.asia.australia.fill", isReward: true)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func authenticate(_ action: ParentAction, password: String, day: String, decisions: [Mission: ReviewDecision] = [:]) throws {
        refresh()
        var next = journal
        let result: ReviewResult
        if action == .manage {
            result = try CheckInEngine.review(day: day, decisions: decisions, password: password, now: now, journal: &next)
        } else {
            try CheckInEngine.retryHomework(day: day, password: password, now: now, journal: &next)
            result = ReviewResult(confirmed: [], cancelled: [], rewards: [], revokedRewards: [])
        }
        let gained = result.confirmed.reduce(0) { $0 + (next.record($1, day: day)?.effectivePoints ?? 0) - (journal.record($1, day: day)?.effectivePoints ?? 0) }
        let reachedGoal = !journal.isGoalMet(on: day) && next.isGoalMet(on: day)
        try save(next)
        let cancelledMessage = result.cancelled.isEmpty ? "" : "\n已取消 \(result.cancelled.count) 项，孩子可重新打卡。"
        let revokedMessage = result.revokedRewards.isEmpty ? "" : "\n同步撤回不再达标的奖励 \(result.revokedRewards.reduce(0) { $0 + $1.points }) 分。"
        if !result.rewards.isEmpty {
            celebration = Celebration(
                title: "星球奖励到达！",
                subtitle: result.rewards.map { "\($0.title) +\($0.points) 分" }.joined(separator: "\n")
                    + "\n本次补打得分 +\(gained)" + cancelledMessage + revokedMessage,
                symbol: "globe.asia.australia.fill", isReward: true
            )
        } else if !result.confirmed.isEmpty {
            celebration = Celebration(
                title: reachedGoal ? "今日目标达成！" : "补打卡成功！",
                subtitle: "有效打卡分 +\(gained)\n" + (reachedGoal ? "今天已经获得至少 \(dailyGoal) 分，真棒！" : "每一个小进步，都让飞船更进一步。") + cancelledMessage + revokedMessage,
                symbol: reachedGoal ? "flag.checkered" : "checkmark.seal.fill"
            )
        } else if action == .manage {
            toast = "已取消 \(result.cancelled.count) 项，孩子可以重新打卡。" + revokedMessage
        } else { toast = "作业已重新开始计时，这次一起专心完成吧！" }
    }

    func startCartoon() {
        refresh()
        do {
            var next = journal
            try SpendingEngine.startCartoon(now: now, journal: &next)
            try save(next)
        } catch { errorMessage = error.localizedDescription }
    }

    func stopCartoon(id: UUID) {
        refresh()
        // Ignore a repeated end tap after the expense was already persisted.
        if journal.spendingLedger.records.contains(where: { $0.id == id }) { return }
        do {
            var next = journal
            let expense = try SpendingEngine.stopCartoon(id: id, now: now, journal: &next)
            try save(next)
            toast = "观看已结束，本次消耗 \(expense.points) 分。"
        } catch { errorMessage = error.localizedDescription }
    }

    func addManualExpense(id: UUID, name: String, points: Int) throws {
        refresh()
        var next = journal
        _ = try SpendingEngine.addManual(id: id, name: name, points: points, now: now, journal: &next)
        try save(next)
    }

    func saveMission(_ mission: MissionConfiguration, password: String) throws {
        refresh()
        var next = journal
        try ConfigurationEngine.saveMission(mission, password: password, now: now, journal: &next)
        try save(next)
    }

    func setMissionEnabled(_ id: String, enabled: Bool, password: String) throws {
        refresh()
        var next = journal
        try ConfigurationEngine.setMissionEnabled(id, enabled: enabled, password: password, now: now, journal: &next)
        try save(next)
    }

    func deleteMission(_ id: String, password: String) throws {
        refresh()
        var next = journal
        try ConfigurationEngine.deleteMission(id, password: password, now: now, journal: &next)
        try save(next)
    }

    func saveRewards(dailyGoal: Int, week: WeeklyRewardConfiguration, month: MonthlyRewardConfiguration, password: String) throws {
        refresh()
        var next = journal
        try ConfigurationEngine.saveRewards(dailyGoal: dailyGoal, week: week, month: month, password: password, now: now, journal: &next)
        try save(next)
    }

    private func save(_ next: Journal) throws {
        try persistence.commit(next)
        journal = next
    }

    private func loadHolidayCalendars() {
        for year in currentYear...(currentYear + 1) {
            holidayCalendars[year] = HolidayCalendar.bundled(year: year)
            if let url = cacheDirectory?.appendingPathComponent("\(year).json"),
               let data = try? Data(contentsOf: url),
               let calendar = try? HolidayCalendar.validated(data, year: year) {
                holidayCalendars[year] = calendar
            }
        }
    }

    func updateHolidays() async {
        guard !isUpdatingHolidays else { return }
        if let lastHolidayRequest, now.timeIntervalSince(lastHolidayRequest) < 6 * 60 * 60 { return }
        isUpdatingHolidays = true
        lastHolidayRequest = now
        defer { isUpdatingHolidays = false }
        loadHolidayCalendars()
        for year in currentYear...(currentYear + 1) {
            do {
                let calendar = try await HolidayCalendar.download(year: year)
                if let directory = cacheDirectory {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try JSONEncoder().encode(calendar).write(to: directory.appendingPathComponent("\(year).json"), options: .atomic)
                }
                holidayCalendars[year] = calendar
                if year == currentYear { holidayUpdateMessage = "节假日日历已更新" }
            } catch {
                if year == currentYear {
                    holidayUpdateMessage = hasHolidayCalendar ? "正在使用离线节假日日历" : "未取得本年度安排，暂按周末规则"
                }
            }
        }
    }
}
