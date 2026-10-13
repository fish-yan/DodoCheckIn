import Foundation

enum MissionRuleKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case timeWindow, timer, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timeWindow: "时间区间打卡"
        case .timer: "计时"
        case .none: "无规则"
        }
    }
}

enum TimerComparison: String, Codable, CaseIterable, Identifiable, Sendable {
    case greater = ">", equal = "=", less = "<"
    var id: String { rawValue }
}

struct MissionRuleConfiguration: Codable, Equatable, Sendable {
    var kind: MissionRuleKind = .none
    var startMinute = 0
    var endMinute = 23 * 60 + 59
    var restDayEndMinute: Int?
    var includesEnd = true
    var comparison: TimerComparison = .less
    var minutes = 30
    // Built-in meals/homework preserve the original inclusive upper boundary.
    var includesTimerLimit = false
    var requiresPrerequisites = false

    var maximumDuration: TimeInterval? {
        guard kind == .timer else { return nil }
        switch comparison {
        case .greater: return nil
        case .less: return Double(minutes * 60)
        case .equal: return Double((minutes + 1) * 60)
        }
    }

    func points(for duration: TimeInterval, unitPoints: Int) -> Int {
        switch comparison {
        case .greater: return Int(duration / Double(minutes * 60)) * unitPoints
        case .equal: return Int(duration / 60) == minutes ? unitPoints : 0
        case .less: return (includesTimerLimit ? duration <= Double(minutes * 60) : duration < Double(minutes * 60)) ? unitPoints : 0
        }
    }

    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    func description(points: Int) -> String {
        switch kind {
        case .none: return requiresPrerequisites ? "三餐和作业全部达标后解锁" : "完成后打卡"
        case .timeWindow:
            let limit = includesEnd ? "（含结束时刻）" : "（不含结束时刻）"
            let rest = restDayEndMinute.map { "，休息日截止\(Self.clock($0))" } ?? ""
            return "\(Self.clock(startMinute))–\(Self.clock(endMinute))\(limit)\(rest)"
        case .timer:
            switch comparison {
            case .greater: return "可分段累计，每满\(minutes)分钟记\(points)分"
            case .equal: return "完整分钟数等于\(minutes)（\(minutes):00–\(minutes):59）"
            case .less: return "用时\(includesTimerLimit ? "≤" : "<")\(minutes)分钟"
            }
        }
    }
}

struct MissionConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var iconID: String
    var group: String
    var rule: MissionRuleConfiguration
    var points: Int
    // Older saved configurations have no visibility field and remain enabled.
    var isHidden: Bool?
    var isEnabled: Bool {
        get { isHidden != true }
        set { isHidden = !newValue }
    }

    static var defaults: [MissionConfiguration] {
        Mission.allCases.map { mission in
            var rule = MissionRuleConfiguration()
            switch mission {
            case .wake:
                rule.kind = .timeWindow
                rule.endMinute = 7 * 60 + 30
                rule.restDayEndMinute = 8 * 60 + 30
                rule.includesEnd = false
            case .washing, .sleeping:
                rule.kind = .timeWindow
                rule.endMinute = mission == .washing ? 21 * 60 : 21 * 60 + 30
            case .breakfast, .lunch, .dinner, .homework:
                rule.kind = .timer
                rule.minutes = mission == .homework ? 60 : 30
                rule.includesTimerLimit = true
            case .reading:
                rule.kind = .timer
                rule.comparison = .greater
                rule.minutes = 15
            case .promptness: rule.requiresPrerequisites = true
            default: break
            }
            return MissionConfiguration(id: mission.rawValue, name: mission.title, iconID: mission.rawValue,
                                        group: mission.group, rule: rule, points: mission.points)
        }
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 20,
              Mission.selectableIcons.contains(where: { $0.rawValue == iconID }), Mission.groups.contains(group),
              (1...10_000).contains(points), (1...1440).contains(rule.minutes),
              (0..<1440).contains(rule.startMinute), (0..<1440).contains(rule.endMinute),
              rule.startMinute <= rule.endMinute,
              rule.restDayEndMinute.map({ (rule.startMinute..<1440).contains($0) }) ?? true else {
            throw ConfigurationError.invalidMission
        }
    }
}

struct WeeklyRewardConfiguration: Codable, Equatable, Sendable {
    var days = 7
    var points = 10
}

struct MonthlyRewardConfiguration: Codable, Equatable, Sendable {
    var days = 25
    var points = 50
    var planetStep = 50
}

struct DatedConfiguration<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var effectiveDay: String
    var value: Value
}

struct ConfigurationSchedule: Codable, Equatable, Sendable {
    var missions: [DatedConfiguration<[MissionConfiguration]>]
    var dailyGoals: [DatedConfiguration<Int>]
    var weeks: [DatedConfiguration<WeeklyRewardConfiguration>]
    var months: [DatedConfiguration<MonthlyRewardConfiguration>]

    static func value<T>(in versions: [DatedConfiguration<T>], on day: String) -> T? {
        versions.filter { $0.effectiveDay <= day }.max { $0.effectiveDay < $1.effectiveDay }?.value
    }

    static func replace<T>(_ versions: inout [DatedConfiguration<T>], day: String, value: T) {
        // A new save supersedes older pending settings, so they cannot restore stale values later.
        versions.removeAll { $0.effectiveDay >= day }
        versions.append(DatedConfiguration(effectiveDay: day, value: value))
        versions.sort { $0.effectiveDay < $1.effectiveDay }
    }
}

enum ConfigurationError: String, LocalizedError {
    case missingMission = "该打卡项目已删除，请刷新列表。"
    case invalidMission = "请填写1～20字的名称、有效时间范围及1～10000的正整数分值。时间区间暂不跨午夜，计时分钟为1～1440。"
    case invalidRewards = "日目标、奖励分数和星球步长须为1～10000的正整数；周天数为1～7，月天数为1～31。"
    case duplicateName = "已有同名打卡项目，请换一个名称。"
    var errorDescription: String? { rawValue }
}

enum ConfigurationEngine {
    static func editableValue<T>(in versions: [DatedConfiguration<T>]) -> T? {
        versions.max { $0.effectiveDay < $1.effectiveDay }?.value
    }

    static func adopt(_ journal: inout Journal, now: Date) {
        guard journal.configuration == nil else { return }
        RewardEngine.preserveQualifications(&journal)
        let today = BeijingCalendar.key(now)
        journal.schemaVersion = max(journal.schemaVersion, 2)
        journal.configuration = ConfigurationSchedule(
            missions: [.init(effectiveDay: today, value: MissionConfiguration.defaults)],
            dailyGoals: [.init(effectiveDay: today, value: AppRules.dailyGoal)],
            weeks: [.init(effectiveDay: today, value: WeeklyRewardConfiguration())],
            months: [.init(effectiveDay: today, value: MonthlyRewardConfiguration())]
        )
    }

    static func saveMission(_ input: MissionConfiguration, password: String, now: Date, journal: inout Journal) throws {
        guard password == AppRules.parentPassword else { throw CheckInError.wrongPassword }
        try CheckInEngine.validateDay(BeijingCalendar.key(now), now: now, journal: journal)
        var mission = input
        mission.name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try mission.validate()
        var next = journal
        adopt(&next, now: now)
        var schedule = next.configuration!
        let day = BeijingCalendar.key(now)
        var tasks = editableValue(in: schedule.missions) ?? MissionConfiguration.defaults
        guard !tasks.contains(where: { $0.id != mission.id && $0.name == mission.name }) else { throw ConfigurationError.duplicateName }
        if let index = tasks.firstIndex(where: { $0.id == mission.id }) { tasks[index] = mission }
        else { tasks.append(mission) }
        ConfigurationSchedule.replace(&schedule.missions, day: day, value: tasks)
        next.configuration = schedule
        journal = next
    }

    static func setMissionEnabled(_ id: String, enabled: Bool, password: String, now: Date, journal: inout Journal) throws {
        try updateMissionCatalog(password: password, now: now, journal: &journal) { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw ConfigurationError.missingMission }
            tasks[index].isEnabled = enabled
        }
    }

    static func deleteMission(_ id: String, password: String, now: Date, journal: inout Journal) throws {
        try updateMissionCatalog(password: password, now: now, journal: &journal) { tasks in
            guard tasks.contains(where: { $0.id == id }) else { throw ConfigurationError.missingMission }
            tasks.removeAll { $0.id == id }
        }
    }

    private static func updateMissionCatalog(password: String, now: Date, journal: inout Journal,
                                             update: (inout [MissionConfiguration]) throws -> Void) throws {
        guard password == AppRules.parentPassword else { throw CheckInError.wrongPassword }
        try CheckInEngine.validateDay(BeijingCalendar.key(now), now: now, journal: journal)
        var next = journal
        adopt(&next, now: now)
        var schedule = next.configuration!
        var tasks = editableValue(in: schedule.missions) ?? MissionConfiguration.defaults
        try update(&tasks)
        ConfigurationSchedule.replace(&schedule.missions, day: BeijingCalendar.key(now), value: tasks)
        next.configuration = schedule
        journal = next
    }

    static func saveRewards(dailyGoal: Int, week: WeeklyRewardConfiguration, month: MonthlyRewardConfiguration,
                            password: String, now: Date, journal: inout Journal) throws {
        guard password == AppRules.parentPassword else { throw CheckInError.wrongPassword }
        try CheckInEngine.validateDay(BeijingCalendar.key(now), now: now, journal: journal)
        guard (1...10_000).contains(dailyGoal), (1...7).contains(week.days), (1...31).contains(month.days),
              [week.points, month.points, month.planetStep].allSatisfy({ (1...10_000).contains($0) }) else {
            throw ConfigurationError.invalidRewards
        }
        var next = journal
        RewardEngine.preserveQualifications(&next)
        adopt(&next, now: now)
        var schedule = next.configuration!
        let today = BeijingCalendar.key(now)
        ConfigurationSchedule.replace(&schedule.dailyGoals, day: today, value: dailyGoal)
        ConfigurationSchedule.replace(&schedule.weeks, day: today, value: week)
        ConfigurationSchedule.replace(&schedule.months, day: today, value: month)
        next.configuration = schedule
        // Only valid check-in points qualify. Existing reward IDs/amounts stay intact.
        _ = RewardEngine.settle(&next, now: now)
        journal = next
    }
}
