import SwiftUI

struct TodayView: View {
    @Bindable var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showRules = false
    @State private var showJourney = false
    @State private var parentAction: ParentAction?
    @State private var parentDay = ""

    private let columns = [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        scoreCard
                        journeyButton
                    }
                    .padding(.horizontal, 10)
                    if !store.hasHolidayCalendar {
                        Label("未取得本年度节假日安排，暂按周末规则判断起床时间。", systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.secondary).cardSurface()
                    }
                    ForEach(Mission.groups.filter { group in store.missions.contains { $0.group == group } }, id: \.self) { group in
                        missionSection(group)
                    }
                    HStack(spacing: 12) {
                        SpaceArtwork("AstronautWave").frame(width: 48, height: 56)
                        Text("每天一点点，成长看得见")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 8)
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 12)
            }
            .background(SpaceTheme.background)
            .navigationTitle("多多打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showRules = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("计分规则")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openParent(.manage) } label: { Label("家长", systemImage: "lock.shield") }
                        .accessibilityIdentifier("parent.open")
                }
            }
            .sheet(isPresented: $showRules) { RulesView(store: store) }
            .sheet(isPresented: $showJourney) { JourneyView(store: store) }
            .sheet(item: $parentAction) { action in
                ParentGateView(store: store, action: action, day: parentDay)
            }
        }
    }

    private func missionSection(_ group: String) -> some View {
        let color = SpaceTheme.color(forGroup: group)
        let frameContentTop = SpaceTheme.groupFrameContentTop(group)
        return VStack(spacing: 0) {
            GeometryReader { geometry in
                Text(group)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .position(x: geometry.size.width / 2, y: SpaceTheme.groupTitleCenter(group))
            }
            .frame(height: frameContentTop)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.missions.filter { $0.group == group }) { mission in
                    MissionCard(
                        mission: mission, record: store.journal.record(mission, day: store.today),
                        now: store.now, isRestDay: store.isRestDay,
                        unlocked: store.journal.record(mission, day: store.today)?.isPassed == true || !mission.requiresPrerequisites || store.journal.isPromptnessUnlocked(on: store.today),
                        action: { store.tap(mission, day: store.today) },
                        retry: { openParent(.retryHomework) }
                    )
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 22)
            .padding(.bottom, 25)
        }
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(color.opacity(colorScheme == .dark ? 0.12 : 0.10))
                .padding(.top, SpaceTheme.groupTitleCenter(group) + 16)
                .padding(.horizontal, 8).padding(.bottom, 8)
            Image(SpaceTheme.groupFrame(group))
                .resizable(capInsets: EdgeInsets(top: 112, leading: 24, bottom: 24, trailing: 24), resizingMode: .stretch)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .opacity(colorScheme == .dark ? 0.8 : 1)
        }
        .overlay(alignment: .topTrailing) {
            Text(groupProgress(group))
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 64, height: 26)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.85), lineWidth: 1))
                .padding(.trailing, 28)
                .padding(.top, frameContentTop - 28)
                .allowsHitTesting(false)
        }
    }

    private var dateLabel: String {
        let date = BeijingCalendar.calendar.dateComponents([.month, .day], from: store.now)
        return "\(date.month!)月\(date.day!)日 · \(store.isRestDay ? "休息日" : "工作日")"
    }

    private var scoreCard: some View {
        let effective = store.journal.effectiveScore(on: store.today)
        let rewards = store.journal.rewards.filter { $0.day == store.today }.reduce(0) { $0 + $1.points }
        return VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Image("HomeLaunchScene")
                        .resizable(resizingMode: .stretch)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("今天也要\n闪闪发光！")
                            .font(.title2.bold()).foregroundStyle(SpaceTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dateLabel).font(.caption.weight(.medium)).foregroundStyle(SpaceTheme.ink)
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "bolt.fill").foregroundStyle(Color.orange)
                                Text("\(effective)").font(.title2.bold()).contentTransition(.numericText())
                                    .accessibilityIdentifier("today.effective")
                                Text("/ \(store.dailyGoal) 分").font(.subheadline.weight(.semibold))
                            }
                            ProgressView(value: Double(min(effective, store.dailyGoal)), total: Double(store.dailyGoal))
                                .tint(.orange)
                                .accessibilityLabel("每日目标进度")
                                .accessibilityValue("有效分 \(effective)，目标 \(store.dailyGoal) 分")
                            Text(effective >= store.dailyGoal ? "飞船能量已充满！" : "再得\(store.dailyGoal - effective)分，飞船就能出发啦！")
                                .font(.caption2.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .foregroundStyle(SpaceTheme.ink)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(width: geometry.size.width * 0.50, alignment: .leading)
                    .padding(16)
                }
            }
            .frame(height: 232)
            HStack(spacing: 0) {
                scoreLabel("今日打卡分", value: effective)
                scoreLabel("奖励分", value: rewards)
                Divider().frame(height: 32).padding(.trailing, 8)
                Button { openParent(.manage) } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                        }
                        Text("家长管理").font(.caption.weight(.semibold))
                    }
                    .frame(minWidth: 64, minHeight: 44)
                    .foregroundStyle(SpaceTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("parent.confirmToday")
                .accessibilityLabel("家长管理，补打或取消打卡")
            }
            .padding(.horizontal, 8).padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(SpaceTheme.accent.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func scoreLabel(_ title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title3.bold()).contentTransition(.numericText())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var journeyButton: some View {
        let exploration = store.monthlyExploration
        let firstPlanet = min(exploration.unlockedPlanets / 4 * 4, 4)
        let nextThreshold = min(exploration.unlockedPlanets + 1, AppRules.planetNames.count) * exploration.step
        return Button { showJourney = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    SpaceArtwork("PlanetEarth").frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("我的星际旅程").font(.headline).foregroundStyle(.primary)
                        Text("每\(exploration.step)分解锁星球").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("本月").font(.caption2).foregroundStyle(.secondary)
                        Text("\(exploration.points) / \(nextThreshold)").font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(SpaceTheme.accent)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SpaceTheme.accent)
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(firstPlanet..<(firstPlanet + 4), id: \.self) { index in
                        HomePlanetNode(index: index, unlocked: index < exploration.unlockedPlanets)
                    }
                }
                .background(alignment: .top) {
                    HomeOrbitPath().stroke(SpaceTheme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                        .frame(height: 48).padding(.horizontal, 24)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(SpaceTheme.accent.opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journey.open")
    }

    private func groupProgress(_ group: String) -> String {
        let missions = store.missions.filter { $0.group == group }
        let count = missions.filter { store.journal.record($0, day: store.today)?.isPassed == true }.count
        return "\(count) / \(missions.count)"
    }

    private func openParent(_ action: ParentAction) {
        parentDay = store.today
        parentAction = action
    }
}

private struct HomeOrbitPath: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.6))
            path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.6),
                          control1: CGPoint(x: rect.width * 0.35, y: -rect.height * 0.1),
                          control2: CGPoint(x: rect.width * 0.65, y: rect.height * 1.1))
        }
    }
}

private struct HomePlanetNode: View {
    let index: Int
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            SpaceArtwork(SpaceTheme.planetArtwork[index])
                .frame(height: 44)
                .saturation(unlocked ? 1 : 0.6)
                .overlay {
                    if !unlocked {
                        Image(systemName: "lock.fill").font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4).background(SpaceTheme.navy.opacity(0.6), in: Circle())
                    }
                }
            Text(AppRules.planetNames[index]).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            Text(unlocked ? "已点亮" : "未解锁").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct MissionCard: View {
    let mission: Mission
    let record: MissionRecord?
    let now: Date
    let isRestDay: Bool
    let unlocked: Bool
    let action: () -> Void
    let retry: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var outcome: AttemptOutcome? { record?.latest?.outcome }
    private var color: Color { SpaceTheme.color(for: mission) }
    private var completed: Bool { record?.isPassed == true && !running }
    private var showsCompletedAction: Bool { completed && !mission.isAccumulating }
    private var displayedPoints: Int { record?.isPassed == true ? record!.points : mission.points }
    private var running: Bool { outcome == .running }
    private var canRetryHomework: Bool { mission == .homework && mission.isTimed }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 4) {
                Text(mission.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("mission.title.\(mission.rawValue)")
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").foregroundStyle(SpaceTheme.gold)
                    Text("+\(displayedPoints)").foregroundStyle(color)
                        .accessibilityIdentifier("mission.points.\(mission.rawValue)")
                }
                .font(.system(size: 12, weight: .bold))
                .fixedSize()
                .accessibilityLabel("\(displayedPoints)分")
                Spacer(minLength: 0)
            }
            .frame(height: 24, alignment: .leading)
            SpaceArtwork(mission.artworkName)
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .saturation(unlocked ? 1 : 0.25)
                .opacity(unlocked ? 1 : 0.5)
            HStack(spacing: 4) {
                if mission.isTimed {
                    Image(systemName: "timer")
                        .font(.system(size: running ? 20 : 16, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolEffect(.pulse, isActive: running && !reduceMotion)
                        .accessibilityHidden(true)
                }
                Text(detailText)
                    .font(.system(size: running ? 24 : 15, weight: running ? .bold : .medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("mission.detail.\(mission.rawValue)")
            }
            .foregroundStyle(running ? color : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .center)
            .background(running ? color.opacity(colorScheme == .dark ? 0.20 : 0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if running {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.55), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            Button(action: outcome == .failed && canRetryHomework ? retry : action) {
                HStack(spacing: 4) {
                    if showsCompletedAction { Image(systemName: "checkmark.circle.fill") }
                    if !unlocked { Image(systemName: "lock.fill") }
                    Text(buttonTitle)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(showsCompletedAction ? Color.clear : buttonDisabled ? Color(.tertiarySystemFill) : colorScheme == .dark ? color.opacity(0.8) : color, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(showsCompletedAction ? color : buttonDisabled ? Color.secondary : SpaceTheme.ink)
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(MissionActionStyle())
            .disabled(buttonDisabled)
            .accessibilityIdentifier("mission.\(mission.rawValue)")
            .accessibilityLabel("\(mission.title)，\(buttonTitle)")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).fill(color.opacity(completed ? 0.12 : 0.025))
                }
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(completed ? 0.5 : 0.20), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var detailText: String {
        if let record, let attempt = record.latest, attempt.outcome != .cancelled {
            if attempt.isParentMakeup == true { return "家长补打" }
            if mission.isTimed {
                let duration = mission.usesSegmentedTimer ? record.readingDuration(at: now) : attempt.duration(at: now)
                return mission.timerText(duration: duration, isRunning: attempt.outcome == .running)
            }
            if attempt.outcome == .passed {
                return BeijingCalendar.clockText(attempt.endedAt ?? attempt.startedAt)
            }
        }
        if let config = mission.configuration {
            switch config.rule.kind {
            case .none: return unlocked ? "等你来点亮" : "三餐、作业后解锁"
            case .timeWindow:
                let end = isRestDay ? config.rule.restDayEndMinute ?? config.rule.endMinute : config.rule.endMinute
                if config.rule.startMinute == 0 {
                    return String(format: "%d:%02d前", end / 60, end % 60)
                }
                return "\(MissionRuleConfiguration.clock(config.rule.startMinute))–\(MissionRuleConfiguration.clock(end))"
            case .timer:
                return mission.isAccumulating ? "每\(config.rule.minutes)分钟 +\(mission.points)分" : "\(config.rule.comparison == .less && config.rule.includesTimerLimit ? "≤" : config.rule.comparison.rawValue)\(config.rule.minutes)分钟"
            }
        }
        switch mission {
        case .wake: return (record?.isRestDay ?? isRestDay) ? "早上8:30前" : "早上7:30前"
        case .breakfast, .lunch, .dinner: return "30分钟"
        case .homework: return "60分钟"
        case .reading: return "累计>15分钟"
        case .washing: return "晚上9:00"
        case .sleeping: return "晚上9:30"
        case .promptness: return unlocked ? "等你来点亮" : "三餐、作业后解锁"
        default: return "等你来点亮"
        }
    }

    private var buttonTitle: String {
        if !unlocked { return "尚未解锁" }
        switch outcome {
        case .running: return mission.usesSegmentedTimer ? "停止" : "结束"
        case .paused: return "开始"
        case .passed: return mission.isAccumulating ? "开始" : "已完成"
        case .failed: return canRetryHomework ? "家长开启重试" : "未达标"
        case .cancelled: return mission.isTimed ? "开始" : "打卡"
        case nil: return mission.isTimed ? "开始" : "打卡"
        }
    }

    private var buttonDisabled: Bool {
        !unlocked || (outcome == .passed && !mission.isAccumulating) || (outcome == .failed && !canRetryHomework)
    }
}

private struct MissionActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Completed buttons remain disabled, while their explicit status color stays legible.
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview("TodayView") {
    if let persistence = try? JournalPersistence(now: Date(), memoryOnly: true) {
        TodayView(store: AppStore(persistence: persistence))
            .tint(SpaceTheme.accent)
    } else {
        ContentUnavailableView("无法载入预览", systemImage: "exclamationmark.triangle")
    }
}
