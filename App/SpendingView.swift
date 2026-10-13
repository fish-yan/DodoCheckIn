import SwiftUI

struct SpendingView: View {
    let store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showManualExpense = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("把努力，换成小快乐").font(.title2.bold())
                        Text("赚到的每一分，都留在成长记录里")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    balanceCard
                    cartoonCard
                    Button { showManualExpense = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(SpaceTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("添加消耗项目").font(.headline).foregroundStyle(.primary)
                                Text("填写名称和消耗积分").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.cardSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("spending.manual.open")
                    history
                }.padding(20)
            }
            .background(SpaceTheme.background)
            .navigationTitle("积分消耗")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showManualExpense) { ManualExpenseView(store: store) }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("剩余积分").font(.subheadline)
                    Text("\(store.remainingPoints) 分")
                        .font(.largeTitle.bold()).contentTransition(.numericText())
                        .accessibilityIdentifier("spending.balance")
                }
                Spacer(minLength: 8)
                if !dynamicTypeSize.isAccessibilitySize {
                    SpaceArtwork("RewardTreasure").frame(width: 64, height: 72)
                }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 24))
            layout {
                balanceMetric("累计总分", value: store.journal.totalPoints, id: "spending.earned")
                balanceMetric("已消耗积分", value: store.spentPoints, id: "spending.spent")
            }
            Text("总分 = 有效打卡分 + 奖励分；消耗不扣减成长得分。")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
            if store.remainingPoints < 0 {
                Text("当前积分已透支，后续打卡得分会抵扣缺口。仍可继续记录消耗。")
                    .font(.caption).foregroundStyle(SpaceTheme.gold)
            }
        }
        .padding(20).foregroundStyle(.white)
        .background { SpaceTheme.navy.overlay { StarsView() } }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func balanceMetric(_ title: String, value: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value) 分").font(.title2.bold()).contentTransition(.numericText())
                .accessibilityIdentifier(id)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
    }

    private var cartoonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("看动画片", systemImage: "play.tv.fill").font(.headline)
            Text("每满 2 分钟消耗 1 分，不足 2 分钟不计分。每次观看单独计算。")
                .font(.subheadline).foregroundStyle(.secondary)
            if let session = store.journal.spendingLedger.activeCartoon {
                VStack(alignment: .leading, spacing: 8) {
                    Text(BeijingCalendar.durationText(session.duration(at: store.now)))
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(SpaceTheme.accent)
                        .accessibilityIdentifier("spending.cartoon.timer")
                        .accessibilityLabel("本次观看时长")
                        .accessibilityValue(BeijingCalendar.durationText(session.duration(at: store.now)))
                    Text("本次已消耗 \(session.points(at: store.now)) 分")
                        .font(.headline).accessibilityIdentifier("spending.cartoon.points")
                    Text("开始于 \(SpendingText.dateTime(session.startedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { store.stopCartoon(id: session.id) } label: {
                    Label("结束观看", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(SpaceTheme.actionFill)
                .accessibilityIdentifier("spending.cartoon.stop")
            } else {
                Button { store.startCartoon() } label: {
                    Label("开始看动画片", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(SpaceTheme.actionFill)
                .accessibilityIdentifier("spending.cartoon.start")

            }
        }.cardSurface()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("消耗记录").font(.headline)
            if let session = store.journal.spendingLedger.activeCartoon {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "play.tv.fill").foregroundStyle(SpaceTheme.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("看动画片 · 观看中").font(.headline)
                        Text(SpendingText.dateTime(session.startedAt)).font(.caption).foregroundStyle(.secondary)
                        Text("已观看 \(SpendingText.duration(session.duration(at: store.now))) · 已消耗 \(session.points(at: store.now)) 分")
                            .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }.cardSurface()
            }
            if store.journal.spendingLedger.records.isEmpty && store.journal.spendingLedger.activeCartoon == nil {
                HStack(spacing: 16) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        SpaceArtwork("EmptyExplorer").frame(width: 72, height: 80)
                    }
                    Text("还没有消耗记录\n每一份小快乐，都值得记录。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.cardSurface()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(records) { expense in
                        ExpenseRow(expense: expense)
                    }
                }
            }
        }
    }

    private var records: [PointExpense] {
        // Reverse first to keep the newest insertion first when timestamps are identical.
        store.journal.spendingLedger.records.reversed().sorted { $0.endedAt > $1.endedAt }
    }
}

private struct ExpenseRow: View {
    let expense: PointExpense

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(expense.name, systemImage: expense.kind == .cartoon ? "play.tv.fill" : "star.circle.fill")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("消耗 \(expense.points) 分").font(.headline).foregroundStyle(SpaceTheme.accent)
            Text(SpendingText.dateTime(expense.endedAt)).font(.caption).foregroundStyle(.secondary)
            if expense.kind == .cartoon {
                Text("观看时长：\(SpendingText.duration(expense.duration))").font(.subheadline)
                Text("开始：\(SpendingText.dateTime(expense.startedAt))")
                    .font(.caption).foregroundStyle(.secondary)
                if expense.endReason == .balanceExhausted {
                    Label("积分用完，自动结束计时", systemImage: "stop.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("expense.\(expense.id.uuidString)")
    }
}

private struct ManualExpenseView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var requestID = UUID()
    @State private var name = ""
    @State private var pointsText = ""
    @State private var error: String?
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            Form {
                Section("消耗项目") {
                    TextField("例如：买贴纸", text: $name)
                        .accessibilityLabel("项目名称").accessibilityIdentifier("spending.manual.name")
                    TextField("请输入正整数", text: $pointsText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("消耗积分").accessibilityIdentifier("spending.manual.points")
                }
                Section {
                    Text("当前剩余 \(store.remainingPoints) 分")
                    Text("提交后记录当前日期和时间，不影响已获得的成长得分。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("spending.manual.error")
                    }
                }
            }
            .navigationTitle("添加消耗项目").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记录") { submit() }
                        .disabled(submitted || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pointsText.isEmpty)
                        .accessibilityIdentifier("spending.manual.submit")
                }
            }
        }
    }

    private func submit() {
        guard !submitted else { return }
        guard let points = Int(pointsText), points > 0 else {
            error = SpendingError.invalidPoints.localizedDescription
            return
        }
        do {
            try store.addManualExpense(id: requestID, name: name, points: points)
            submitted = true
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private enum SpendingText {
    static func dateTime(_ date: Date) -> String {
        "\(BeijingCalendar.key(date)) \(BeijingCalendar.clockText(date))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return "\(total / 60) 分 \(total % 60) 秒"
    }
}
