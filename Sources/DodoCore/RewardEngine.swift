import Foundation

enum RewardEngine {
    static func settle(_ journal: inout Journal, now: Date) -> [Reward] {
        let existing = Set(journal.rewards.map(\.id))
        let additions = eligibleRewards(journal, now: now).filter { !existing.contains($0.id) }
        journal.rewards.append(contentsOf: additions)
        return additions
    }

    static func revokeUnqualifiedToday(_ journal: inout Journal, now: Date) -> [Reward] {
        let today = BeijingCalendar.key(now)
        let eligible = Set(eligibleRewards(journal, now: now).map(\.id))
        let revoked = journal.rewards.filter {
            $0.day == today && !($0.qualification?.isMet(in: journal) ?? eligible.contains($0.id))
        }
        let revokedIDs = Set(revoked.map(\.id))
        journal.rewards.removeAll { revokedIDs.contains($0.id) }
        return revoked
    }

    private static func eligibleRewards(_ journal: Journal, now: Date) -> [Reward] {
        let today = BeijingCalendar.key(now)
        let week = BeijingCalendar.days(in: BeijingCalendar.week(containing: now))
        let month = BeijingCalendar.days(in: BeijingCalendar.month(containing: now))
        var candidates: [Reward] = []
        let weekly = journal.weeklyReward(on: today)
        let weeklyDays = week.filter { $0 <= today && journal.isGoalMet(on: $0) }.count
        if let weekly {
            if weeklyDays >= weekly.days {
                candidates.append(Reward(period: week[0], stage: .week, awardedAt: now,
                                         awardedPoints: weekly.points, titleSnapshot: "周达标\(weekly.days)天奖励"))
            }
        } else if week.last == today && week.allSatisfy({ journal.isGoalMet(on: $0) }) {
            candidates.append(Reward(period: week[0], stage: .week, awardedAt: now))
        }
        let achieved = month.filter { $0 <= today && journal.isGoalMet(on: $0) }.count
        if let monthly = journal.monthlyReward(on: today) {
            if achieved >= min(monthly.days, month.count) {
                candidates.append(Reward(period: String(today.prefix(7)), stage: .month25, awardedAt: now,
                                         awardedPoints: monthly.points, titleSnapshot: "月达标\(min(monthly.days, month.count))天奖励"))
            }
        } else {
            if achieved >= 25 {
                candidates.append(Reward(period: String(today.prefix(7)), stage: .month25, awardedAt: now))
            }
            if month.last == today && achieved == month.count {
                candidates.append(Reward(period: String(today.prefix(7)), stage: .monthFull, awardedAt: now))
            }
        }
        return candidates.map { reward in
            var result = reward
            result.qualification = qualification(for: reward, journal: journal)
            return result
        }
    }

    static func preserveQualifications(_ journal: inout Journal) {
        for index in journal.rewards.indices where journal.rewards[index].qualification == nil {
            journal.rewards[index].qualification = qualification(for: journal.rewards[index], journal: journal)
        }
    }

    private static func qualification(for reward: Reward, journal: Journal) -> RewardQualification {
        let interval = reward.stage == .week
            ? BeijingCalendar.week(containing: reward.awardedAt) : BeijingCalendar.month(containing: reward.awardedAt)
        let days = BeijingCalendar.days(in: interval)
        let requiredDays: Int
        switch reward.stage {
        case .week: requiredDays = journal.weeklyReward(on: reward.day)?.days ?? 7
        case .month25: requiredDays = min(journal.monthlyReward(on: reward.day)?.days ?? 25, days.count)
        case .monthFull: requiredDays = days.count
        }
        return RewardQualification(requiredDays: requiredDays, dailyGoals: Dictionary(uniqueKeysWithValues:
            days.filter { $0 <= reward.day }.map { ($0, journal.dailyGoal(on: $0)) }))
    }
}

struct PeriodStatistics: Equatable {
    var count: Int
    var effectivePoints: Int
    var rewardPoints: Int
    var expectedCount: Int
    var achievedDays: Int
    var topMissions: [Mission]
    var missionCounts: [Mission: Int]
    var totalPoints: Int { effectivePoints + rewardPoints }
    var rate: Double { expectedCount == 0 ? 0 : Double(count) / Double(expectedCount) }

    static func calculate(journal: Journal, interval: DateInterval, now: Date) -> PeriodStatistics {
        let today = BeijingCalendar.key(now)
        let days = BeijingCalendar.days(in: interval).filter { $0 >= journal.firstDay && $0 <= today }
        let daySet = Set(days)
        let records = journal.records.filter { daySet.contains($0.day) && $0.isEffective }
        let counts = Dictionary(grouping: records, by: \.mission).mapValues(\.count)
        let catalog = journal.missions(on: today)
        let order = Dictionary(uniqueKeysWithValues: catalog.enumerated().map { ($1, $0) })
        let top = counts.keys.sorted {
            if counts[$0] == counts[$1] { return (order[$0] ?? Int.max, $0.rawValue) < (order[$1] ?? Int.max, $1.rawValue) }
            return counts[$0]! > counts[$1]!
        }
        return PeriodStatistics(
            count: records.count, effectivePoints: records.reduce(0) { $0 + $1.effectivePoints },
            rewardPoints: journal.rewards.filter { daySet.contains($0.day) }.reduce(0) { $0 + $1.points },
            expectedCount: days.reduce(0) { $0 + journal.missions(on: $1).count },
            achievedDays: days.filter { journal.isGoalMet(on: $0) }.count,
            topMissions: Array(top.prefix(3)), missionCounts: counts
        )
    }
}
