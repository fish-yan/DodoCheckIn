import SwiftUI

enum SpaceTheme {
    static let accent = Color("AccentColor")
    static let actionFill = Color(red: 0.404, green: 0.337, blue: 0.824)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.32)
    static let navy = Color(red: 0.10, green: 0.12, blue: 0.29)
    static let mint = Color(red: 0.42, green: 0.90, blue: 0.76)
    static let gold = Color(red: 1, green: 0.79, blue: 0.35)
    static let background = Color(.systemGroupedBackground)
    static let planetArtwork = [
        "PlanetMercury", "PlanetVenus", "PlanetEarth", "PlanetMars",
        "PlanetJupiter", "PlanetSaturn", "PlanetUranus", "PlanetNeptune"
    ]

    static func groupArtwork(_ group: String) -> String {
        switch group {
        case "能量补给站": "MissionPromptness"
        case "知识探索站": "MissionReading"
        case "生活空间站": "MissionToys"
        default: "MissionHonesty"
        }
    }

    static func groupFrame(_ group: String) -> String {
        switch group {
        case "能量补给站": "SectionEnergyFrame"
        case "知识探索站": "SectionKnowledgeFrame"
        case "生活空间站": "SectionLifeFrame"
        default: "SectionCourageFrame"
        }
    }

    static func groupTitleCenter(_ group: String) -> CGFloat {
        switch group {
        case "能量补给站": 52
        case "知识探索站": 64
        case "生活空间站": 60
        default: 72
        }
    }

    /// Inner edge of each 3x frame's top rail; decoration heights differ by asset.
    static func groupFrameContentTop(_ group: String) -> CGFloat {
        switch group {
        case "能量补给站": 74
        case "知识探索站": 86
        case "生活空间站": 82
        default: 98
        }
    }

    static func color(for mission: Mission) -> Color {
        color(forGroup: mission.group)
    }

    static func color(forGroup group: String) -> Color {
        switch group {
        case "能量补给站": Color("MissionEnergyAction")
        case "知识探索站": Color("MissionKnowledgeAction")
        case "生活空间站": Color("MissionLifeAction")
        default: Color("MissionCourageAction")
        }
    }
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}

struct StarsView: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<32 {
                let x = Double((index * 73 + 17) % 317) / 317 * size.width
                let y = Double((index * 43 + 11) % 197) / 197 * size.height
                let radius = index.isMultiple(of: 5) ? 2.0 : 1.0
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.3)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Decorative artwork keeps task names, status and actions in native accessible text.
struct SpaceArtwork: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct RocketView: View {
    var body: some View {
        SpaceArtwork("SpaceRocket").frame(width: 110, height: 140)
    }
}

struct PlanetView: View {
    var index: Int
    var unlocked: Bool

    var body: some View {
        SpaceArtwork(SpaceTheme.planetArtwork[index])
            .saturation(unlocked ? 1 : 0.15)
            .opacity(unlocked ? 1 : 0.55)
            .frame(width: 72, height: 64)
            .overlay(alignment: .bottomTrailing) {
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                }
            }
            .accessibilityHidden(true)
    }
}

struct CelebrationView: View {
    let celebration: Celebration
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { celebrationCard }
            } else {
                celebrationCard
            }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.35)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private var celebrationCard: some View {
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(SpaceTheme.accent.opacity(0.15)).frame(width: 160, height: 160)
                    ForEach(0..<8) { index in
                        Image(systemName: "sparkle")
                            .foregroundStyle(index.isMultiple(of: 2) ? SpaceTheme.gold : SpaceTheme.mint)
                            .offset(y: appeared ? -88 : -48)
                            .rotationEffect(.degrees(Double(index) * 45))
                    }
                    SpaceArtwork(celebration.isReward ? "RewardTreasure" : "CelebrationPanda")
                        .frame(width: 180, height: 180)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.7)
                }
                Text(celebration.title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(celebration.subtitle).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(action: dismiss) {
                    Text("继续探索")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            SpaceTheme.actionFill,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(.white)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("celebration.dismiss")
            }
            .padding(32)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
    }
}


extension Mission {
    var artworkName: String {
        let icon = configuration?.iconID ?? rawValue
        return "Mission" + icon.prefix(1).uppercased() + icon.dropFirst()
    }
}
