import Foundation

enum AppRules {
    // 家长密码只在这里修改；不使用 Keychain 或密码设置流程。
    static let parentPassword = "885802"
    static let dailyGoal = 13
    static var dailyMaximum: Int { Mission.allCases.reduce(0) { $0 + $1.points } }
    static let pointsPerPlanet = 50
    static let planetNames = ["水星", "金星", "地球", "火星", "木星", "土星", "天王星", "海王星"]
}

struct Mission: RawRepresentable, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    let rawValue: String
    var configuration: MissionConfiguration?

    init(rawValue: String) { self.rawValue = rawValue }
    init(configuration: MissionConfiguration) {
        rawValue = configuration.id
        self.configuration = configuration
    }
    static func == (lhs: Mission, rhs: Mission) -> Bool { lhs.rawValue == rhs.rawValue }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    private enum CodingKeys: String, CodingKey { case rawValue, configuration }
    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            rawValue = value
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rawValue = try container.decode(String.self, forKey: .rawValue)
            configuration = try container.decodeIfPresent(MissionConfiguration.self, forKey: .configuration)
        }
    }
    func encode(to encoder: Encoder) throws {
        if let configuration {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rawValue, forKey: .rawValue)
            try container.encode(configuration, forKey: .configuration)
        } else {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    static let wake = Mission(rawValue: "wake")
    static let breakfast = Mission(rawValue: "breakfast")
    static let lunch = Mission(rawValue: "lunch")
    static let dinner = Mission(rawValue: "dinner")
    static let sleeping = Mission(rawValue: "sleeping")
    static let listening = Mission(rawValue: "listening")
    static let homework = Mission(rawValue: "homework")
    static let reading = Mission(rawValue: "reading")
    static let toys = Mission(rawValue: "toys")
    static let cleaning = Mission(rawValue: "cleaning")
    static let washing = Mission(rawValue: "washing")
    static let hygiene = Mission(rawValue: "hygiene")
    static let dressing = Mission(rawValue: "dressing")
    static let kindness = Mission(rawValue: "kindness")
    static let calmness = Mission(rawValue: "calmness")
    static let promptness = Mission(rawValue: "promptness")
    static let honesty = Mission(rawValue: "honesty")
    static let allCases: [Mission] = [.wake, .breakfast, .lunch, .dinner, .sleeping, .listening, .homework, .reading, .toys, .cleaning, .washing, .hygiene, .dressing, .kindness, .calmness, .promptness, .honesty]
    // An icon option only, not an additional default check-in task.
    static let genericIcon = Mission(rawValue: "generic")
    static var selectableIcons: [Mission] { [.genericIcon] + allCases }

    var id: String { rawValue }

    var title: String {
        if let configuration { return configuration.name }
        return switch self {
        case .genericIcon: "通用图标"
        case .wake: "起床"
        case .breakfast: "吃早饭"
        case .lunch: "吃午饭"
        case .dinner: "吃晚饭"
        case .listening: "认真听讲"
        case .homework: "写作业"
        case .toys: "收拾玩具"
        case .cleaning: "打扫卫生"
        case .washing: "洗漱"
        case .reading: "阅读"
        case .sleeping: "睡觉"
        case .kindness: "乖巧听话"
        case .calmness: "不发脾气"
        case .promptness: "做事不拖拉"
        case .honesty: "诚实守信"
        case .hygiene: "干净卫生"
        case .dressing: "自己穿衣"
        default: "自定义项目"
        }
    }

    var symbol: String {
        if let configuration { return Mission(rawValue: configuration.iconID).symbol }
        return switch self {
        case .wake: "sun.max.fill"
        case .breakfast: "cup.and.saucer.fill"
        case .lunch: "fork.knife"
        case .dinner: "carrot.fill"
        case .listening: "ear.badge.waveform"
        case .homework: "pencil.and.outline"
        case .toys: "teddybear.fill"
        case .cleaning: "sparkles"
        case .washing: "drop.fill"
        case .reading: "book.fill"
        case .sleeping: "moon.zzz.fill"
        case .kindness: "heart.fill"
        case .calmness: "leaf.fill"
        case .promptness: "bolt.fill"
        case .honesty: "checkmark.shield.fill"
        case .hygiene: "hands.sparkles.fill"
        case .dressing: "tshirt.fill"
        default: "star.fill"
        }
    }

    var points: Int {
        if let configuration { return configuration.points }
        return switch self {
        case .listening, .homework, .reading, .kindness, .calmness, .promptness: 2
        default: 1
        }
    }

    var isTimed: Bool {
        if let configuration { return configuration.rule.kind == .timer }
        return [.breakfast, .lunch, .dinner, .homework, .reading].contains(self)
    }

    var maximumDuration: TimeInterval? {
        if let configuration { return configuration.rule.maximumDuration }
        return switch self {
        case .breakfast, .lunch, .dinner: 30 * 60
        case .homework: 60 * 60
        default: nil
        }
    }

    func timerText(duration: TimeInterval, isRunning: Bool) -> String {
        let elapsed = BeijingCalendar.durationText(duration)
        guard !isRunning else { return elapsed }
        if let configuration { return "\(elapsed)/\(configuration.rule.comparison.rawValue)\(configuration.rule.minutes)" }
        let target = self == .reading ? ">15" : "\(Int((maximumDuration ?? 0) / 60))"
        return "\(elapsed)/\(target)"
    }

    var ruleDescription: String {
        if let configuration { return configuration.rule.description(points: configuration.points) }
        return switch self {
        case .wake: "工作日 7:30 前 · 休息日 8:30 前"
        case .breakfast, .lunch, .dinner: "开始 → 完成 · 30 分钟内"
        case .homework: "开始 → 完成 · 60 分钟内"
        case .reading: "可分段阅读 · 当日累计超过 15 分钟后停止即完成"
        case .washing: "晚上 9:00 前或整点完成"
        case .sleeping: "晚上 9:30 前或整点完成"
        case .promptness: "三餐和作业全部达标后解锁"
        default: "完成后点亮这颗小星星"
        }
    }

    var group: String {
        if let configuration { return configuration.group }
        return switch self {
        case .wake, .breakfast, .lunch, .dinner, .sleeping: "能量补给站"
        case .listening, .homework, .reading: "知识探索站"
        case .toys, .cleaning, .washing, .hygiene, .dressing: "生活空间站"
        case .kindness, .calmness, .promptness, .honesty: "勇气成长站"
        default: "勇气成长站"
        }
    }

    var isAccumulating: Bool { configuration?.rule.kind == .timer && configuration?.rule.comparison == .greater }
    var usesSegmentedTimer: Bool { isAccumulating || (configuration == nil && self == .reading) }
    var requiresPrerequisites: Bool { configuration?.rule.requiresPrerequisites ?? (self == .promptness) }

    static let groups = ["能量补给站", "知识探索站", "生活空间站", "勇气成长站"]
    static let prerequisites: [Mission] = [.breakfast, .lunch, .dinner, .homework]
}
