import SwiftUI

struct ParentGateView: View {
    let store: AppStore
    let action: ParentAction
    let day: String
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String?
    @State private var submitting = false
    @State private var decisions: [Mission: ReviewDecision] = [:]
    @FocusState private var passwordFocused: Bool

    private var reviewable: [Mission] { store.journal.missions(on: day) }

    private var reviewDecisions: [Mission: ReviewDecision] {
        Dictionary(uniqueKeysWithValues: reviewable.map { ($0, decisions[$0] ?? .unchanged) })
    }

    private var selectionCount: Int {
        reviewDecisions.values.filter { $0 != .unchanged }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(SpaceTheme.accent)
                        Text(action == .manage ? "家长补打与纠错" : "重新开始作业任务").font(.title2.bold())
                        Text(action == .manage ? "正常打卡立即得分，无需审核。\n漏打或未达标时可补打，也可取消误打。" : "之前的超时记录会保留。\n验证后立即重新计时，作业最多计一次分。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)

                    if day != store.today {
                        Label("日期已变化，这一天的记录已封存。", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else if action == .manage {
                        if reviewable.isEmpty {
                            ContentUnavailableView("没有可管理的任务", systemImage: "checkmark.seal", description: Text("请先在设置中添加打卡项目。"))
                        } else {
                            VStack(spacing: 12) {
                                ForEach(reviewable) { mission in
                                    reviewRow(mission)
                                    Divider()
                                }
                                HStack {
                                    Text("本次处理")
                                    Spacer()
                                    Text("\(selectionCount) 项").bold()
                                }
                                Text("取消三餐或作业时，已完成的“做事不拖拉”也会取消。取消会同步更新分数及达标奖励；重新打卡仍需符合原时间要求。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.cardSurface()
                        }
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if day == store.today && (action == .retryHomework || !reviewable.isEmpty) {
                    VStack(spacing: 12) {
                        passwordInput
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("parent.error")
                        }
                        Button(action == .manage ? "提交修改（\(selectionCount) 项）" : "验证并重新计时") { submit() }
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                            .background(SpaceTheme.actionFill, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                            .disabled(password.count != 6 || submitting || (action == .manage && selectionCount == 0))
                            .opacity(password.count == 6 && (action == .retryHomework || selectionCount > 0) ? 1 : 0.5)
                            .accessibilityIdentifier("parent.submit")
                    }
                    .padding(16)
                    .background(.regularMaterial)
                }
            }
            .background(SpaceTheme.background)
            .navigationTitle("家长管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private var passwordInput: some View {
        SecureField("请输入 6 位家长密码", text: $password)
            .focused($passwordFocused)
            .keyboardType(.numberPad)
            .textContentType(.password)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("家长密码")
            .accessibilityIdentifier("parent.password")
            .onChange(of: password) { _, value in
                password = String(value.filter(\.isNumber).prefix(6))
                if !value.isEmpty { error = nil }
                if password.count == 6 { passwordFocused = false }
            }
    }

    private func reviewRow(_ mission: Mission) -> some View {
        let record = store.journal.record(mission, day: day)
        return VStack(alignment: .leading, spacing: 8) {
            Label(mission.title, systemImage: mission.symbol).font(.headline)
            if let record {
                Text(record.isEffective ? "已得 \(record.effectivePoints) 分" : record.latest?.outcome == .running ? "计时中" : record.latest?.outcome == .paused ? "已暂停" : record.latest?.outcome == .cancelled ? "已取消" : "未达标")
                    .font(.caption).foregroundStyle(.secondary)
                if mission.usesSegmentedTimer {
                    Text("本轮累计：\(BeijingCalendar.durationText(record.readingDuration(at: store.now)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let attempt = record.latest {
                    Text("\(attempt.isParentMakeup == true ? "家长补打" : "记录时间")：\(BeijingCalendar.clockText(attempt.startedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("未打卡").font(.caption).foregroundStyle(.secondary) }
            Text("补打按原规则分值记分；累计计时至少补记一个单位，不重复加分。")
                .font(.caption2).foregroundStyle(.secondary)
            Picker("\(mission.title)管理", selection: Binding(
                get: { reviewDecisions[mission] ?? .unchanged },
                set: { decisions[mission] = $0 }
            )) {
                Text(ReviewDecision.unchanged.title).tag(ReviewDecision.unchanged)
                if record?.isPassed != true || record?.latest?.outcome == .running {
                    Text(ReviewDecision.makeup.title).tag(ReviewDecision.makeup)
                }
                if record != nil && record?.latest?.outcome != .cancelled {
                    Text(ReviewDecision.cancel.title).tag(ReviewDecision.cancel)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("review.\(mission.rawValue)")
        }.padding(.vertical, 4)
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        defer { submitting = false }
        do {
            try store.authenticate(action, password: password, day: day, decisions: reviewDecisions)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            password = ""
        }
    }
}

struct RulesView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("每天的小目标") {
                    Text("打卡得分达到 \(store.dailyGoal) 分，今天就达标啦。累计计时任务每满设定分钟数可继续得分；奖励分不参与每日达标判断。")
                }
                Section("任务与分值") {
                    ForEach(store.missions) { mission in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: mission.symbol).foregroundStyle(SpaceTheme.color(for: mission)).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mission.title).font(.headline)
                                Text(mission.ruleDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(mission.points) 分").font(.subheadline.bold())
                        }.padding(.vertical, 4)
                    }
                }
                Section("探索奖励") {
                    Text("自然周达标 \(store.journal.weeklyReward(on: store.today)?.days ?? 7) 天，奖励 \(store.journal.weeklyReward(on: store.today)?.points ?? 10) 分。")
                    if let monthly = store.journal.monthlyReward(on: store.today) {
                        Text("自然月累计达标\(monthly.days)天（不足该天数的月份按全月），奖励\(monthly.points)分。周月奖励可叠加。")
                    } else { Text("本月沿用原规则：累计25天奖励50分，全月达标合计100分。") }
                    Text("每月有效打卡分与奖励分每满 \(store.monthlyExploration.step) 分解锁一颗星球，共 8 颗。每月开启新旅程，历史积分保留。")
                }
                Section("打卡小约定") {
                    Text("单次任务记录打卡时间；计时任务需要开始、完成两次操作，整体算一次打卡。未达标不计次数和分数。")
                    Text("累计计时任务可多次开始与停止，暂停不累计时间。每满n分钟记m分，不足部分不计分；新增分数立即生效。取消后本轮累计清零，旧记录保留。作业超时可由家长验证后重试。")
                    Text("家长可为当天漏打或未达标的项目补打，或取消误打，输入密码提交。补打会标注操作时间，不伪造实际完成时间。取消会移除对应分数，并撤回不再满足条件的奖励；已完成项目也可取消。取消三餐或作业还会取消已完成的“做事不拖拉”。北京时间午夜后记录只读。")
                    Text("节假日和调休补班自动读取年度安排。无该年度数据时明确提示，并暂按周末规则判定；已有记录不会被新日历改写。")
                }
            }
            .navigationTitle("计分规则").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct JourneyView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var exploration: MonthlyExploration { store.monthlyExploration }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    RocketView()
                    Text("每一颗星球，都是你的进步").font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(exploration.month) · 本月 \(exploration.points) 分")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("每月新旅程 · 每\(exploration.step)分解锁一颗星球")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(AppRules.planetNames.enumerated()), id: \.offset) { index, name in
                        HStack(spacing: 16) {
                            PlanetView(index: index, unlocked: index < exploration.unlockedPlanets)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.headline)
                                Text("本月 \((index + 1) * store.monthlyExploration.step) 分解锁").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: index < exploration.unlockedPlanets ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(index < exploration.unlockedPlanets ? SpaceTheme.accent : Color.secondary)
                        }.cardSurface()
                    }
                    if exploration.unlockedPlanets == AppRules.planetNames.count { Text("本月太阳系探索完成！继续记录你的每一点成长。").font(.headline) }
                }.padding(20)
            }
            .background(SpaceTheme.background)
            .navigationTitle("我的星际旅程").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
