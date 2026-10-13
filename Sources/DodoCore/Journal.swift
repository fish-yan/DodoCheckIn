import Foundation

enum AttemptOutcome: String, Codable, Sendable {
    case running, paused, passed, failed, cancelled
}

struct Attempt: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    // Automatic expiry is separate from an actual child end tap.
    var closedAt: Date?
    var outcome: AttemptOutcome
    var explanation: String?
    // Optional fields keep journals from earlier versions decodable.
    var cancelledAt: Date?
    var outcomeBeforeCancellation: AttemptOutcome?
    var isParentMakeup: Bool?

    func duration(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? closedAt ?? now).timeIntervalSince(startedAt))
    }
}

struct MissionRecord: Codable, Identifiable, Equatable, Sendable {
    var day: String
    var mission: Mission
    var points: Int
    var ruleSnapshot: String
    var isRestDay: Bool
    var attempts: [Attempt]
    var confirmedAt: Date?
    var confirmedPoints: Int?
    // A makeup grants at least one unit; later timed earnings replace, rather than add to, this floor.
    var parentMakeupPoints: Int?

    var id: String { "\(day):\(mission.rawValue)" }
    var latest: Attempt? { attempts.last }
    var isPassed: Bool {
        mission.isAccumulating ? points > 0 && latest?.outcome != .cancelled : latest?.outcome == .passed
    }
    var effectivePoints: Int {
        isPassed ? points : 0
    }
    var isEffective: Bool { effectivePoints > 0 }
    var isFullyConfirmed: Bool { isEffective && effectivePoints == points }
    var pendingPoints: Int { isPassed ? max(0, points - effectivePoints) : 0 }

    /// A parent cancellation ends a reading round; earlier segments remain in history.
    func readingDuration(at now: Date) -> TimeInterval {
        let start = attempts.lastIndex { $0.outcome == .cancelled }.map { $0 + 1 } ?? 0
        return attempts.dropFirst(start).reduce(0) { total, attempt in
            guard attempt.outcome == .paused || attempt.outcome == .passed || attempt.outcome == .running else {
                return total
            }
            return total + attempt.duration(at: now)
        }
    }
}

struct ParentReview: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var day: String
    var at: Date
    var missionIDs: [String]
    var kind: String
}

enum RewardStage: String, Codable, Sendable {
    case week, month25, monthFull

    var points: Int { self == .week ? 10 : 50 }
    var title: String {
        switch self {
        case .week: "自然周全勤奖励"
        case .month25: "月度 25 天奖励"
        case .monthFull: "全月达标补足奖励"
        }
    }
}

struct RewardQualification: Codable, Equatable, Sendable {
    var requiredDays: Int
    var dailyGoals: [String: Int]

    func isMet(in journal: Journal) -> Bool {
        dailyGoals.filter { journal.effectiveScore(on: $0.key) >= $0.value }.count >= requiredDays
    }
}

struct Reward: Codable, Identifiable, Equatable, Sendable {
    var period: String
    var stage: RewardStage
    var awardedAt: Date
    var id: String { "\(period):\(stage.rawValue)" }
    var awardedPoints: Int?
    var titleSnapshot: String?
    var qualification: RewardQualification?
    var points: Int { awardedPoints ?? stage.points }
    var title: String { titleSnapshot ?? stage.title }
    var day: String { BeijingCalendar.key(awardedAt) }
}

struct Journal: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var firstDay: String
    var latestDay: String
    var records: [MissionRecord] = []
    var reviews: [ParentReview] = []
    var rewards: [Reward] = []
    // Missing in legacy journals. Dates before adoption retain the original catalog and goal.
    var expandedRulesStartDay: String?
    // Adoption date for the seventeenth mission; historical denominators stay unchanged.
    var listeningStartDay: String?
    // Optional for compatibility with journals created before the spending tab.
    var spending: SpendingLedger?
    var configuration: ConfigurationSchedule?
    var automaticScoringAdoptedAt: Date?

    var spendingLedger: SpendingLedger { spending ?? SpendingLedger() }

    init(now: Date) {
        firstDay = BeijingCalendar.key(now)
        latestDay = firstDay
        expandedRulesStartDay = firstDay
        listeningStartDay = firstDay
    }

    func record(_ mission: Mission, day: String) -> MissionRecord? {
        records.first { $0.day == day && $0.mission == mission }
    }

    func selfScore(on day: String) -> Int {
        records.filter { $0.day == day && $0.isPassed }.reduce(0) { $0 + $1.points }
    }

    func effectiveScore(on day: String) -> Int {
        records.filter { $0.day == day }.reduce(0) { $0 + $1.effectivePoints }
    }

    func isGoalMet(on day: String) -> Bool {
        effectiveScore(on: day) >= dailyGoal(on: day)
    }

    func dailyGoal(on day: String) -> Int {
        configuration.flatMap { ConfigurationSchedule.value(in: $0.dailyGoals, on: day) } ?? (usesExpandedRules(on: day) ? AppRules.dailyGoal : 13)
    }

    func missions(on day: String) -> [Mission] {
        var catalog = visibleMissions(on: day)
        // Hidden/deleted tasks with records remain available in history and parent corrections.
        for record in records where record.day == day && !catalog.contains(record.mission) {
            catalog.append(record.mission)
        }
        return catalog
    }

    func visibleMissions(on day: String) -> [Mission] {
        if let values = configuration.flatMap({ ConfigurationSchedule.value(in: $0.missions, on: day) }) {
            return values.filter(\.isEnabled).map { config in record(Mission(rawValue: config.id), day: day)?.mission ?? Mission(configuration: config) }
        }
        return Mission.allCases.filter { mission in
            switch mission {
            case .listening: listeningStartDay.map { day >= $0 } ?? false
            case .hygiene, .dressing: usesExpandedRules(on: day)
            default: true
            }
        }
    }

    private func usesExpandedRules(on day: String) -> Bool {
        guard let expandedRulesStartDay else { return false }
        return day >= expandedRulesStartDay
    }

    var totalPoints: Int {
        records.reduce(0) { $0 + $1.effectivePoints } + rewards.reduce(0) { $0 + $1.points }
    }

    func exploration(in date: Date) -> MonthlyExploration {
        let month = String(BeijingCalendar.key(date).prefix(7))
        let earned = records.filter { $0.day.hasPrefix(month + "-") }.reduce(0) { $0 + $1.effectivePoints }
        let bonus = rewards.filter { $0.day.hasPrefix(month + "-") }.reduce(0) { $0 + $1.points }
        return MonthlyExploration(month: month, points: earned + bonus, step: monthlyReward(on: BeijingCalendar.key(date))?.planetStep ?? AppRules.pointsPerPlanet)
    }

    func weeklyReward(on day: String) -> WeeklyRewardConfiguration? {
        configuration.flatMap { ConfigurationSchedule.value(in: $0.weeks, on: day) }
    }

    func monthlyReward(on day: String) -> MonthlyRewardConfiguration? {
        configuration.flatMap { ConfigurationSchedule.value(in: $0.months, on: day) }
    }

    func isPromptnessUnlocked(on day: String) -> Bool {
        Mission.prerequisites.allSatisfy { record($0, day: day)?.isPassed == true }
    }
}

struct MonthlyExploration: Equatable, Sendable {
    var month: String
    var points: Int
    var step = AppRules.pointsPerPlanet

    var unlockedPlanets: Int { min(AppRules.planetNames.count, points / step) }
}
