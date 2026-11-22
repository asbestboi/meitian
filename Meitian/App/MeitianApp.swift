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
                    if p == .active {
                        store.refreshDay()
                        Task { await content.refreshIfStale(level: store.profile.confirmedLevel + 1) }
                        Task {
                            await OnlineService.shared.sync(store: store, arena: arena)
                            await OnlineService.shared.refreshInbox()
                        }
                    }
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
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TodayView(goToPractice: { tab = 1 })
                .tabItem { Label("Learn", systemImage: "map.fill") }
                // a free spin is waiting
                .badge(tab != 0 && store.spinWait <= 0 ? Text("🎰") : nil)
                .tag(0)
            PracticeView()
                .tabItem { Label("Practice", systemImage: "rectangle.stack.fill") }
                .tag(1)
            ArenaView()
                .tabItem { Label("Arena", systemImage: "flag.2.crossed.fill") }
                .tag(2)
            StatsView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .haptic(.selection, trigger: tab)
        .onChange(of: tab) { _, _ in SFX.shared.play(.tabSwitch) }
        .overlay { MilestoneCelebration() }
        .overlay {
            if let theme = store.arenaReveal {
                ArenaReveal(theme: theme) { withAnimation(Theme.spring) { store.arenaReveal = nil } }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let coins = arena.refunded {
                Text("Avatars were retired, +\(coins) 🪙 refunded")
                    .font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.background)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        SFX.shared.play(.coin)
                        try? await Task.sleep(for: .seconds(4.5))
                        withAnimation(Theme.spring) { arena.refunded = nil }
                    }
            }
        }
    }
}
