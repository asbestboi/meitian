import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @State private var retake = false
    @State private var confirmReset = false
    @State private var reminderTime = Date.now
    @AppStorage(PinyinPrefs.show) private var showPinyin = true
    @AppStorage(PinyinPrefs.toneColors) private var toneColors = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    levelCard
                    HStack(spacing: 12) {
                        tile("\(store.streak)", "Day streak", "flame.fill", Theme.red)
                        tile("\(store.bestStreak)", "Best streak", "trophy.fill", Theme.gold)
                    }
                    HStack(spacing: 12) {
                        tile("\(store.cards.count)", "Words learned", "book.fill", Theme.jade)
                        tile("\(store.challengeHistory.count)", "Challenges", "person.2.fill", Theme.plum)
                    }
                    calendar
                    levels
                    pinyinSettings
                    settings
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Progress")
        }
        .fullScreenCover(isPresented: $retake) {
            OnboardingFlow(retakeOnly: true, onRetakeDone: { retake = false })
                .environment(store)
        }
        .onAppear {
            reminderTime = Calendar.current.date(from: DateComponents(hour: store.profile.reminderHour,
                                                                      minute: store.profile.reminderMinute)) ?? .now
        }
    }

    private var levelCard: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: store.levelProgress, lineWidth: 12, gradient: [Theme.gold, Theme.red]) {
                VStack(spacing: 0) {
                    Text("Lv").font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
                    Text("\(store.playerLevel)").font(.rounded(.title, weight: .heavy)).contentTransition(.numericText())
                }
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.profile.name.isEmpty ? "Learner" : store.profile.name)
                    .font(.rounded(.title2, weight: .bold))
                Text("\(store.xp) XP · \(store.xpToNextLevel) to level \(store.playerLevel + 1)")
                    .font(.rounded(.subheadline)).foregroundStyle(.secondary)
                Pill(text: "Learning HSK \(store.currentLevel) · \(WordBank.levelTitle(store.currentLevel))",
                     color: Theme.levelColor(store.currentLevel), systemImage: "graduationcap.fill")
            }
            Spacer(minLength: 0)
        }
        .cardSurface()
    }

    private func tile(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.rounded(.largeTitle, weight: .heavy)).contentTransition(.numericText())
            Text(label).font(.rounded(.subheadline, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
    }

    /// Last 15 weeks, GitHub-style. Columns are weeks, rows Mon…Sun.
    private var calendar: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 // Monday = 0
        let weeks = 15
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today) ?? today
        return VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.rounded(.headline, weight: .bold))
            HStack(spacing: 4) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? today
                            let log = store.days[AppStore.key(for: date)]
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color(for: log, future: date > today))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.rounded(.caption2)).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(intensity(i)).frame(width: 12, height: 12)
                }
                Text("More").font(.rounded(.caption2)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity calendar. Current streak \(store.streak) days.")
    }

    private func intensity(_ i: Int) -> Color {
        switch i {
        case 0: return Color.primary.opacity(0.07)
        case 1: return Theme.jade.opacity(0.35)
        case 2: return Theme.jade.opacity(0.65)
        default: return Theme.jade
        }
    }

    private func color(for log: DayLog?, future: Bool) -> Color {
        if future { return .clear }
        guard let log, log.active else { return intensity(0) }
        let score = (log.learnedDone ? 1 : 0) + (log.reviewed > 0 ? 1 : 0) + (log.challenge != nil ? 1 : 0)
        return intensity(score)
    }

    private var levels: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Levels").font(.rounded(.headline, weight: .bold))
            ForEach(WordBank.levels, id: \.self) { level in
                let total = WordBank.words(level: level).count
                let done = store.learnedCount(level: level)
                let known = level <= store.profile.confirmedLevel
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("HSK \(level) · \(WordBank.levelTitle(level))").font(.rounded(.subheadline, weight: .bold))
                        if known { Pill(text: "Placement ✓", color: Theme.jade) }
                        Spacer()
                        Text("\(done)/\(total)").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(Theme.levelGradient(level))
                                .frame(width: max(10, geo.size.width * CGFloat(done) / CGFloat(max(total, 1))))
                                .opacity(done == 0 ? 0 : 1)
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
        .cardSurface()
    }

    private var pinyinSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $showPinyin) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Show pinyin", systemImage: "character.phonetic")
                    Text("Pinyin above characters on cards and quizzes. Turn it off to test your reading.")
                        .font(.rounded(.caption)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            Divider().padding(.leading, 16)
            Toggle(isOn: $toneColors) {
                Label("Tone colors", systemImage: "paintpalette.fill")
            }
            .padding(16)
            if toneColors {
                ToneLegend().padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .font(.rounded(.body))
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(Theme.spring, value: toneColors)
        .sensoryFeedback(.selection, trigger: showPinyin)
    }

    private var settings: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            HStack {
                Label("Name", systemImage: "person.fill")
                Spacer()
                TextField("Name", text: $store.profile.name)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { store.save() }
            }
            .padding(16)
            Divider().padding(.leading, 16)
            Stepper(value: $store.profile.dailyGoal, in: 1...15) {
                Label("New words a day: \(store.profile.dailyGoal)", systemImage: "target")
            }
            .padding(16)
            .onChange(of: store.profile.dailyGoal) { _, _ in store.save() }
            Divider().padding(.leading, 16)
            Toggle(isOn: $store.profile.reminderOn) {
                Label("Daily reminder", systemImage: "bell.fill")
            }
            .padding(16)
            .onChange(of: store.profile.reminderOn) { _, on in updateReminder(on) }
            if store.profile.reminderOn {
                Divider().padding(.leading, 16)
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .padding(16)
                    .onChange(of: reminderTime) { _, _ in updateReminder(true) }
            }
            Divider().padding(.leading, 16)
            Button { retake = true } label: {
                Label("Retake placement quiz", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            Divider().padding(.leading, 16)
            Button(role: .destructive) { confirmReset = true } label: {
                Label("Reset all progress", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset all progress", role: .destructive) {
                    Reminders.cancel()
                    store.resetAll()
                    arena.reset()
                }
            } message: {
                Text("Your words, streak, XP, challenges, coins and cosmetics will be deleted. This can't be undone.")
            }
        }
        .font(.rounded(.body))
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(Theme.spring, value: store.profile.reminderOn)
    }

    private func updateReminder(_ on: Bool) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        store.profile.reminderHour = c.hour ?? 19
        store.profile.reminderMinute = c.minute ?? 0
        store.save()
        if on {
            let p = store.profile
            Task {
                let ok = await Reminders.schedule(hour: p.reminderHour, minute: p.reminderMinute, name: p.name)
                if !ok { await MainActor.run { store.profile.reminderOn = false } }
            }
        } else {
            Reminders.cancel()
        }
    }
}
