import SwiftUI

/// Learn tab: one winding path through the current HSK level (Duolingo-style map). Lessons, sentences, a story
/// checkpoint after every unit, the level-up test at the end. One big button always says what's next.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    var goToPractice: () -> Void

    @State private var lessonWords: [Word] = []
    @State private var learning = false
    @State private var testLevel: LevelRef?
    @State private var story: StoryRef?
    @State private var storyUnit = 0
    @State private var sentenceNode: SentenceNodeRef?
    @State private var goals = false
    @State private var hint: String?
    @State private var hintTick = 0
    @State private var scroll = ScrollOffset()
    @State private var lastNext: String?

    var body: some View {
        let units = store.learnPath
        let next = units.flatMap(\.nodes).first(where: \.next)
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if let saved = store.freezeNotice { freezeBanner(saved) }
                        ForEach(units, id: \.number) { unit in
                            unitHeader(unit)
                            ForEach(Array(unit.nodes.enumerated()), id: \.offset) { i, node in
                                PathNodeButton(node: node, level: store.currentLevel,
                                               swing: pathSwing(index: UInt32(i))) { tap(node) }
                                    .id(nodeId(node))
                            }
                        }
                        Text("HSK \(store.currentLevel + 1) unlocks after the test ✦")
                            .font(.rounded(.footnote, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.vertical, 32)
                    }
                    .padding(.horizontal, 16)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: -geo.frame(in: .named("path")).minY)
                    })
                }
                .coordinateSpace(name: "path")
                .onPreferenceChange(ScrollOffsetKey.self) { [scroll] y in scroll.y = y }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let next { proxy.scrollTo(nodeId(next), anchor: .center) }
                }
            }
            .background(ArenaBackground(theme: store.arenaTheme, strength: 0.42, scroll: scroll).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { startBar(next) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $learning) {
            LearnSession(words: lessonWords).environment(store)
        }
        .fullScreenCover(item: $testLevel) { ref in
            LevelTestView(level: ref.level, onPracticeWeak: goToPractice).environment(store)
        }
        .fullScreenCover(item: $story) { ref in
            StoryPlayer(story: ref.story, onFinished: storyFinished).environment(store)
        }
        .fullScreenCover(item: $sentenceNode) { ref in
            SentenceSession(node: ref.node).environment(store)
        }
        .sheet(isPresented: $goals) {
            GoalsSheet()
                .environment(store).environment(arena)
                .sheetSounds()
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .haptic(.warning, trigger: hintTick)
        .onAppear { store.checkArena(); lastNext = next.map(nodeId) }
        .onChange(of: store.currentLevel) { _, _ in store.checkArena() }
        // finishing a node opens the next one
        .onChange(of: "\(store.cards.count)-\(store.profile.pathSentences?.count ?? 0)") { _, _ in
            let now = store.nextPathNode.map(nodeId)
            if let lastNext, let now, lastNext != now { SFX.shared.play(.nodeUnlock) }
            lastNext = now
        }
    }

    private func nodeId(_ n: PathNode) -> String { "\(n.unit)-\(n.kind)-\(n.number)" }

    // MARK: actions

    private func tap(_ node: PathNode) {
        switch (node.kind, node.state) {
        case (_, .locked):
            switch node.kind {
            case .lesson: show("finish the lessons before this one first")
            case .sentences: show("finish lesson \(node.number) to open these sentences")
            case .story: show("finish unit \(node.unit)'s sentences to open its story")
            case .test: show("learn every lesson to unlock the test")
            }
        case (.lesson, .done):
            start(store.lessonWords(Int(node.number)))
        case (.lesson, .open):
            start(store.nextUpWords())
        case (.sentences, _):
            sentenceNode = SentenceNodeRef(node: node)
        case (.story, _):
            openStory(unit: Int(node.unit), done: node.state == .done)
        case (.test, _):
            if store.canLevelUp { testLevel = LevelRef(level: store.currentLevel) }
            else { show("you've reached the highest level 🐉") }
        }
    }

    private func start(_ words: [Word]) {
        guard !words.isEmpty else { return }
        lessonWords = words
        learning = true
    }

    /// Odd units get a picture story, even units an SMS chat.
    private func openStory(unit: Int, done: Bool) {
        let chat = unit % 2 == 0
        if let s = StoryProgress.next(chat: chat, store: store, unit: unit)
            ?? StoryProgress.next(chat: !chat, store: store, unit: unit) {
            ImagePrefetch.run(s)
            storyUnit = done ? 0 : unit
            story = StoryRef(story: s)
        } else if !done {
            // nothing new to read right now: the checkpoint becomes a treasure chest
            store.finishPathStory(unit: unit)
            show("🎁 chest opened · +20 XP")
        } else {
            show("learn more words to unlock the next story")
        }
    }

    /// Finishing the story completes the checkpoint.
    private func storyFinished(translations: Int) {
        guard storyUnit > 0 else { return }
        store.finishPathStory(unit: storyUnit, translations: translations)
        storyUnit = 0
    }

    private func show(_ text: String) {
        hintTick += 1
        withAnimation(Theme.spring) { hint = text }
        let tick = hintTick
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if tick == hintTick { withAnimation(Theme.spring) { hint = nil } }
        }
    }

    // MARK: pieces

    private var topBar: some View {
        let claimable = store.quests.filter { $0.done && !store.isClaimed($0.quest) }.count
        let questsDone = store.quests.filter(\.done).count
        return HStack(spacing: 8) {
            Text("HSK \(store.currentLevel)")
                .font(.rounded(.subheadline, weight: .heavy))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.levelColor(store.currentLevel).opacity(0.16), in: Capsule())
                .foregroundStyle(Theme.levelColor(store.currentLevel))
            Spacer()
            StreakBadge(streak: store.streak)
            Button { goals = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill").foregroundStyle(Theme.gold)
                    Text("\(max(store.today.xp, 0))").font(.rounded(.headline, weight: .heavy))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
            }
            .accessibilityLabel("XP today and daily goals")
            Button { goals = true } label: {
                HStack(spacing: 4) {
                    Text("🎯")
                    Text("\(questsDone)/\(store.quests.count)").font(.rounded(.headline, weight: .heavy))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if claimable > 0 {
                        Circle().fill(Theme.red).frame(width: 10, height: 10).offset(x: 2, y: -2)
                    }
                }
            }
            .accessibilityLabel("Daily quests, \(questsDone) of \(store.quests.count) done")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.background.opacity(0.94))
    }

    private func unitHeader(_ unit: PathUnit) -> some View {
        let done = unit.nodes.allSatisfy { $0.state == .done || $0.kind == .test }
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("unit \(unit.number)").font(.rounded(.title3, weight: .heavy))
                Text("HSK \(store.currentLevel) · lessons \(unit.firstLesson)–\(unit.lastLesson)")
                    .font(.rounded(.subheadline, weight: .semibold)).opacity(0.85)
            }
            Spacer()
            if done { Image(systemName: "checkmark.seal.fill").font(.title2) }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Theme.levelGradient(store.currentLevel),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, unit.number == 1 ? 8 : 32)
        .padding(.bottom, 16)
    }

    private func freezeBanner(_ saved: Int) -> some View {
        HStack(spacing: 12) {
            Text("🧊").font(.title2)
            Text("A streak freeze saved your \(saved)-day streak!").font(.rounded(.subheadline, weight: .bold))
            Spacer(minLength: 0)
            Button { withAnimation(Theme.spring) { store.freezeNotice = nil } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 32, height: 32)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Theme.sky.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    /// The one primary action, in the thumb zone.
    private func startBar(_ next: PathNode?) -> some View {
        VStack(spacing: 8) {
            if let hint {
                Text(hint).font(.rounded(.subheadline, weight: .bold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.ink, in: Capsule())
                    .foregroundStyle(Theme.background)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let next {
                Button { tap(next) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(startTitle(next)).font(.rounded(.headline, weight: .heavy))
                            Text(startSubtitle(next)).font(.rounded(.caption, weight: .semibold)).opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.headline.weight(.heavy))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(Theme.limeGradient, in: Capsule())
                    .shadow(color: Theme.lime.opacity(0.35), radius: 16, y: 6)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    private func startTitle(_ n: PathNode) -> String {
        switch n.kind {
        case .test: return "take the HSK \(store.currentLevel) test"
        case .sentences: return "build sentences"
        case .story: return "read the unit \(n.unit) story"
        case .lesson: return store.today.learnedDone ? "start lesson \(n.number)" : "learn today's words"
        }
    }

    private func startSubtitle(_ n: PathNode) -> String {
        switch n.kind {
        case .test: return "pass with 80% to unlock HSK \(store.currentLevel + 1)"
        case .sentences: return "+\(pathSentencesXp()) XP · only words you know"
        case .story: return "+20 XP"
        case .lesson: return "unit \(n.unit) · lesson \(n.number) · \(store.profile.dailyGoal) new words"
        }
    }
}

struct SentenceNodeRef: Identifiable {
    let node: PathNode
    var id: String { "\(node.unit)-\(node.number)" }
}

/// One stop on the path: a chunky round button with a darker base (pressable depth).
struct PathNodeButton: View {
    let node: PathNode
    let level: Int
    /// -1…1 sideways position.
    let swing: Double
    let action: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGFloat { node.kind == .lesson ? 72 : 84 }

    private var color: Color {
        switch node.state {
        case .locked: return Color.secondary.opacity(0.22)
        case .done, .open:
            switch node.kind {
            case .test: return Theme.gold
            case .story: return Theme.hot
            case .sentences: return Theme.sky
            case .lesson: return Theme.levelColor(level)
            }
        }
    }

    private var icon: String {
        switch (node.kind, node.state) {
        case (.lesson, .done): return "checkmark"
        case (.lesson, _): return node.state == .locked ? "lock.fill" : "star.fill"
        case (.sentences, .done): return "checkmark.bubble.fill"
        case (.sentences, _): return "text.bubble.fill"
        case (.story, .done): return "book.closed.fill"
        case (.story, _): return "book.fill"
        case (.test, _): return "trophy.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).brightness(-0.18).offset(y: 6)
                Circle().fill(color)
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .heavy))
                    .foregroundStyle(node.state == .locked ? Color.secondary : Color.white)
            }
            .frame(width: size, height: size)
            .background {
                if node.next {
                    Circle().stroke(color.opacity(0.35), lineWidth: 6)
                        .frame(width: size + 18, height: size + 18)
                        .scaleEffect(pulse ? 1.08 : 0.96)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .overlay(alignment: .top) {
            if node.next {
                Text(node.kind == .test ? "TEST" : "START")
                    .font(.rounded(.caption, weight: .heavy))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.card, in: Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                    .foregroundStyle(color)
                    .offset(y: pulse ? -44 : -40)
                    .fixedSize()
            }
        }
        .overlay(alignment: .bottom) {
            if node.kind != .lesson {
                Text(caption)
                    .font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
                    .offset(y: 28).fixedSize()
            }
        }
        .offset(x: CGFloat(swing) * 72)
        .frame(maxWidth: .infinity)
        .padding(.vertical, node.kind == .lesson ? 10 : 22)
        .onAppear {
            guard node.next, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(accessibility)
    }

    private var caption: String {
        switch node.kind {
        case .lesson: return ""
        case .sentences: return "sentences · +\(pathSentencesXp()) XP"
        case .story: return "story"
        case .test: return "level-up test"
        }
    }

    private var accessibility: String {
        let what = switch node.kind {
        case .lesson: "Lesson \(node.number)"
        case .sentences: "Sentences after lesson \(node.number)"
        case .story: "Unit \(node.unit) story"
        case .test: "HSK \(level) test"
        }
        let state = switch node.state {
        case .done: "done"
        case .open: "open"
        case .locked: "locked"
        }
        return "\(what), \(state)"
    }
}

/// Today's milestones and quests (from the top bar).
struct GoalsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MilestoneCard()
                    QuestCard()
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("today's goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Full-screen session: swipe through cards, then a quick quiz, then celebrate.
struct LearnSession: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let words: [Word]

    enum Phase { case cards, quiz, failed, done }
    @State private var phase: Phase = .cards
    @State private var questions: [QuizQuestion] = []
    @State private var score = 0
    @State private var confetti = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Close")
                    Spacer()
                    Text(phase == .cards ? "Swipe right if you've got it" : phase == .quiz ? "Quick check" : "")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                switch phase {
                case .cards:
                    SwipeDeck(words: words, onFinish: {
                        questions = makeQuiz()
                        withAnimation(Theme.spring) { phase = .quiz }
                    })
                    .transition(.opacity)
                case .quiz:
                    QuizRunner(questions: questions, useHearts: true, onFailed: {
                        withAnimation(Theme.spring) { phase = .failed }
                    }, onDone: { correct in
                        score = correct
                        store.finishLearning(words, quizCorrect: correct)
                        if correct == questions.count { store.count(.perfect) }
                        withAnimation(Theme.bouncy) { phase = .done }
                        confetti += 1
                    })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                case .failed:
                    // from the top: cards and a fresh quiz; nothing was saved from this try
                    OutOfHeartsView(onRetry: {
                        questions = []
                        score = 0
                        withAnimation(Theme.spring) { phase = .cards }
                    }, onQuit: { dismiss() })
                    .transition(.opacity)
                case .done:
                    done.transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(20)
            ConfettiView(trigger: confetti)
        }
        .haptic(.success, trigger: confetti)
    }

    private func makeQuiz() -> [QuizQuestion] {
        let pool = store.learnedWords + words
        let kinds = QuizQuestion.mixedKinds()
        return words.shuffled().enumerated().map { i, w in
            QuizQuestion.make(for: w, kind: kinds[i % kinds.count], pool: pool)
        }
    }

    private var done: some View {
        let gained = words.count * 10 + score * 5
        return VStack(spacing: 22) {
            Spacer()
            Text("🎉").font(.system(size: 90))
            Text("太棒了！").font(.hanzi(44, weight: .heavy)).foregroundStyle(Theme.warmGradient)
            Text("tài bàng le · awesome!").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
            Text("You learned \(words.count) new words today")
                .font(.rounded(.title3, weight: .semibold))
            HStack(spacing: 12) {
                stat("\(score)/\(words.count)", "quiz", Theme.jade)
                stat("+\(gained)", "XP", Theme.gold)
                stat("\(store.streak)", "day streak", Theme.red)
            }
            Spacer()
            Text("Nice! The next lesson is waiting on your path.")
                .font(.rounded(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.rounded(.title2, weight: .heavy)).foregroundStyle(color)
            Text(label).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
