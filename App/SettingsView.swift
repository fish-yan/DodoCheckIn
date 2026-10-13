import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case missions = "打卡配置", rewards = "奖励机制"
    var id: String { rawValue }
    var symbol: String { self == .missions ? "checklist" : "gift" }
}

private struct SettingsRoute: Hashable {
    var page: SettingsPage
    var password: String
}

struct SettingsView: View {
    let store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [SettingsRoute] = []
    @State private var requestedPage: SettingsPage?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(SettingsPage.allCases) { page in
                        Button {
                            requestedPage = page
                        } label: {
                            HStack {
                                Label(page.rawValue, systemImage: page.symbol)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.foregroundStyle(.primary).padding(.vertical, 6)
                        }
                        .accessibilityIdentifier(page == .missions ? "settings.missions" : "settings.rewards")
                    }
                } footer: {
                    Text("请家长验证密码后修改。保存后立即生效，已有打卡记录和已发放奖励保留。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route.page {
                case .missions: MissionConfigurationList(store: store, password: route.password)
                case .rewards: RewardConfigurationView(store: store, password: route.password)
                }
            }
            .sheet(item: $requestedPage) { page in
                SettingsPasswordView { password in
                    requestedPage = nil
                    path.append(SettingsRoute(page: page, password: password))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    path = []
                    requestedPage = nil
                }
            }
        }
    }
}

private struct SettingsPasswordView: View {
    let onVerified: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("家长验证") {
                    SecureField("请输入6位家长密码", text: $password)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("settings.password")
                    if showError { Text("家长密码不正确").foregroundStyle(.red) }
                    Button("验证并进入") {
                        if password == AppRules.parentPassword { onVerified(password) }
                        else { showError = true; password = "" }
                    }
                    .disabled(password.count != 6)
                    .accessibilityIdentifier("settings.unlock")
                }
            }
            .navigationTitle("家长验证").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct MissionConfigurationList: View {
    let store: AppStore
    let password: String
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Label("勾选后显示在首页，左滑可删除项目", systemImage: "checklist")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("隐藏或删除不影响已有记录和积分。").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Mission.groups, id: \.self) { group in
                Section(group) {
                    ForEach(store.editableMissions.filter { $0.group == group }) { configuration in
                        HStack(spacing: 8) {
                            Button {
                                do {
                                    try store.setMissionEnabled(configuration.id, enabled: !configuration.isEnabled, password: password)
                                } catch { self.error = error.localizedDescription }
                            } label: {
                                Image(systemName: configuration.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(configuration.name)，首页显示")
                            .accessibilityValue(configuration.isEnabled ? "已勾选" : "未勾选")
                            .accessibilityIdentifier("settings.enabled.\(configuration.id)")
                            NavigationLink {
                                MissionConfigurationEditor(store: store, password: password, configuration: configuration)
                            } label: {
                                HStack(spacing: 12) {
                                    SpaceArtwork(Mission(configuration: configuration).artworkName).frame(width: 40, height: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(configuration.name)
                                        Text(configuration.rule.description(points: configuration.points))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Text("\(configuration.points)分").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("settings.edit.\(configuration.id)")
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                do { try store.deleteMission(configuration.id, password: password) }
                                catch { self.error = error.localizedDescription }
                            }
                            .accessibilityIdentifier("settings.delete.\(configuration.id)")
                        }
                    }
                }
            }
        }
        .navigationTitle("打卡配置").navigationBarTitleDisplayMode(.inline)
        .alert("无法更新配置", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    MissionConfigurationEditor(store: store, password: password, configuration: MissionConfiguration(
                        id: "custom-" + UUID().uuidString.lowercased(), name: "", iconID: Mission.genericIcon.rawValue,
                        group: Mission.groups[0], rule: MissionRuleConfiguration(), points: 1))
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("新增打卡项目")
                .accessibilityIdentifier("settings.addMission")
            }
        }
    }
}

private struct MissionConfigurationEditor: View {
    let store: AppStore
    let password: String
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: MissionConfiguration
    @State private var points: String
    @State private var minutes: String
    @State private var error: String?

    init(store: AppStore, password: String, configuration: MissionConfiguration) {
        self.store = store
        self.password = password
        _configuration = State(initialValue: configuration)
        _points = State(initialValue: String(configuration.points))
        _minutes = State(initialValue: String(configuration.rule.minutes))
    }

    var body: some View {
        Form {
            Section("项目") {
                TextField("项目名称", text: $configuration.name).accessibilityIdentifier("settings.mission.name")
                NavigationLink {
                    MissionIconPicker(selection: $configuration.iconID)
                } label: {
                    HStack {
                        Text("图标")
                        Spacer()
                        SpaceArtwork(Mission(rawValue: configuration.iconID).artworkName).frame(width: 40, height: 40)
                        Text(Mission(rawValue: configuration.iconID).title).foregroundStyle(.secondary)
                    }
                }
                Picker("所属分组", selection: $configuration.group) {
                    ForEach(Mission.groups, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("规则") {
                Picker("规则类型", selection: $configuration.rule.kind) {
                    ForEach(MissionRuleKind.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("settings.mission.rule")
                if configuration.rule.kind == .timeWindow {
                    DatePicker("起始时间", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("结束时间", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    Toggle("包含结束时刻", isOn: $configuration.rule.includesEnd)
                    Toggle("休息日使用不同结束时间", isOn: Binding(
                        get: { configuration.rule.restDayEndMinute != nil },
                        set: { configuration.rule.restDayEndMinute = $0 ? configuration.rule.endMinute : nil }
                    ))
                    if configuration.rule.restDayEndMinute != nil {
                        DatePicker("休息日结束时间", selection: Binding(
                            get: { date(for: configuration.rule.restDayEndMinute!) },
                            set: { configuration.rule.restDayEndMinute = minute(of: $0) }
                        ), displayedComponents: .hourAndMinute)
                    }
                    Text("按北京时间判断，同一天内的区间，不跨午夜。").font(.caption).foregroundStyle(.secondary)
                } else if configuration.rule.kind == .timer {
                    Picker("比较方式", selection: $configuration.rule.comparison) {
                        ForEach(TimerComparison.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    TextField("计时分钟数", text: $minutes).keyboardType(.numberPad)
                        .accessibilityIdentifier("settings.mission.minutes")
                    if configuration.rule.comparison == .greater {
                        Text("每满设定分钟数记一次分，不足部分向下取整。当天可多次开始、停止，暂停不累计；新增积分立即生效。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if configuration.rule.comparison == .equal {
                        Text("按完整分钟判断，例如=30分钟可在30:00～30:59结束。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle("包含上限整点（≤）", isOn: $configuration.rule.includesTimerLimit)
                    }
                }
                if configuration.id == Mission.promptness.rawValue {
                    Toggle("三餐和作业达标后解锁", isOn: $configuration.rule.requiresPrerequisites)
                }
            }
            Section("记分") {
                TextField("正整数分值", text: $points).keyboardType(.numberPad)
                    .accessibilityIdentifier("settings.mission.points")
                Text(configuration.rule.kind == .timer && configuration.rule.comparison == .greater
                     ? "累计计分 = 完整计时分钟数 ÷ 设定分钟数（向下取整）× 分值。"
                     : "符合规则完成一次后获得该分值，立即计入有效分。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("保存后立即用于新增项目和今天尚无记录的项目。今天已有记录的项目继续沿用原规则，次日使用新配置。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Button("保存配置", action: save).accessibilityIdentifier("settings.mission.save")
            }
        }
        .environment(\.calendar, BeijingCalendar.calendar)
        .environment(\.timeZone, BeijingCalendar.calendar.timeZone)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(configuration.name.isEmpty ? "新增打卡项目" : "编辑打卡项目")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeBinding(_ keyPath: WritableKeyPath<MissionRuleConfiguration, Int>) -> Binding<Date> {
        Binding(get: { date(for: configuration.rule[keyPath: keyPath]) },
                set: { configuration.rule[keyPath: keyPath] = minute(of: $0) })
    }
    private func date(for minute: Int) -> Date { BeijingCalendar.time(on: "2001-01-01", hour: minute / 60, minute: minute % 60) }
    private func minute(of date: Date) -> Int {
        BeijingCalendar.calendar.component(.hour, from: date) * 60 + BeijingCalendar.calendar.component(.minute, from: date)
    }
    private func save() {
        do {
            guard let value = Int(points), let duration = Int(minutes) else { throw ConfigurationError.invalidMission }
            configuration.points = value
            configuration.rule.minutes = duration
            try store.saveMission(configuration, password: password)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct MissionIconPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(Mission.selectableIcons) { mission in
                    Button {
                        selection = mission.rawValue
                        dismiss()
                    } label: {
                        VStack(spacing: 8) {
                            SpaceArtwork(mission.artworkName).frame(height: 64)
                            Text(mission.title).font(.caption)
                            Image(systemName: selection == mission.rawValue ? "checkmark.circle.fill" : "circle")
                        }
                        .frame(maxWidth: .infinity).padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.icon.\(mission.rawValue)")
                }
            }.padding(16)
        }
        .background(SpaceTheme.background)
        .navigationTitle("选择图标").navigationBarTitleDisplayMode(.inline)
    }
}

private struct RewardConfigurationView: View {
    let store: AppStore
    let password: String
    @Environment(\.dismiss) private var dismiss
    @State private var dailyGoal: String
    @State private var weekDays: String
    @State private var weekPoints: String
    @State private var monthDays: String
    @State private var monthPoints: String
    @State private var planetStep: String
    @State private var error: String?

    init(store: AppStore, password: String) {
        self.store = store
        self.password = password
        let schedule = store.journal.configuration
        let goal = schedule.flatMap { ConfigurationEngine.editableValue(in: $0.dailyGoals) } ?? AppRules.dailyGoal
        let week = schedule.flatMap { ConfigurationEngine.editableValue(in: $0.weeks) } ?? WeeklyRewardConfiguration()
        let month = schedule.flatMap { ConfigurationEngine.editableValue(in: $0.months) } ?? MonthlyRewardConfiguration()
        _dailyGoal = State(initialValue: String(goal))
        _weekDays = State(initialValue: String(week.days))
        _weekPoints = State(initialValue: String(week.points))
        _monthDays = State(initialValue: String(month.days))
        _monthPoints = State(initialValue: String(month.points))
        _planetStep = State(initialValue: String(month.planetStep))
    }

    var body: some View {
        Form {
            Section {
                numberRow("日达标分数", value: $dailyGoal, id: "dailyGoal")
            } header: { Text("每日目标") } footer: { Text("保存后立即更新今日目标，仅有效打卡分参与达标。历史日期的目标不变。") }
            Section {
                numberRow("周达标天数", value: $weekDays, id: "weekDays")
                numberRow("周奖励分数", value: $weekPoints, id: "weekPoints")
            } header: { Text("自然周奖励") } footer: { Text("保存后立即生效，已发放的奖励不重算。周一至周日累计1～7天，不要求连续。") }
            Section {
                numberRow("月达标天数", value: $monthDays, id: "monthDays")
                numberRow("月奖励分数", value: $monthPoints, id: "monthPoints")
                numberRow("星球解锁步长", value: $planetStep, id: "planetStep")
            } header: { Text("自然月奖励与星际旅程") } footer: {
                Text("保存后立即生效，已发放的奖励不重算。每月只发放一次达标奖励。可设1～31天，若超过当月天数则按全月达标。每满设定步长的月度积分解锁一颗星球。")
            }
            Section {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Button("保存奖励机制", action: save).accessibilityIdentifier("settings.rewards.save")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("奖励机制").navigationBarTitleDisplayMode(.inline)
    }

    private func numberRow(_ title: String, value: Binding<String>, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: value).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
                .accessibilityIdentifier("settings.reward.\(id)")
        }
    }
    private func save() {
        do {
            guard let goal = Int(dailyGoal), let days = Int(weekDays), let points = Int(weekPoints),
                  let monthlyDays = Int(monthDays), let monthlyPoints = Int(monthPoints), let step = Int(planetStep) else {
                throw ConfigurationError.invalidRewards
            }
            try store.saveRewards(dailyGoal: goal, week: WeeklyRewardConfiguration(days: days, points: points),
                                  month: MonthlyRewardConfiguration(days: monthlyDays, points: monthlyPoints, planetStep: step), password: password)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
