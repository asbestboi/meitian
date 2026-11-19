import SwiftUI

/// HSK level-up test: 20 mixed questions on the level's words; 80% unlocks the next level's words and
/// stories. Also used to test out of a level early ("skip ahead").
struct LevelTestView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Fixed when the test opens: passing raises the learner's level while the results are still showing.
    @State private var level: Int
    /// Opens weak-words practice after a failed test.
    var onPracticeWeak: (() -> Void)? = nil

    init(level: Int, onPracticeWeak: (() -> Void)? = nil) {
        _level = State(initialValue: level)
        self.onPracticeWeak = onPracticeWeak
    }

    @State private var questions: [QuizQuestion] = []
    @State private var started = false
    @State private var finished = false
    @State private var score = 0
    @State private var confetti = 0

    private var passed: Bool { levelTestPassed(right: UInt32(score), total: UInt32(questions.count)) }

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
                    Text("HSK \(level) test").font(.rounded(.headline, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                if finished {
                    results.transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if started {
                    QuizRunner(questions: questions, onDone: { correct in
                        score = correct
                        if levelTestPassed(right: UInt32(correct), total: UInt32(questions.count)) {
                            store.passLevelTest(level)
                            confetti += 1
                        }
                        withAnimation(Theme.bouncy) { finished = true }
                    })
                } else {
                    intro
                }
            }
            .padding(20)
            ConfettiView(trigger: confetti)
        }
        .onAppear { questions = makeQuestions() }
    }

    private func makeQuestions() -> [QuizQuestion] {
        let levelWords = WordBank.words(level: level)
        let ids = levelTestWordIds(levelIds: levelWords.map(\.id),
                                   learnedIds: levelWords.filter { store.cards[$0.id] != nil }.map(\.id),
                                   seed: UInt64.random(in: 0...UInt64.max))
        let kinds = QuizQuestion.mixedKinds()
        return ids.compactMap(WordBank.word).enumerated().map { i, w in
            QuizQuestion.make(for: w, kind: kinds[i % kinds.count], pool: levelWords)
        }
    }

    private var intro: some View {
        let learned = store.learnedCount(level: level)
        let total = WordBank.words(level: level).count
        return VStack(spacing: 18) {
            Spacer()
            Text("🎓").font(.system(size: 80))
            Text("HSK \(level) level-up").font(.rounded(.largeTitle, weight: .heavy))
            Text("\(questions.count) questions on HSK \(level) words. Get 80% right to unlock HSK \(level + 1) words and stories.")
                .font(.rounded(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if learned < total {
                Text("You've learned \(learned) of \(total) words, so some of these will be new. Skipping ahead is allowed ✦")
                    .font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.gold).multilineTextAlignment(.center)
            }
            Spacer()
            BigButton(title: "start the test", systemImage: "arrow.right", enabled: !questions.isEmpty) {
                withAnimation(Theme.spring) { started = true }
            }
        }
    }

    private var results: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(passed ? "🏅" : "💪").font(.system(size: 90))
            Text(passed ? "升级了！" : "差一点！").font(.hanzi(44, weight: .heavy))
            Text(passed ? "shēngjí le · level up!" : "chà yìdiǎn · so close!")
                .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
            Text("\(score) / \(questions.count) right").font(.rounded(.title2, weight: .heavy))
                .foregroundStyle(passed ? Theme.jade : Theme.red)
            Text(passed ? "+100 XP · HSK \(level + 1) words and stories are unlocked."
                        : "You need \(Int((Double(questions.count) * 0.8).rounded(.up))) right. Practice your weak words and try again any time.")
                .font(.rounded(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            if !passed, let onPracticeWeak {
                BigButton(title: "practice weak words", systemImage: "bolt.fill") {
                    dismiss()
                    onPracticeWeak()
                }
            }
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
    }
}

struct LevelRef: Identifiable {
    let level: Int
    var id: Int { level }
}

/// Today: shown once every word of the current level is learned. The test itself is presented by the
/// parent (this card disappears as soon as the test is passed).
struct LevelTestCard: View {
    @Environment(AppStore.self) private var store
    var onStart: (Int) -> Void

    var body: some View {
        if store.levelComplete {
            if store.canLevelUp {
                Button { onStart(store.currentLevel) } label: {
                    HStack(spacing: 16) {
                        Text("🎓").font(.system(size: 40))
                            .frame(width: 66, height: 66)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HSK \(store.currentLevel) test").font(.rounded(.title3, weight: .heavy))
                            Text("all HSK \(store.currentLevel) words learned ✦ pass to unlock HSK \(store.currentLevel + 1)")
                                .font(.rounded(.caption)).opacity(0.85)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .streetBlock(Theme.nightGradient, padding: 18)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            } else {
                Text("You've learned every word up to HSK \(store.currentLevel) 🐉 more levels arrive with new lesson packs.")
                    .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(padding: 16)
            }
        }
    }
}
