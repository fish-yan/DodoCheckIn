import SwiftUI
import Combine

@main
struct DodoCheckInApp: App {
    @State private var store: AppStore?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    RootView(store: store)
                } else if let startupError {
                    ContentUnavailableView {
                        Label("暂时无法打开记录", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(startupError)
                    } actions: {
                        Button("重新打开") { start() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("飞船准备中…")
                }
            }
            .task { if store == nil { start() } }
            .tint(SpaceTheme.accent)
        }
    }

    private func start() {
        do {
            #if DEBUG
            let memoryOnly = ProcessInfo.processInfo.arguments.contains("--uitesting")
            #else
            let memoryOnly = false
            #endif
            store = AppStore(persistence: try JournalPersistence(now: Date(), memoryOnly: memoryOnly))
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}

struct RootView: View {
    @Bindable var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            TodayView(store: store)
                .tabItem { Label("今日打卡", systemImage: "sparkles") }
            StatisticsView(store: store)
                .tabItem { Label("打卡统计", systemImage: "chart.bar.xaxis") }
            SpendingView(store: store)
                .tabItem { Label("积分消耗", systemImage: "star.circle") }
            SettingsView(store: store)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .fontDesign(.rounded)
        .onReceive(timer) { date in
            if scenePhase == .active { store.refresh(at: date) }
        }
        .task { await store.updateHolidays() }
        .task(id: scenePhase) {
            if scenePhase == .active {
                store.refresh()
                await store.updateHolidays()
            }
        }
        .task(id: store.currentYear) { await store.updateHolidays() }
        .overlay {
            if let celebration = store.celebration {
                CelebrationView(celebration: celebration) { store.celebration = nil }
                    .zIndex(10)
            }
        }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(16)
                    .onTapGesture { store.toast = nil }
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(4))
                        if store.toast == toast { store.toast = nil }
                    }
            }
        }
        .alert("温馨提示", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("知道了", role: .cancel) {} } message: { Text(store.errorMessage ?? "") }
    }
}
