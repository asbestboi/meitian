import SwiftUI

struct PracticeView: View {
    @Environment(AppStore.self) private var store
    @Environment(ContentSync.self) private var content
    @State private var session: PracticeSession.Mode?
    @State private var search = ""
    @State private var levelFilter = 0
    @State private var status: WordFilter = .all
    @State private var selected: Word?
    @State private var sprint = false
    @State private var sentences = false
    @State private var challenge = false
    @State private var showLibrary = false
    @AppStorage(Prefs.swears) private var swears = false
    @AppStorage(Prefs.listening) private var listeningOn = true
    @AppStorage(Prefs.speaking) private var speakingOn = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    reviewHero
                    section("practice") { modes }
                    section("read") {
                        VStack(spacing: 24) {
                            StoryHub()
                            StoryHub(chats: true)
                        }
                    }
                    libraryRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Practice")
            .navigationDestination(isPresented: $showLibrary) { libraryPage }
        }
        .fullScreenCover(item: $session) { mode in
            PracticeSession(mode: mode).environment(store)
        }
        .fullScreenCover(isPresented: $sentences) {
            SentenceSession().environment(store)
        }
        .fullScreenCover(isPresented: $sprint) {
            SwearSprintView().environment(store)
        }
        .sheet(isPresented: $challenge) {
            ChallengeView().environment(store)
                .presentationCornerRadius(32)
        }
        .onChange(of: swears) { _, on in if !on && levelFilter == WordBank.streetLevel { levelFilter = 0 } }
        .sheet(item: $selected) { w in
            WordDetail(word: w)
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.rounded(.title3, weight: .heavy))
            content()
        }
    }

    /// Every practice mode as the same kind of tile, two per row.
    private var modes: some View {
        let hasWords = !store.learnedWords.isEmpty
        let weak = store.weakWords(limit: 12)
        let sentenceCount = Int(content.stats.sentences)
        let challengeDone = store.today.challenge != nil
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            modeTile("⚡", "weak words", weak.count >= 4 ? "\(weak.count) to fix" : "none yet", enabled: weak.count >= 4) {
                session = .weak
            }
            modeTile("💬", "sentences", sentenceCount > 0 ? "build & translate" : "downloading…", enabled: sentenceCount > 0) {
                sentences = true
            }
            modeTile("🎧", "listening", "10 questions", enabled: hasWords && listeningOn) { session = .listening }
            modeTile("🎙️", "speaking", "10 questions", enabled: hasWords && speakingOn) { session = .speaking }
            modeTile("🔀", "speed mix", "everything, fast", enabled: hasWords) { session = .mixed }
            modeTile(challengeDone ? "🏆" : store.profile.preferredFriend.emoji, "friend challenge",
                     challengeDone ? "done today ✓" : "use a word for real", enabled: true) { challenge = true }
            if swears {
                modeTile("🤬", "swear sprint", "60 s rapid fire · 18+", enabled: true) { sprint = true }
            }
        }
    }

    private func modeTile(_ emoji: String, _ title: String, _ subtitle: String, enabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(emoji).font(.system(size: 32))
                Text(title).font(.rounded(.headline, weight: .bold))
                Text(enabled ? subtitle : (store.learnedWords.isEmpty ? "learn words first" : subtitle))
                    .font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary)
            .cardSurface(padding: 16)
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }

    private var libraryRow: some View {
        Button { showLibrary = true } label: {
            HStack(spacing: 16) {
                Text("📚").font(.system(size: 32))
                VStack(alignment: .leading, spacing: 4) {
                    Text("my words").font(.rounded(.headline, weight: .bold))
                    Text("\(store.cards.count) learned · search the whole HSK list")
                        .font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.headline.weight(.bold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .cardSurface(padding: 16)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var libraryPage: some View {
        ScrollView {
            library.padding(.horizontal, 16).padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("My words")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search hanzi, pinyin or English")
    }

    private var reviewHero: some View {
        let due = store.dueWords.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(due > 0 ? "\(due) due for review" : "All caught up ✨")
                        .font(.rounded(.title2, weight: .bold))
                    Text(due > 0 ? "Spaced repetition: review right before you'd forget."
                         : "Come back tomorrow, or pick a mode below.")
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

    private var filtered: [Word] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let weak = status == .weak ? Set(store.weakWords(limit: 200).map(\.id)) : []
        let now = Date.now
        return WordBank.visible(swears: swears).filter { (w: Word) -> Bool in
            let card = store.cards[w.id]
            let statusOK: Bool = switch status {
            case .all: true
            case .learned: card != nil
            case .weak: weak.contains(w.id)
            case .due: card.map { $0.due <= now } ?? false
            case .mastered: card?.mastered ?? false
            case .new: card == nil
            }
            return statusOK && (levelFilter == 0 || w.level == levelFilter) &&
            (q.isEmpty || w.hanzi.contains(q) || w.meaning.lowercased().contains(q) ||
             w.pinyin.folding(options: .diacriticInsensitive, locale: nil).lowercased()
                .contains(q.folding(options: .diacriticInsensitive, locale: nil)))
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Level", selection: $levelFilter) {
                Text("All").tag(0)
                ForEach(WordBank.levels, id: \.self) { Text(WordBank.levels.count > 4 ? "\($0)" : "HSK \($0)").tag($0) }
                if swears { Text("🤬").tag(WordBank.streetLevel) }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(WordFilter.allCases) { s in
                        Button { withAnimation(Theme.spring) { status = s } } label: {
                            Text(s.label).font(.rounded(.caption, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(status == s ? Theme.ink : Theme.card, in: Capsule())
                                .foregroundStyle(status == s ? Theme.background : .primary)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text("\(filtered.count) words").font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
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
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(1...6, id: \.self) { b in
                            Capsule().fill(b <= state.box ? Theme.jade : Color.secondary.opacity(0.2)).frame(width: 5, height: 10)
                        }
                    }
                    Text("✓\(state.correct) ✗\(state.wrong)").font(.rounded(.caption2, weight: .semibold)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("box \(state.box), \(state.correct) right, \(state.wrong) wrong")
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
                if !word.example.isEmpty {
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
                }
                ExampleSentences(word: word)
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
    enum Mode: String, Identifiable { case review, listening, speaking, mixed, weak; var id: String { rawValue } }
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
                    Text(mode == .review ? "Review" : mode == .listening ? "Listening" : mode == .speaking ? "Speaking" : mode == .weak ? "Weak words" : "Speed mix")
                        .font(.rounded(.headline, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                if finished {
                    results.transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if !questions.isEmpty {
                    QuizRunner(questions: questions, onAnswer: { q, right in
                        if mode == .review || mode == .weak { store.grade(q.word, right: right) }
                        else if right { store.addXP(2) }
                    }, onDone: { correct in
                        score = correct
                        if mode == .listening || mode == .speaking { store.count(.listenSpeak) }
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
        case .weak:
            let kinds = QuizQuestion.mixedKinds()
            return store.weakWords(limit: 12).enumerated().map { i, w in QuizQuestion.make(for: w, kind: kinds[i % kinds.count], pool: learned) }
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

/// Word library filter by how the learner is doing with each word.
enum WordFilter: String, CaseIterable, Identifiable {
    case all, learned, weak, due, mastered, new
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "all"
        case .learned: "learned"
        case .weak: "⚡ weak"
        case .due: "due"
        case .mastered: "👑 mastered"
        case .new: "not yet"
        }
    }
}
