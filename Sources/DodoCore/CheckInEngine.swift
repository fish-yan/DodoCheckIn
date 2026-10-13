import Foundation

enum CheckInError: String, LocalizedError {
    case unavailable = "该项目已隐藏或删除，请在打卡配置中查看。"
    case historical = "这一天已经封存，请返回今天打卡。"
    case clockChanged = "设备日期或时间已回退，请恢复正确时间后再试。"
    case alreadyFinished = "这个任务今天已经记录过啦。"
    case locked = "先在规定时间内完成三餐和作业，再来点亮这颗星星。"
    case wrongPassword = "家长密码不正确，请重新输入。"
    case cannotRetry = "只有今天超时的作业可以由家长开启重试。"
    case noPending = "当前没有需要家长确认的任务。"
    case noSelection = "请逐项选择需要补打或取消的打卡。"
    case staleSelection = "所选项目状态已变化，请重新选择后提交。"

    var errorDescription: String? { rawValue }
}

enum CheckInResult: Equatable {
    case started, paused, completed, failed
}

enum ReviewDecision: String, CaseIterable, Identifiable {
    case unchanged, makeup, cancel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unchanged: "暂不处理"
        case .makeup: "补打卡"
        case .cancel: "取消打卡"
        }
    }
}

struct ReviewResult {
    var confirmed: [Mission]
    var cancelled: [Mission]
    var rewards: [Reward]
    var revokedRewards: [Reward]
}

enum CheckInEngine {
    static func adoptAutomaticScoring(_ journal: inout Journal, now: Date) {
        guard journal.automaticScoringAdoptedAt == nil else { return }
        journal.schemaVersion = 3
        journal.automaticScoringAdoptedAt = now
        // Legacy passed records now count directly; original timestamps and review history are untouched.
        RewardEngine.preserveQualifications(&journal)
        _ = RewardEngine.settle(&journal, now: now)
    }

    static func validateDay(_ day: String, now: Date, journal: Journal) throws {
        guard day == BeijingCalendar.key(now) else { throw CheckInError.historical }
        guard day >= journal.latestDay else { throw CheckInError.clockChanged }
    }

    static func reconcile(_ journal: inout Journal, now: Date) {
        let today = BeijingCalendar.key(now)
        if journal.expandedRulesStartDay == nil {
            journal.expandedRulesStartDay = max(journal.latestDay, today)
            _ = RewardEngine.revokeUnqualifiedToday(&journal, now: now)
        }
        if journal.listeningStartDay == nil {
            journal.listeningStartDay = max(journal.latestDay, today)
        }
        journal.latestDay = max(journal.latestDay, today)
        for index in journal.records.indices {
            let record = journal.records[index]
            guard let latest = record.latest, latest.outcome == .running else { continue }
            let midnight = BeijingCalendar.nextDay(BeijingCalendar.date(record.day)!)
            let deadline = record.mission.maximumDuration.map { latest.startedAt.addingTimeInterval($0) }
            let strictLimit = record.mission.configuration.map { $0.rule.comparison == .equal || !$0.rule.includesTimerLimit } ?? false
            let exceeded = deadline.map { strictLimit ? now >= $0 : now > $0 } ?? false
            guard now >= midnight || exceeded else { continue }
            let attemptIndex = journal.records[index].attempts.count - 1
            journal.records[index].attempts[attemptIndex].outcome = .failed
            journal.records[index].attempts[attemptIndex].closedAt = min(deadline ?? midnight, midnight)
            journal.records[index].attempts[attemptIndex].explanation = exceeded && (deadline ?? midnight) < midnight
                ? "超过规定用时，今天继续加油" : "当天未结束，记录已封存"
        }
    }

    static func tap(
        _ mission: Mission, day: String, now: Date, isRestDay: Bool, journal: inout Journal
    ) throws -> CheckInResult {
        try validateDay(day, now: now, journal: journal)
        reconcile(&journal, now: now)
        if journal.configuration != nil && !journal.visibleMissions(on: day).contains(mission) {
            throw CheckInError.unavailable
        }
        let resolved = journal.record(mission, day: day)?.mission
            ?? journal.missions(on: day).first { $0 == mission } ?? mission
        defer { _ = RewardEngine.settle(&journal, now: now) }
        if resolved.configuration != nil {
            return try configuredTap(resolved, day: day, now: now, isRestDay: isRestDay, journal: &journal)
        }
        if mission == .promptness && !journal.isPromptnessUnlocked(on: day) {
            throw CheckInError.locked
        }
        if let index = journal.records.firstIndex(where: { $0.day == day && $0.mission == mission }),
           journal.records[index].latest?.outcome != .cancelled {
            if mission == .reading, let latest = journal.records[index].latest, latest.outcome == .paused {
                guard now >= (latest.endedAt ?? latest.startedAt) else { throw CheckInError.clockChanged }
                journal.records[index].attempts.append(Attempt(startedAt: now, outcome: .running))
                return .started
            }
            guard let latest = journal.records[index].latest, latest.outcome == .running else {
                throw CheckInError.alreadyFinished
            }
            guard now >= latest.startedAt else { throw CheckInError.clockChanged }
            let paused = mission == .reading && journal.records[index].readingDuration(at: now) <= 15 * 60
            let attemptIndex = journal.records[index].attempts.count - 1
            journal.records[index].attempts[attemptIndex].endedAt = now
            journal.records[index].attempts[attemptIndex].closedAt = now
            journal.records[index].attempts[attemptIndex].outcome = paused ? .paused : .passed
            if mission == .reading { journal.records[index].ruleSnapshot = mission.ruleDescription }
            return paused ? .paused : .completed
        }

        let passed = singlePasses(mission, day: day, now: now, isRestDay: isRestDay)
        let outcome: AttemptOutcome = mission.isTimed ? .running : (passed ? .passed : .failed)
        let attempt = Attempt(
            startedAt: now, endedAt: mission.isTimed ? nil : now, closedAt: mission.isTimed ? nil : now,
            outcome: outcome, explanation: outcome == .failed ? "已超过规定打卡时间" : nil
        )
        if let index = journal.records.firstIndex(where: { $0.day == day && $0.mission == mission }) {
            journal.records[index].attempts.append(attempt)
            journal.records[index].confirmedAt = nil
            journal.records[index].parentMakeupPoints = nil
            journal.records[index].isRestDay = isRestDay
            journal.records[index].ruleSnapshot = mission == .wake
                ? (isRestDay ? "休息日 08:30 前" : "工作日 07:30 前") : mission.ruleDescription
        } else {
            journal.records.append(MissionRecord(
                day: day, mission: mission, points: mission.points,
                ruleSnapshot: mission == .wake
                    ? (isRestDay ? "休息日 08:30 前" : "工作日 07:30 前") : mission.ruleDescription,
                isRestDay: isRestDay, attempts: [attempt]
            ))
        }
        return mission.isTimed ? .started : (passed ? .completed : .failed)
    }

    private static func configuredTap(_ mission: Mission, day: String, now: Date, isRestDay: Bool,
                                      journal: inout Journal) throws -> CheckInResult {
        let config = mission.configuration!
        if config.rule.requiresPrerequisites && !journal.isPromptnessUnlocked(on: day) { throw CheckInError.locked }
        let index = journal.records.firstIndex { $0.day == day && $0.mission == mission }
        if let index, let latest = journal.records[index].latest, latest.outcome != .cancelled {
            guard now >= (latest.endedAt ?? latest.startedAt) else { throw CheckInError.clockChanged }
            if mission.isAccumulating && (latest.outcome == .paused || latest.outcome == .passed) {
                journal.records[index].attempts.append(Attempt(startedAt: now, outcome: .running))
                return .started
            }
            guard latest.outcome == .running else { throw CheckInError.alreadyFinished }
            let duration = mission.isAccumulating ? journal.records[index].readingDuration(at: now) : latest.duration(at: now)
            let points = max(config.rule.points(for: duration, unitPoints: config.points), journal.records[index].parentMakeupPoints ?? 0)
            let attemptIndex = journal.records[index].attempts.count - 1
            journal.records[index].attempts[attemptIndex].endedAt = now
            journal.records[index].attempts[attemptIndex].closedAt = now
            journal.records[index].points = points
            let outcome: AttemptOutcome = points > 0 ? .passed : mission.isAccumulating ? .paused : .failed
            journal.records[index].attempts[attemptIndex].outcome = outcome
            if outcome == .failed { journal.records[index].attempts[attemptIndex].explanation = "未达到计时要求" }
            return outcome == .passed ? .completed : outcome == .paused ? .paused : .failed
        }
        let isTimed = config.rule.kind == .timer
        let second = now.timeIntervalSince(BeijingCalendar.calendar.startOfDay(for: now))
        let end = (isRestDay ? config.rule.restDayEndMinute ?? config.rule.endMinute : config.rule.endMinute) * 60
        let inWindow = second >= Double(config.rule.startMinute * 60) && (config.rule.includesEnd ? second <= Double(end) : second < Double(end))
        let passed = config.rule.kind != .timeWindow || inWindow
        let outcome: AttemptOutcome = isTimed ? .running : passed ? .passed : .failed
        let attempt = Attempt(startedAt: now, endedAt: isTimed ? nil : now, closedAt: isTimed ? nil : now,
                              outcome: outcome, explanation: outcome == .failed ? "未在规定打卡时间内" : nil)
        if let index {
            journal.records[index].attempts.append(attempt)
            journal.records[index].points = isTimed ? 0 : config.points
            journal.records[index].confirmedAt = nil
            journal.records[index].confirmedPoints = nil
            journal.records[index].parentMakeupPoints = nil
        } else {
            journal.records.append(MissionRecord(day: day, mission: mission, points: isTimed ? 0 : config.points,
                                                 ruleSnapshot: mission.ruleDescription, isRestDay: isRestDay, attempts: [attempt]))
        }
        return isTimed ? .started : passed ? .completed : .failed
    }

    static func singlePasses(_ mission: Mission, day: String, now: Date, isRestDay: Bool) -> Bool {
        switch mission {
        case .wake:
            now < BeijingCalendar.time(on: day, hour: isRestDay ? 8 : 7, minute: 30)
        case .washing:
            now <= BeijingCalendar.time(on: day, hour: 21, minute: 0)
        case .sleeping:
            now <= BeijingCalendar.time(on: day, hour: 21, minute: 30)
        default: true
        }
    }

    static func review(
        day: String, decisions: [Mission: ReviewDecision], password: String, now: Date, journal: inout Journal
    ) throws -> ReviewResult {
        guard password == AppRules.parentPassword else { throw CheckInError.wrongPassword }
        try validateDay(day, now: now, journal: journal)
        let selected = decisions.filter { $0.value != .unchanged }
        guard !selected.isEmpty else { throw CheckInError.noSelection }
        var next = journal
        reconcile(&next, now: now)
        let available = Set(next.missions(on: day))
        for (mission, decision) in selected {
            guard available.contains(mission) else { throw CheckInError.staleSelection }
            if decision == .cancel {
                guard let record = next.record(mission, day: day), record.latest?.outcome != .cancelled else {
                    throw CheckInError.staleSelection
                }
            }
        }
        var cancellations = Set(selected.filter { $0.value == .cancel }.map(\.key))
        if !cancellations.isDisjoint(with: Mission.prerequisites),
           next.record(.promptness, day: day)?.isPassed == true,
           next.record(.promptness, day: day)?.mission.requiresPrerequisites == true {
            cancellations.insert(.promptness)
        }
        let confirmations = Set(selected.filter { $0.value == .makeup }.map(\.key)).subtracting(cancellations)
        for index in next.records.indices where next.records[index].day == day {
            let mission = next.records[index].mission
            if cancellations.contains(mission) {
                let last = next.records[index].attempts.count - 1
                next.records[index].attempts[last].outcomeBeforeCancellation = next.records[index].attempts[last].outcome
                next.records[index].attempts[last].outcome = .cancelled
                next.records[index].attempts[last].cancelledAt = now
                if next.records[index].attempts[last].closedAt == nil {
                    next.records[index].attempts[last].closedAt = now
                }
                next.records[index].confirmedAt = nil
                next.records[index].confirmedPoints = nil
                next.records[index].parentMakeupPoints = nil
            }
        }
        var supplemented = Set<Mission>()
        for mission in next.missions(on: day) where confirmations.contains(mission) {
            if supplement(mission, day: day, now: now, journal: &next) { supplemented.insert(mission) }
        }
        let confirmed = next.missions(on: day).filter { supplemented.contains($0) }
        let cancelled = next.missions(on: day).filter { cancellations.contains($0) }
        for (kind, missions) in [("makeup", confirmed), ("cancel", cancelled)] where !missions.isEmpty {
            next.reviews.append(ParentReview(day: day, at: now, missionIDs: missions.map(\.rawValue), kind: kind))
        }
        let revoked = RewardEngine.revokeUnqualifiedToday(&next, now: now)
        let rewards = RewardEngine.settle(&next, now: now)
        journal = next
        return ReviewResult(confirmed: confirmed, cancelled: cancelled, rewards: rewards, revokedRewards: revoked)
    }

    private static func supplement(_ mission: Mission, day: String, now: Date, journal: inout Journal) -> Bool {
        let marker = Attempt(startedAt: now, endedAt: now, closedAt: now, outcome: .passed,
                             explanation: "家长补打卡，按原项目规则分值补记", isParentMakeup: true)
        if let index = journal.records.firstIndex(where: { $0.day == day && $0.mission == mission }) {
            let record = journal.records[index]
            guard !record.isPassed || record.latest?.outcome == .running else { return false }
            var points = max(record.effectivePoints, mission.points)
            if record.latest?.outcome == .running {
                if mission.isAccumulating, let rule = mission.configuration?.rule {
                    points = max(points, rule.points(for: record.readingDuration(at: now), unitPoints: mission.points))
                }
                let last = record.attempts.count - 1
                journal.records[index].attempts[last].endedAt = now
                journal.records[index].attempts[last].closedAt = now
                journal.records[index].attempts[last].outcome = mission.usesSegmentedTimer ? .paused : .failed
                journal.records[index].attempts[last].explanation = "家长补打时结束计时，原计时记录保留"
            }
            journal.records[index].attempts.append(marker)
            journal.records[index].points = points
            journal.records[index].parentMakeupPoints = points
        } else {
            journal.records.append(MissionRecord(day: day, mission: mission, points: mission.points,
                ruleSnapshot: mission.ruleDescription, isRestDay: false, attempts: [marker], parentMakeupPoints: mission.points))
        }
        return true
    }

    static func retryHomework(day: String, password: String, now: Date, journal: inout Journal) throws {
        guard password == AppRules.parentPassword else { throw CheckInError.wrongPassword }
        try validateDay(day, now: now, journal: journal)
        reconcile(&journal, now: now)
        guard let index = journal.records.firstIndex(where: { $0.day == day && $0.mission == .homework }),
              journal.records[index].latest?.outcome == .failed,
              journal.records[index].mission.isTimed,
              journal.records[index].confirmedAt == nil else { throw CheckInError.cannotRetry }
        journal.records[index].attempts.append(Attempt(startedAt: now, outcome: .running))
        journal.reviews.append(ParentReview(day: day, at: now, missionIDs: [Mission.homework.rawValue], kind: "retry"))
    }
}
