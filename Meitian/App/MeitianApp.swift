import SwiftUI

@main
struct MeitianApp: App {
    @State private var store = AppStore()
    @State private var arena = ArenaStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(arena)
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
        .tint(Theme.red)
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
