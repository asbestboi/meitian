import SwiftUI

/// 🤬 Swear Sprint: learn a handful of street words with flip cards, then a 60-second rapid-fire round
/// where every right answer in a row pushes the combo multiplier up.
struct SwearSprintView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Phase { case intro, learn, countdown(Int), sprint, results }

    @State private var phase: Phase = .intro
    @State private var newWords: [Word] = []
    @State private var question: QuizQuestion?
    @State private var picked: Word?
    @State private var reveal = false
    @State private var score = 0
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var correct = 0
    @State private var answered = 0
    @State private var endsAt = Date.now
    @State private var token = 0
    @State private var shake: CGFloat = 0
    @State private var confetti = 0
    @State private var newBest = false
    @AppStorage("sprintBest") private var best = 0

    static let seconds = 60.0

    private var multiplier: Int { Int(sprintMultiplier(combo: UInt32(clamping: combo))) }
    private var pool: [Word] { WordBank.swears.filter { store.cards[$0.id] != nil } + newWords }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button { token += 1; dismiss() } label: {
                        Image(systemName: "xmark").font(.headline.weight(.black))
                            .frame(width: 40, height: 40)
                            .background(Theme.card, in: Circle())
                            .overlay(Circle().stroke(Theme.ink, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("🤬 swear sprint").font(.street(26))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                content
            }
            .padding(20)
            ConfettiView(trigger: confetti)
        }
        .animation(Theme.spring, value: phaseKey)
    }

    private var phaseKey: String {
        switch phase {
        case .intro: return "intro"
        case .learn: return "learn"
        case .countdown(let n): return "cd\(n)"
        case .sprint: return "sprint"
        case .results: return "results"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro: intro
        case .learn:
            VStack(spacing: 8) {
                Text("New street words. Swipe right when you've got one.")
                    .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                SwipeDeck(words: newWords, onFinish: {
                    store.addToReview(newWords)
                    startCountdown()
                })
            }
        case .countdown(let n):
            Spacer()
            Text("\(n)").font(.street(160)).foregroundStyle(Theme.pink)
                .id(n).transition(.scale(scale: 1.6).combined(with: .opacity))
            Text("Tap fast. Combos multiply your points.").font(.rounded(.headline)).foregroundStyle(.secondary)
            Spacer()
        case .sprint: sprint
        case .results: results
        }
    }

    // MARK: intro

    private var intro: some View {
        let fresh = WordBank.swears.filter { store.cards[$0.id] == nil }
        return VStack(spacing: 18) {
            Spacer()
            Text("🤬").font(.system(size: 90))
            Text("learn to swear fast").font(.street(46)).multilineTextAlignment(.center)
            Text("\(fresh.isEmpty ? "You've unlocked every street word." : "\(min(5, fresh.count)) new words first, then") 60 seconds of rapid fire. Three right in a row = ×2, six = ×3… up to ×5.")
                .font(.rounded(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Pill(text: "Best \(best)", color: Theme.gold, systemImage: "trophy.fill")
                Pill(text: "\(WordBank.swears.count - fresh.count)/\(WordBank.swears.count) learned", color: Theme.pink, tilt: 3)
            }
            Text("Real insults: great for understanding, use with care. 😉")
                .font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.red)
            Spacer()
            BigButton(title: fresh.isEmpty ? "Sprint!" : "Learn & sprint", systemImage: "bolt.fill",
                      gradient: Theme.pinkGradient) {
                newWords = Array(fresh.prefix(5))
                if newWords.isEmpty { startCountdown() } else { phase = .learn }
            }
        }
    }

    // MARK: sprint

    private func startCountdown() {
        token += 1
        countdownStep(3, t: token)
    }

    private func countdownStep(_ n: Int, t: Int) {
        guard t == token else { return }
        if n == 0 { startSprint(); return }
        phase = .countdown(n)
        SFX.shared.play(.tick)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { countdownStep(n - 1, t: t) }
    }

    private func startSprint() {
        score = 0; combo = 0; bestCombo = 0; correct = 0; answered = 0; newBest = false
        endsAt = Date.now.addingTimeInterval(Self.seconds)
        nextQuestion()
        phase = .sprint
        SFX.shared.play(.go)
        let t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.seconds) {
            guard t == token else { return }
            finish()
        }
    }

    private func nextQuestion() {
        let words = pool.isEmpty ? WordBank.swears : pool
        guard let w = words.randomElement() else { return }
        let kind: QuizQuestion.Kind = Bool.random() ? .hanziToMeaning : .meaningToHanzi
        question = QuizQuestion.make(for: w, kind: kind, pool: WordBank.swears)
        picked = nil
        reveal = false
    }

    private func pick(_ option: Word) {
        guard let q = question, picked == nil else { return }
        picked = option
        answered += 1
        let right = option.id == q.word.id
        if right {
            correct += 1
            combo += 1
            bestCombo = max(bestCombo, combo)
            score += 10 * multiplier
            SFX.shared.play(combo % 3 == 0 ? .coin : .correct)
        } else {
            combo = 0
            reveal = true
            SFX.shared.play(.wrong)
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
        let t = token
        DispatchQueue.main.asyncAfter(deadline: .now() + (right ? 0.25 : 0.8)) {
            guard t == token, case .sprint = phase else { return }
            withAnimation(Theme.spring) { nextQuestion() }
        }
    }

    private var sprint: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                let left = max(0, endsAt.timeIntervalSince(tl.date))
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.0f", left.rounded(.up)))
                            .font(.street(54))
                            .foregroundStyle(left < 10 ? Theme.red : .primary)
                            .contentTransition(.numericText(countsDown: true))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(score)").font(.street(44)).contentTransition(.numericText())
                            Text("points").font(.rounded(.caption, weight: .black)).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: left, total: Self.seconds).tint(left < 10 ? Theme.red : Theme.pink)
                }
            }
            HStack {
                Pill(text: "×\(multiplier) combo", color: multiplier > 1 ? Theme.pink : Theme.ink.opacity(0.6),
                     systemImage: "flame.fill", tilt: -4)
                    .scaleEffect(multiplier > 1 ? 1.15 : 1)
                    .animation(Theme.bouncy, value: multiplier)
                Spacer()
                Text("\(combo) in a row").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let q = question {
                QuizPanel(question: q, picked: picked, locked: picked != nil, reveal: reveal) { pick($0) }
                    .modifier(ShakeEffect(amount: shake))
            }
            Spacer(minLength: 0)
        }
        .haptic(.success, trigger: correct)
        .haptic(.error, trigger: shake)
    }

    private func finish() {
        token += 1
        if score > best { best = score; newBest = true }
        store.addXP(correct * 3)
        phase = .results
        confetti += 1
    }

    // MARK: results

    private var results: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(newBest ? "new best ✦" : "time!").font(.street(64)).foregroundStyle(newBest ? Theme.gold : Theme.pink)
            Text("\(score)").font(.street(110)).contentTransition(.numericText())
            Text("points").font(.rounded(.headline, weight: .bold)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                stat("\(correct)/\(answered)", "right")
                stat("×\(sprintMultiplier(combo: UInt32(clamping: bestCombo)))", "top combo")
                stat("+\(correct * 3)", "XP")
            }
            Spacer()
            BigButton(title: "Again", systemImage: "arrow.clockwise", gradient: Theme.pinkGradient) {
                newWords = []
                startCountdown()
            }
            Button("Done") { dismiss() }.font(.rounded(.headline, weight: .bold))
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.street(34))
            Text(l).font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(padding: 12)
    }
}
