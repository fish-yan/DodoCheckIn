import SwiftUI

struct StatisticsView: View {
    let store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var displayedMonth = BeijingCalendar.month(containing: Date()).start
    @State private var selectedDay = BeijingCalendar.key(Date())
    @State private var detailDay: HistorySelection?

    private let lavender = Color(red: 0.57, green: 0.46, blue: 1)
    private var accent: Color { colorScheme == .dark ? Color(red: 0.72, green: 0.63, blue: 1) : SpaceTheme.actionFill }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    introduction
                    todaySummary
                    periodCard(title: "本周探索", interval: BeijingCalendar.week(containing: store.now), isMonth: false)
                    periodCard(title: "本月探索", interval: BeijingCalendar.month(containing: store.now), isMonth: true)
                    calendarCard
                    selectedSummary
                    Text("合计积分包含有效打卡分和奖励分，奖励分不影响每日 \(store.dailyGoal) 分目标。")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 12)
                        .accessibilityIdentifier("statistics.footnote")
                }
                .padding(.horizontal, 10).padding(.bottom, 16)
                .foregroundStyle(colorScheme == .dark ? Color.primary : SpaceTheme.navy)
            }
            .background {
                LinearGradient(colors: colorScheme == .dark
                    ? [Color(red: 0.09, green: 0.09, blue: 0.17), Color(.systemGroupedBackground)]
                    : [Color(red: 0.92, green: 0.92, blue: 1), Color(red: 0.96, green: 0.98, blue: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            }
            .tint(accent)
            .navigationTitle("打卡统计").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $detailDay) { selection in
                DayDetailView(journal: store.journal, day: selection.id, now: store.now)
            }
        }
    }

    private var introduction: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("每一步成长，都算数")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.8).lineLimit(1)
                Text("打卡成功立即计入成长记录")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            SpaceArtwork("StatisticsHero").frame(width: 126, height: 120)
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
    }

    private var todaySummary: some View {
        let stats = PeriodStatistics.calculate(
            journal: store.journal,
            interval: DateInterval(start: BeijingCalendar.calendar.startOfDay(for: store.now), end: BeijingCalendar.nextDay(store.now)),
            now: store.now
        )
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("今日战绩", symbol: "sun.max.fill", color: .orange,
                           trailing: store.journal.isGoalMet(on: store.today) ? "目标已达成" : "目标 \(store.dailyGoal) 分")
            LazyVGrid(columns: metricColumns, spacing: 8) {
                StatisticsMetricTile(title: "有效次数", value: "\(stats.count)", unit: "次", symbol: "checkmark.circle.fill", color: .green)
                StatisticsMetricTile(title: "有效打卡分", value: "\(stats.effectivePoints)", unit: "分", symbol: "star.fill", color: .orange)
            }
        }.modifier(StatisticsSurface(tint: .yellow))
    }

    private func periodCard(title: String, interval: DateInterval, isMonth: Bool) -> some View {
        let stats = PeriodStatistics.calculate(journal: store.journal, interval: interval, now: store.now)
        let days = BeijingCalendar.days(in: interval)
        let rewardPeriod = isMonth ? String(store.today.prefix(7)) : days[0]
        let earned = store.journal.rewards.filter { $0.period == rewardPeriod }
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading(title, symbol: isMonth ? "moon.stars.fill" : "flag.fill", color: isMonth ? .blue : lavender,
                           trailing: "\(stats.achievedDays) / \(days.count) 天达标")
            LazyVGrid(columns: metricColumns, spacing: 8) {
                StatisticsMetricTile(title: "有效次数", value: "\(stats.count)", unit: "次", symbol: "calendar", color: .blue)
                StatisticsMetricTile(title: "有效打卡分", value: "\(stats.effectivePoints)", unit: "分", symbol: "star.fill", color: .orange)
                StatisticsMetricTile(title: "奖励分", value: "\(stats.rewardPoints)", unit: "分", symbol: "gift.fill", color: .pink)
                StatisticsMetricTile(title: "合计积分", value: "\(stats.totalPoints)", unit: "分", symbol: "star.circle.fill", color: .indigo)
            }
            if isMonth {
                monthlyGoalCard(achievedDays: stats.achievedDays, totalDays: days.count)
                if let reward = earned.first(where: { $0.stage == .month25 }) {
                    rewardLine(reward.title, subtitle: "奖励 \(reward.points) 分", artwork: "StatisticsMedal", earned: true)
                    if let bonus = earned.first(where: { $0.stage == .monthFull }) {
                        rewardLine(bonus.title, subtitle: "奖励 \(bonus.points) 分", artwork: "StatisticsMedal", earned: true)
                    } else if store.journal.monthlyReward(on: store.today) == nil {
                        rewardLine("全月达标", subtitle: "奖励 100 分", artwork: "StatisticsMedal", earned: false)
                    }
                } else if let monthly = store.journal.monthlyReward(on: store.today) {
                    rewardLine("累计 \(min(monthly.days, days.count)) 天", subtitle: "奖励 \(monthly.points) 分", artwork: "StatisticsMedal", earned: earned.contains { $0.stage == .month25 })
                } else {
                rewardLine("累计 25 天", subtitle: "奖励 50 分", artwork: "StatisticsMedal", earned: earned.contains { $0.stage == .month25 })
                rewardLine("全月达标", subtitle: "奖励 100 分", artwork: "StatisticsMedal", earned: earned.contains { $0.stage == .monthFull })
                }
            } else {
                weeklyTrail(days: days)
                if let reward = earned.first(where: { $0.stage == .week }) {
                    rewardLine(reward.title, subtitle: "奖励 \(reward.points) 分", artwork: "StatisticsChest", earned: true)
                } else {
                    rewardLine("本周累计达标 \(store.journal.weeklyReward(on: store.today)?.days ?? 7) 天", subtitle: "奖励 \(store.journal.weeklyReward(on: store.today)?.points ?? 10) 分", artwork: "StatisticsChest", earned: false)
                }
            }
            Text("最常点亮的任务").font(.subheadline.bold())
            if stats.topMissions.isEmpty {
                HStack(spacing: 10) {
                    SpaceArtwork("EmptyExplorer").frame(width: 78, height: 72)
                    Text("星星正在等你点亮。\n完成打卡，就能积累成长积分哦。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(stats.topMissions.enumerated()), id: \.element) { index, mission in
                        HStack(spacing: 10) {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background([Color.orange, Color.gray, Color.brown][index].gradient, in: Circle())
                            SpaceArtwork(mission.artworkName).frame(width: 28, height: 28)
                            Text(mission.title).font(.subheadline.weight(.medium))
                            Spacer(minLength: 4)
                            Text("\(stats.missionCounts[mission] ?? 0) 次").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }.modifier(StatisticsSurface(tint: isMonth ? .cyan : lavender))
    }

    private func monthlyGoalCard(achievedDays: Int, totalDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("本月达标进度").font(.headline)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(achievedDays)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("/ \(totalDays) 天").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(achievedDays), total: Double(totalDays))
                .progressViewStyle(MonthlyStarProgressStyle(tint: accent))
            Text("每天满\(store.dailyGoal)分，点亮一天")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("本月达标进度")
        .accessibilityValue("\(achievedDays) / \(totalDays) 天，每天有效打卡满\(store.dailyGoal)分，点亮一天")
        .accessibilityIdentifier("statistics.monthlyGoal")
    }

    private func sectionHeading(_ title: String, symbol: String, color: Color, trailing: String = "") -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 25, weight: .semibold))
                .foregroundStyle(color.gradient).frame(width: 30).accessibilityHidden(true)
            Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer(minLength: 2)
            if !trailing.isEmpty {
                Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func weeklyTrail(days: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let achieved = store.journal.isGoalMet(on: day)
                VStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(achieved ? Color.orange.gradient : Color.gray.opacity(0.28).gradient)
                        .shadow(color: achieved ? .orange.opacity(0.2) : .clear, radius: 3, y: 2)
                    Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index])
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day)，\(achieved ? "目标达成" : "未达目标")")
            }
        }
        .background(alignment: .top) {
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width / 14, y: 14))
                    path.addLine(to: CGPoint(x: geometry.size.width * 13 / 14, y: 14))
                }.stroke(accent.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
        }
        .padding(.vertical, 2)
    }

    private var tileFill: Color { colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.86) }

    private func rewardLine(_ title: String, subtitle: String, artwork: String, earned: Bool) -> some View {
        HStack(spacing: 10) {
            SpaceArtwork(artwork).frame(width: 44, height: 44)
                .saturation(earned || artwork == "StatisticsChest" ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(earned ? "已获得" : "探索中").font(.caption2)
                .foregroundStyle(earned ? accent : .secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SpaceArtwork("PlanetSaturn").frame(width: 36, height: 32)
                Text("成长日历").font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "sparkle").foregroundStyle(.orange).accessibilityHidden(true)
            }
            if dynamicTypeSize.isAccessibilitySize {
                DatePicker("查看日期", selection: Binding(
                    get: { BeijingCalendar.date(selectedDay)! },
                    set: { selectedDay = BeijingCalendar.key($0); displayedMonth = BeijingCalendar.month(containing: $0).start }
                ), in: BeijingCalendar.date(store.journal.firstDay)!...max(store.now, BeijingCalendar.date(store.journal.firstDay)!), displayedComponents: .date)
                .environment(\.calendar, BeijingCalendar.calendar)
                .environment(\.timeZone, BeijingCalendar.calendar.timeZone)
                .datePickerStyle(.compact)
            } else {
                HStack {
                    Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(!canShowPreviousMonth)
                        .opacity(canShowPreviousMonth ? 1 : 0.3)
                        .accessibilityLabel("上个月")
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Spacer()
                    Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(!canShowNextMonth)
                        .opacity(canShowNextMonth ? 1 : 0.3)
                        .accessibilityLabel("下个月")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { name in
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(0..<leadingEmptyDays, id: \.self) { _ in Color.clear.frame(height: 44) }
                    ForEach(monthDays, id: \.self) { day in
                        Button { selectedDay = day } label: {
                            VStack(spacing: 4) {
                                Text("\(Int(day.suffix(2))!)").font(.subheadline.weight(day == selectedDay ? .bold : .regular))
                                Circle().fill(dotColor(day)).frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(day == selectedDay ? accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(day == selectedDay ? .white : .primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(day > store.today || day < store.journal.firstDay)
                        .opacity(day > store.today || day < store.journal.firstDay ? 0.3 : 1)
                        .accessibilityLabel("\(day)，\(store.journal.isGoalMet(on: day) ? "目标达成" : "未达目标")")
                    }
                }
                HStack(spacing: 16) {
                    Label { Text("达成当日目标") } icon: { Circle().fill(.teal).frame(width: 6, height: 6) }
                    Label { Text("有记录") } icon: { Circle().fill(.orange).frame(width: 6, height: 6) }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
        }.modifier(StatisticsSurface(tint: lavender, subtle: true))
    }

    private var metricColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var selectedSummary: some View {
        Button { detailDay = HistorySelection(id: selectedDay) } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill").font(.system(size: 25))
                    .foregroundStyle(accent.gradient).frame(width: 44, height: 48)
                    .background(accent.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedDay == store.today ? "今天的打卡详情" : "\(selectedDay) 打卡详情").font(.subheadline.bold())
                    Text("打卡得分 \(store.journal.effectiveScore(on: selectedDay)) 分")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("查看时间、耗时和奖励记录").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(accent)
            }
            .modifier(StatisticsSurface(tint: lavender, subtle: true))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.detail")
    }

    private var canShowPreviousMonth: Bool {
        displayedMonth > BeijingCalendar.month(containing: BeijingCalendar.date(store.journal.firstDay)!).start
    }

    private var canShowNextMonth: Bool {
        displayedMonth < BeijingCalendar.month(containing: store.now).start
    }

    private var monthDays: [String] { BeijingCalendar.days(in: BeijingCalendar.month(containing: displayedMonth)) }
    private var leadingEmptyDays: Int { (BeijingCalendar.calendar.component(.weekday, from: displayedMonth) + 5) % 7 }
    private var monthTitle: String {
        let parts = BeijingCalendar.calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(String(parts.year!)) 年 \(parts.month!) 月"
    }

    private func changeMonth(_ delta: Int) {
        displayedMonth = BeijingCalendar.calendar.date(byAdding: .month, value: delta, to: displayedMonth)!
        selectedDay = min(store.today, max(store.journal.firstDay, BeijingCalendar.key(displayedMonth)))
    }

    private func dotColor(_ day: String) -> Color {
        if store.journal.isGoalMet(on: day) { return day == selectedDay ? SpaceTheme.mint : .teal }
        return store.journal.records.contains { $0.day == day } ? .orange : .clear
    }
}

private struct MonthlyStarProgressStyle: ProgressViewStyle {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(1, max(0, configuration.fractionCompleted ?? 0))
        GeometryReader { geometry in
            let trackWidth = max(0, geometry.size.width - 40)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.14))
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(0.08), lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: trackWidth * fraction)
                    }
                    .frame(width: trackWidth, height: 18)
                    .offset(x: 20)
                SpaceArtwork("MonthlyProgressStar")
                    .frame(width: 40, height: 40)
                    .shadow(color: .orange.opacity(0.15), radius: 4, y: 2)
                    .offset(x: trackWidth * fraction)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
    }
}

private struct StatisticsSurface: ViewModifier {
    let tint: Color
    var subtle = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.padding(12)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(colors: [tint.opacity(subtle ? 0.035 : 0.15), tint.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(colorScheme == .dark ? tint.opacity(0.22) : .white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: tint.opacity(colorScheme == .dark ? 0.04 : 0.09), radius: 8, y: 4)
    }
}

private struct StatisticsMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(color.gradient)
                .frame(width: 36, height: 40)
                .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText()).monospacedDigit()
                    Text(unit).font(.caption.weight(.medium))
                }.lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
        .background(colorScheme == .dark ? .white.opacity(0.06) : .white.opacity(0.87), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold()).contentTransition(.numericText())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct HistorySelection: Identifiable { var id: String }

struct DayDetailView: View {
    let journal: Journal
    let day: String
    let now: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("打卡得分 \(journal.effectiveScore(on: day)) 分")
                    Label(journal.isGoalMet(on: day) ? "今日目标已达成" : "每日目标 \(journal.dailyGoal(on: day)) 分", systemImage: "flag.checkered")
                    if day < BeijingCalendar.key(now) {
                        Text("当天记录已封存，不能补打或补确认。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("任务记录") {
                    ForEach(journal.missions(on: day)) { mission in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(mission.title, systemImage: mission.symbol).font(.headline)
                                Spacer()
                                if let record = journal.record(mission, day: day) {
                                    Text(record.isEffective ? "+\(record.effectivePoints) 有效分" : record.isPassed ? "已完成" : record.latest?.outcome == .cancelled ? "已取消" : "未完成")
                                        .font(.caption).foregroundStyle(record.isEffective ? .teal : .secondary)
                                } else { Text("未打卡").font(.caption).foregroundStyle(.secondary) }
                            }
                            if let record = journal.record(mission, day: day) {
                                Text(record.ruleSnapshot).font(.caption).foregroundStyle(.secondary)
                                if mission.usesSegmentedTimer {
                                    Text("本轮累计：\(BeijingCalendar.durationText(record.readingDuration(at: now)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(Array(record.attempts.enumerated()), id: \.element.id) { index, attempt in
                                    VStack(alignment: .leading, spacing: 4) {
                                        if record.attempts.count > 1 {
                                            Text(mission.usesSegmentedTimer ? "第 \(index + 1) 段计时" : "第 \(index + 1) 次尝试")
                                                .fontWeight(.medium)
                                        }
                                        Text("\(attempt.isParentMakeup == true ? "家长补打" : mission.isTimed ? "开始" : "打卡")：\(BeijingCalendar.clockText(attempt.startedAt))")
                                        if mission.isTimed && attempt.isParentMakeup != true {
                                            Text("结束：\(attempt.endedAt.map(BeijingCalendar.clockText) ?? "未结束") · 用时 \(BeijingCalendar.durationText(attempt.duration(at: now)))")
                                        }
                                        if let explanation = attempt.explanation { Text(explanation) }
                                        if let cancelledAt = attempt.cancelledAt {
                                            Text("家长取消：\(BeijingCalendar.clockText(cancelledAt)) · 本次不计分")
                                        }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                                if let confirmed = record.confirmedAt {
                                    Text("历史家长确认：\(BeijingCalendar.clockText(confirmed))").font(.caption).foregroundStyle(.teal)
                                }
                            }
                        }.padding(.vertical, 8)
                    }
                }
                Section("当天奖励") {
                    let rewards = journal.rewards.filter { $0.day == day }
                    if rewards.isEmpty { Text("当天没有周期奖励").foregroundStyle(.secondary) }
                    ForEach(rewards) { reward in
                        HStack {
                            Label(reward.title, systemImage: "gift.fill")
                            Spacer()
                            Text("+\(reward.points) 分").foregroundStyle(SpaceTheme.accent)
                        }
                    }
                }
            }
            .navigationTitle(day).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
