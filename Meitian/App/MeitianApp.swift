import SwiftUI

@main
struct MeitianApp: App {
    @State private var store = AppStore()
    @State private var arena = ArenaStore()
    @State private var content = ContentSync()
    @Environment(\.scenePhase) private var phase

    init() {
        // story pictures: keep plenty on disk so stories work offline after the first read
        URLCache.shared = URLCache(memoryCapacity: 40 << 20, diskCapacity: 300 << 20)
        // clean, heavy titles in navigation bars
        let large = UIFont.systemFont(ofSize: 36, weight: .heavy)
        let inline = UIFont.systemFont(ofSize: 17, weight: .bold)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
        UINavigationBar.appearance().titleTextAttributes = [.font: inline]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(arena)
                .environment(content)
                .task { await content.start(level: store.profile.confirmedLevel + 1) }
                // a new placement result may need other level packs
                .onChange(of: store.profile.confirmedLevel) { _, _ in
                    Task { await content.refresh(level: store.profile.confirmedLevel + 1) }
                }
                .onChange(of: phase) { _, p in
                    if p == .active { store.refreshDay() }
                    if p == .background { store.save(); arena.save() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if store.profile.onboarded {
                MainTabs().transition(.opacity)
            } else {
                OnboardingFlow().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: store.profile.onboarded)
        .tint(Theme.ink)
    }
}

struct MainTabs: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TodayView(goToChallenge: { tab = 1 }, goToPractice: { tab = 2 })
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(0)
            ChallengeView()
                .tabItem { Label("Challenge", systemImage: "person.2.wave.2.fill") }
                .tag(1)
            PracticeView()
                .tabItem { Label("Practice", systemImage: "rectangle.stack.fill") }
                .tag(2)
            ArenaView()
                .tabItem { Label("Arena", systemImage: "flag.2.crossed.fill") }
                .tag(3)
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}
