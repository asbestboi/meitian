import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(Invites.settingKey) private var inviteNotifications = true
    @Environment(ContentSync.self) private var content
    @AppStorage(ContentSync.allLevelsKey) private var allLevels = false
    @State private var confirmClear = false
    @Environment(ArenaStore.self) private var arena
    @State private var retake = false
    @State private var levelTest = false
    @State private var confirmReset = false
    @State private var showSettings = false
    @State private var reminderTime = Date.now
    @AppStorage(PinyinPrefs.show) private var showPinyin = true
    @AppStorage(PinyinPrefs.toneColors) private var toneColors = true
    @AppStorage(Prefs.swears) private var swears = false
    @AppStorage(Prefs.sounds) private var sounds = true
    @AppStorage(Prefs.volume) private var volume = 0.8
    @AppStorage(Prefs.haptics) private var haptics = true
    @State private var pictureNote: String?
    @State private var pictureBusy = false
    @AppStorage(Prefs.listening) private var listening = true
    @AppStorage(Prefs.speaking) private var speaking = true
    @AppStorage(Prefs.noListenUntil) private var noListenUntil = 0.0
    @AppStorage(Prefs.noSpeakUntil) private var noSpeakUntil = 0.0

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
                        tile("\(store.slots.spins)", "Spins", "dice.fill", Theme.plum)
                    }
                    calendar
                    levels
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showSettings) { settingsPage }
        }
        .fullScreenCover(isPresented: $levelTest) {
            LevelTestView(level: store.currentLevel).environment(store)
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

    /// Everything adjustable, out of the way of the progress overview.
    private var settingsPage: some View {
        ScrollView {
            VStack(spacing: 24) {
                settings
                pinyinSettings
                exerciseSettings
                contentSettings
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .toggleStyle(SoundToggleStyle())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var levelCard: some View {
        HStack(spacing: 18) {
            PictureUpload(name: store.profile.name, note: $pictureNote, busy: $pictureBusy) {
                VStack(spacing: 6) {
                    ProgressRing(progress: store.levelProgress, lineWidth: 8, gradient: [Theme.gold, Theme.red]) {
                        MyPicture(size: 72)
                    }
                    .frame(width: 92, height: 92)
                    let has = !(OnlineService.shared.profile?.avatar ?? "").isEmpty
                    Text(pictureBusy ? "…" : has ? "change picture" : "+ add picture")
                        .font(.rounded(.caption, weight: .bold)).foregroundStyle(Theme.red)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(store.profile.name.isEmpty ? "Learner" : store.profile.name)
                    .font(.rounded(.title2, weight: .bold))
                Text("Lv \(store.playerLevel) · \(store.xp) XP · \(store.xpToNextLevel) to level \(store.playerLevel + 1)")
                    .font(.rounded(.subheadline)).foregroundStyle(.secondary)
                Pill(text: "Learning HSK \(store.currentLevel) · \(WordBank.levelTitle(store.currentLevel))",
                     color: Theme.levelColor(store.currentLevel), systemImage: "graduationcap.fill")
                ArenaBadge(theme: store.arenaTheme, fill: Theme.background)
                if let pictureNote { Text(pictureNote).font(.rounded(.caption)).foregroundStyle(.secondary) }
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
        .haptic(.selection, trigger: showPinyin)
    }

    private func settingsBlock<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.lowercased()).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .font(.rounded(.body))
                .cardSurface(padding: 0)
        }
    }

    private var exerciseSettings: some View {
        let now = Date.now.timeIntervalSince1970
        return settingsBlock("Sound & exercises") {
            Toggle(isOn: $sounds) { Label("Sound effects", systemImage: "speaker.wave.3.fill") }
                .padding(16)
            if sounds {
                Slider(value: $volume, in: 0...1) {
                    Text("Sound volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                } onEditingChanged: { editing in
                    if !editing { SFX.shared.play(.coin) }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            Divider().padding(.leading, 16)
            Toggle(isOn: $haptics) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    Text("Little vibrations when you tap and answer.").font(.rounded(.caption)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            Divider().padding(.leading, 16)
            Toggle(isOn: $listening) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Listening exercises", systemImage: "ear.fill")
                    if listening && noListenUntil > now {
                        Text("Paused until \(Date(timeIntervalSince1970: noListenUntil).formatted(date: .omitted, time: .shortened))")
                            .font(.rounded(.caption)).foregroundStyle(Theme.gold)
                    }
                }
            }
            .padding(16)
            Divider().padding(.leading, 16)
            Toggle(isOn: $speaking) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Speaking exercises", systemImage: "mic.fill")
                    if speaking && noSpeakUntil > now {
                        Text("Paused until \(Date(timeIntervalSince1970: noSpeakUntil).formatted(date: .omitted, time: .shortened))")
                            .font(.rounded(.caption)).foregroundStyle(Theme.gold)
                    } else {
                        Text("Say words out loud, checked with speech recognition.")
                            .font(.rounded(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            if noListenUntil > now || noSpeakUntil > now {
                Divider().padding(.leading, 16)
                Button {
                    noListenUntil = 0
                    noSpeakUntil = 0
                } label: {
                    Label("I can listen & speak again", systemImage: "play.circle.fill")
                }
                .padding(16)
            } else {
                Divider().padding(.leading, 16)
                HStack(spacing: 10) {
                    Button { noListenUntil = now + 3600 } label: {
                        Label("Can't listen 1h", systemImage: "speaker.slash.fill").font(.rounded(.subheadline, weight: .bold))
                    }
                    Spacer()
                    Button { noSpeakUntil = now + 3600 } label: {
                        Label("Can't speak 1h", systemImage: "mic.slash.fill").font(.rounded(.subheadline, weight: .bold))
                    }
                }
                .padding(16)
            }
        }
    }

    private var contentSettings: some View {
        settingsBlock("Content") {
            Toggle(isOn: $swears) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Swear words 🤬", systemImage: "exclamationmark.bubble.fill")
                    Text("Adds the street deck: one swear word a day, Swear Sprint, rude cosmetics. Battles only match players with the same setting.")
                        .font(.rounded(.caption)).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.pink)
            .padding(16)
            Divider().padding(.leading, 16)
            downloads
        }
        .haptic(.selection, trigger: swears)
    }

    private var statusText: String {
        switch content.status {
        case .idle: return content.stats.sentences > 0 ? "Downloaded" : "Not downloaded yet"
        case .checking: return "Checking for new lessons…"
        case .downloading(let done, let total): return "Downloading \(done + 1) of \(total)…"
        case .ready: return "Up to date"
        case .failed(let message): return message
        }
    }

    @ViewBuilder
    private var downloads: some View {
        let st = content.stats
        VStack(alignment: .leading, spacing: 6) {
            Label("Lessons", systemImage: "arrow.down.circle.fill")
            Text("\(st.words) words · \(st.sentences) sentences · \(st.stories) stories")
                .font(.rounded(.subheadline, weight: .semibold))
            Text(statusText).font(.rounded(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        Divider().padding(.leading, 16)
        Toggle(isOn: $allLevels) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Download every level", systemImage: "square.stack.3d.up.fill")
                Text("Otherwise only sentences for the HSK levels around yours (saves space).")
                    .font(.rounded(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .onChange(of: allLevels) { _, _ in
            Task { await content.refresh(level: store.profile.confirmedLevel + 1) }
        }
        Divider().padding(.leading, 16)
        HStack {
            Button {
                Task { await content.refresh(level: store.profile.confirmedLevel + 1, force: false) }
            } label: {
                Label("Update now", systemImage: "arrow.clockwise")
            }
            Spacer()
            Button(role: .destructive) { confirmClear = true } label: {
                Text("Delete (\(ByteCountFormatter.string(fromByteCount: content.cacheBytes, countStyle: .file)))")
            }
            .confirmationDialog("Delete downloaded lessons?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete downloads", role: .destructive) { content.clear() }
            } message: {
                Text("Your progress stays. Words you learned from downloads come back after the next download.")
            }
        }
        .font(.rounded(.subheadline, weight: .bold))
        .padding(16)
        if !content.credits.isEmpty {
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(content.credits, id: \.self) { Text($0) }
            }
            .font(.rounded(.caption2))
            .foregroundStyle(.secondary)
            .padding(16)
        }
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
            Toggle(isOn: $inviteNotifications) {
                Label("Battle invitations", systemImage: "envelope.badge.fill")
            }
            .padding(16)
            .onChange(of: inviteNotifications) { _, on in if on { Task { await Invites.shared.askPermission() } } }
            Divider().padding(.leading, 16)
            Button { retake = true } label: {
                Label("Retake placement quiz", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            if store.canLevelUp {
                Divider().padding(.leading, 16)
                Button { levelTest = true } label: {
                    Label("Skip ahead: take the HSK \(store.currentLevel) test", systemImage: "graduationcap.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
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
                Text("Your words, streak, XP, story history, coins and cosmetics will be deleted. This can't be undone.")
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
