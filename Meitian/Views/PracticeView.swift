import SwiftUI

struct PracticeView: View {
    @Environment(AppStore.self) private var store
    @State private var session: PracticeSession.Mode?
    @State private var search = ""
    @State private var levelFilter = 0
    @State private var selected: Word?
    @State private var sprint = false
    @AppStorage(Prefs.swears) private var swears = false
    @AppStorage(Prefs.listening) private var listeningOn = true
    @AppStorage(Prefs.speaking) private var speakingOn = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    reviewHero
                    if swears { sprintTile }
                    HStack(spacing: 12) {
                        gameTile("Listening", "ear.fill", Theme.skyGradient,
                                 enabled: store.learnedWords.count >= 1 && listeningOn) {
                            session = .listening
                        }
                        gameTile("Speaking", "mic.fill", Theme.pinkGradient,
                                 enabled: store.learnedWords.count >= 1 && speakingOn) {
                            session = .speaking
                        }
                        gameTile("Speed mix", "bolt.fill", Theme.goldGradient, enabled: store.learnedWords.count >= 1) {
                            session = .mixed
                        }
                    }
                    library
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Practice")
            .searchable(text: $search, prompt: "Search hanzi, pinyin or English")
        }
        .fullScreenCover(item: $session) { mode in
            PracticeSession(mode: mode).environment(store)
        }
        .fullScreenCover(isPresented: $sprint) {
            SwearSprintView().environment(store)
        }
        .onChange(of: swears) { _, on in if !on && levelFilter == WordBank.streetLevel { levelFilter = 0 } }
        .sheet(item: $selected) { w in
            WordDetail(word: w)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
    }

    private var reviewHero: some View {
        let due = store.dueWords.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(due > 0 ? "\(due) due for review" : "All caught up ✨")
                        .font(.rounded(.title2, weight: .bold))
                    Text(due > 0 ? "Spaced repetition: review right before you'd forget."
                         : "Come back tomorrow, or play a game below.")
                        .font(.rounded(.subheadline)).opacity(0.85)
                }
                Spacer()
                ProgressRing(progress: store.cards.isEmpty ? 0 : Double(store.masteredCount) / Double(store.cards.count),
                             lineWidth: 8, gradient: [.white.opacity(0.9), .white]) {
                    Text("\(store.masteredCount)").font(.rounded(.headline, weight: .heavy))
                }
                .frame(width: 64, height: 64)
                .accessibilityLabel("\(store.masteredCount) words mastered")
            }
            if due > 0 {
                Button { session = .review } label: {
                    HStack {
                        Text("Start review")
                        Spacer()
                        Image(systemName: "play.fill")
                    }
                    .font(.rounded(.headline, weight: .bold))
                    .foregroundStyle(Theme.sky)
                    .padding(.horizontal, 20).padding(.vertical, 15)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .foregroundStyle(.white)
        .streetBlock(Theme.skyGradient)
    }

    private var sprintTile: some View {
        Button { sprint = true } label: {
            HStack(spacing: 14) {
                Text("🤬").font(.system(size: 44))
                VStack(alignment: .leading, spacing: 3) {
                    Text("SWEAR SPRINT").font(.street(30))
                    Text("Learn street Chinese fast: flip cards, then 60 s of rapid fire. Combos multiply.")
                        .font(.rounded(.caption, weight: .semibold)).opacity(0.9)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.headline.weight(.black))
            }
            .foregroundStyle(.white)
            .streetBlock(Theme.inkGradient, padding: 18)
            .overlay(alignment: .topTrailing) { Pill(text: "18+", color: Theme.pink, tilt: 6).offset(x: -14, y: -8) }
        }
        .buttonStyle(PressableStyle())
    }

    private func gameTile(_ title: String, _ icon: String, _ g: LinearGradient, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(g, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.rounded(.headline, weight: .bold))
                Text(enabled ? "10 questions" : "Learn words first")
                    .font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary)
            .cardSurface(padding: 16)
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }

    private var filtered: [Word] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return WordBank.visible(swears: swears).filter { w in
            (levelFilter == 0 || w.level == levelFilter) &&
            (q.isEmpty || w.hanzi.contains(q) || w.meaning.lowercased().contains(q) ||
             w.pinyin.folding(options: .diacriticInsensitive, locale: nil).lowercased()
                .contains(q.folding(options: .diacriticInsensitive, locale: nil)))
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Word library").font(.rounded(.title3, weight: .bold)).padding(.top, 6)
            Picker("Level", selection: $levelFilter) {
                Text("All").tag(0)
                ForEach(WordBank.levels, id: \.self) { Text("HSK \($0)").tag($0) }
                if swears { Text("🤬").tag(WordBank.streetLevel) }
            }
            .pickerStyle(.segmented)
            LazyVStack(spacing: 8) {
                ForEach(filtered) { w in
                    Button { selected = w } label: { row(w) }
                        .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
    }

    private func row(_ w: Word) -> some View {
        let state = store.cards[w.id]
        return HStack(spacing: 14) {
            Text(w.hanzi).font(.hanzi(26, weight: .semibold)).frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                PinyinText(pinyin: w.pinyin, font: .rounded(.subheadline, weight: .bold))
                Text(w.meaning).font(.rounded(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let state {
                Image(systemName: state.mastered ? "crown.fill" : "checkmark.circle.fill")
                    .foregroundStyle(state.mastered ? Theme.gold : Theme.jade)
                    .accessibilityLabel(state.mastered ? "Mastered" : "Learned")
            } else {
                Image(systemName: "lock.open").foregroundStyle(.quaternary).accessibilityLabel("Not learned yet")
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct WordDetail: View {
    @Environment(AppStore.self) private var store
    let word: Word

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Pill(text: word.levelLabel, color: Theme.levelColor(word.level))
                    .padding(.top, 24)
                RubyText(hanzi: word.hanzi, pinyin: word.pinyin, size: word.hanzi.count > 3 ? 56 : 76,
                         weight: .semibold, alignment: .center)
                PinyinText(pinyin: word.pinyin, font: .rounded(.title2, weight: .bold))
                Text(word.meaning).font(.rounded(.title3, weight: .medium))
                HStack(spacing: 14) {
                    SpeakButton(text: word.hanzi, size: 56)
                    Button { Speaker.shared.say(word.hanzi, slow: true) } label: {
                        Image(systemName: "tortoise.fill").font(.title3)
                            .frame(width: 56, height: 56)
                            .background(Theme.jade.opacity(0.14), in: Circle())
                            .foregroundStyle(Theme.jade)
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityLabel("Play slowly")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        RubyText(hanzi: word.example, pinyin: word.examplePinyin, size: 22, alwaysShow: true)
                        Spacer()
                        SpeakButton(text: word.example, size: 36, tint: Theme.jade)
                    }
                    Text(word.exampleMeaning).font(.rounded(.subheadline, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                if let s = store.cards[word.id] {
                    HStack {
                        Label("Box \(s.box) of 6", systemImage: "archivebox.fill")
                        Spacer()
                        Text("✓ \(s.correct)  ✗ \(s.wrong)")
                    }
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Review / game session over learned words.
struct PracticeSession: View {
    enum Mode: String, Identifiable { case review, listening, speaking, mixed; var id: String { rawValue } }
    let mode: Mode

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var questions: [QuizQuestion] = []
    @State private var finished = false
    @State private var score = 0
    @State private var confetti = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline.weight(.bold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Close")
                    Spacer()
                    Text(mode == .review ? "Review" : mode == .listening ? "Listening" : mode == .speaking ? "Speaking" : "Speed mix")
                        .font(.rounded(.headline, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                if finished {
                    results.transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if !questions.isEmpty {
                    QuizRunner(questions: questions, onAnswer: { q, right in
                        if mode == .review { store.grade(q.word, right: right) }
                        else if right { store.xp += 2; store.save() }
                    }, onDone: { correct in
                        score = correct
                        withAnimation(Theme.bouncy) { finished = true }
                        confetti += 1
                    })
                }
            }
            .padding(20)
            ConfettiView(trigger: confetti)
        }
        .onAppear { if questions.isEmpty { questions = build() } }
    }

    private func build() -> [QuizQuestion] {
        let learned = store.learnedWords
        switch mode {
        case .review:
            let due = Array(store.dueWords.prefix(15))
            let kinds = QuizQuestion.mixedKinds()
            return due.enumerated().map { i, w in QuizQuestion.make(for: w, kind: kinds[i % kinds.count], pool: learned) }
        case .listening:
            return learned.shuffled().prefix(10).map { QuizQuestion.make(for: $0, kind: .listenToHanzi, pool: learned) }
        case .speaking:
            return learned.shuffled().prefix(8).map { QuizQuestion.make(for: $0, kind: .speak, pool: learned) }
        case .mixed:
            let kinds = QuizQuestion.mixedKinds()
            return learned.shuffled().prefix(10).map { QuizQuestion.make(for: $0, kind: kinds.randomElement()!, pool: learned) }
        }
    }

    private var results: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressRing(progress: questions.isEmpty ? 0 : Double(score) / Double(questions.count), lineWidth: 16,
                         gradient: [Theme.jade, Theme.sky]) {
                Text("\(score)/\(questions.count)").font(.rounded(.largeTitle, weight: .heavy))
            }
            .frame(width: 180, height: 180)
            Text(score == questions.count ? "Perfect! 完美 wánměi!" : score * 2 >= questions.count ? "Nice work! 不错 búcuò!" : "Keep going! 加油 jiāyóu!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(mode == .review ? "Words you missed will come back sooner." : "Every round makes them stick.")
                .font(.rounded(.body)).foregroundStyle(.secondary)
            Spacer()
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
    }
}
