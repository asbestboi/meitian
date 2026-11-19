import SwiftUI

struct OnboardingFlow: View {
    @Environment(AppStore.self) private var store

    enum Step: Int, Comparable {
        case welcome, name, claim, quiz, result, goal
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var name = ""
    @State private var claimed = 0
    @State private var confirmed = 0
    @State private var questions: [QuizQuestion] = []
    @State private var results: [(level: Int, right: Bool)] = []
    @State private var goal = 5
    @State private var reminder = true
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 19, minute: 0)) ?? .now
    @State private var confetti = 0
    /// When true, the placement test runs without onboarding around it (retake from settings).
    var retakeOnly = false
    var onRetakeDone: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            FloatingHanzi().ignoresSafeArea()
            Group {
                switch step {
                case .welcome: welcome
                case .name: nameStep
                case .claim: claimStep
                case .quiz: quizStep
                case .result: resultStep
                case .goal: goalStep
                }
            }
            .padding(24)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            ConfettiView(trigger: confetti)
        }
        .onAppear {
            if retakeOnly {
                claimed = store.profile.claimedLevel
                step = .claim
            }
        }
    }

    private func go(_ s: Step) {
        forward = s > step
        withAnimation(Theme.spring) { step = s }
    }

    private func backButton(to s: Step) -> some View {
        Button { go(s) } label: {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.bold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .foregroundStyle(.primary)
        .accessibilityLabel("Back")
    }

    // MARK: steps

    @State private var wave = false

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("每天")
                .font(.hanzi(96, weight: .heavy))
                .foregroundStyle(Theme.warmGradient)
                .scaleEffect(wave ? 1 : 0.6)
                .opacity(wave ? 1 : 0)
            VStack(spacing: 8) {
                Text("Měitiān")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text("A little Chinese every day.\nNew words, real friends, real sentences.")
                    .font(.rounded(.title3))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .opacity(wave ? 1 : 0)
            .offset(y: wave ? 0 : 20)
            Spacer()
            HStack(spacing: 18) {
                feature("sparkles", "Daily words", Theme.gold)
                feature("person.2.fill", "Friend challenges", Theme.jade)
                feature("flame.fill", "Streaks", Theme.red)
            }
            .opacity(wave ? 1 : 0)
            BigButton(title: "开始 · Let's start", systemImage: "arrow.right") { go(.name) }
        }
        .onAppear { withAnimation(Theme.bouncy.delay(0.15)) { wave = true } }
    }

    private func feature(_ icon: String, _ text: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 56, height: 56)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(text).font(.rounded(.caption, weight: .semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @FocusState private var nameFocused: Bool

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            backButton(to: .welcome)
            Text("你叫什么名字？")
                .font(.hanzi(34, weight: .bold))
            Text("What's your name? (nǐ jiào shénme míngzi?)")
                .font(.rounded(.body)).foregroundStyle(.secondary)
            TextField("Your name", text: $name)
                .font(.rounded(.title2, weight: .semibold))
                .padding(18)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.next)
                .onSubmit { go(.claim) }
            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 10) {
                    Text("我叫\(name)。")
                        .font(.hanzi(22, weight: .semibold))
                    SpeakButton(text: "我叫\(name)。", size: 36)
                }
                .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                Text("That's how you say “My name is \(name).”").font(.rounded(.footnote)).foregroundStyle(.secondary)
            }
            Spacer()
            BigButton(title: "Next", systemImage: "arrow.right",
                      enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) { go(.claim) }
        }
        .animation(Theme.bouncy, value: name.isEmpty)
        .onAppear { nameFocused = true }
    }

    private let claims: [(String, String, String)] = [
        ("🌱", "Total beginner", "I'm starting from zero"),
        ("🐣", "I know a few words", "你好, 谢谢, 再见…"),
        ("🎋", "Basic conversations", "I can order food and chat a bit"),
        ("🐼", "Getting comfortable", "I can talk about my day and plans"),
        ("🐉", "Pretty confident", "I hold real conversations"),
    ]

    private var claimStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if retakeOnly {
                Button("Cancel") { onRetakeDone?() }.font(.rounded(.headline))
            } else {
                backButton(to: .name)
            }
            Text("How's your Chinese?")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Pick what feels right. Then we'll confirm it with a quick quiz.")
                .font(.rounded(.body)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(claims.indices, id: \.self) { i in
                        Button {
                            withAnimation(Theme.bouncy) { claimed = i }
                        } label: {
                            HStack(spacing: 14) {
                                Text(claims[i].0).font(.system(size: 34))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(claims[i].1).font(.rounded(.headline, weight: .bold))
                                    Text(claims[i].2).font(.rounded(.subheadline)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: claimed == i ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(claimed == i ? Theme.red : Color.secondary.opacity(0.4))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(16)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(claimed == i ? Theme.red : .clear, lineWidth: 2.5))
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .sensoryFeedback(.selection, trigger: claimed)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            if claimed == 0 {
                BigButton(title: "Start from the beginning", systemImage: "leaf.fill", gradient: Theme.jadeGradient) {
                    confirmed = 0
                    finishPlacement()
                }
                Button("Actually, test me anyway") { startQuiz() }
                    .font(.rounded(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
            } else {
                BigButton(title: "Confirm my level", systemImage: "checkmark.seal.fill") { startQuiz() }
            }
        }
    }

    private func startQuiz() {
        questions = Placement.questions()
        results = []
        go(.quiz)
    }

    private var quizStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                backButton(to: .claim)
                Spacer()
                let level = questions.isEmpty ? 1 : questions[min(results.count, questions.count - 1)].word.level
                Pill(text: "Level \(level) check", color: Theme.levelColor(level), systemImage: "checkmark.seal")
                    .contentTransition(.numericText())
                    .animation(Theme.spring, value: level)
            }
            QuizRunner(
                questions: questions,
                onAnswer: { q, right in results.append((level: q.word.level, right: right)) },
                shouldContinue: { answered in
                    // after each block of 3, stop if that level wasn't passed
                    guard answered % 3 == 0 else { return true }
                    let level = questions[answered - 1].word.level
                    return results.filter { $0.level == level && $0.right }.count >= 2
                },
                onDone: { _ in
                    confirmed = Placement.confirmedLevel(results: results)
                    go(.result)
                    if confirmed > 0 {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            confetti += 1
                        }
                    }
                })
        }
    }

    private var resultStep: some View {
        VStack(spacing: 22) {
            Spacer()
            ProgressRing(progress: Double(confirmed) / 4, lineWidth: 16, gradient: [Theme.jade, Theme.gold, Theme.red]) {
                VStack(spacing: 2) {
                    Text(confirmed == 0 ? "🌱" : ["", "🐣", "🎋", "🐼", "🐉"][confirmed]).font(.system(size: 54))
                    Text(confirmed == 0 ? "Fresh start" : "HSK \(confirmed)")
                        .font(.rounded(.headline, weight: .heavy))
                }
            }
            .frame(width: 190, height: 190)

            Text(resultTitle)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(resultSubtitle)
                .font(.rounded(.body)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !results.isEmpty {
                Text("\(results.filter(\.right).count) of \(results.count) correct")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            BigButton(title: retakeOnly ? "Save level" : "Sounds good", systemImage: "arrow.right") {
                finishPlacement()
            }
            Button("Retake the quiz") { startQuiz() }
                .font(.rounded(.subheadline, weight: .semibold))
        }
    }

    private var resultTitle: String {
        if confirmed > claimed { return "You're better than you think! 🎉" }
        if confirmed == claimed { return confirmed == 0 ? "Let's begin together" : "Confirmed! 太棒了" }
        return "Let's build a solid base"
    }

    private var resultSubtitle: String {
        let start = min(confirmed + 1, 4)
        if confirmed >= 4 { return "You know all four levels. We'll keep you sharp with level 4 words and reviews." }
        return "You'll get new words from level \(start) (\(WordBank.levelTitle(start))) and climb from there."
    }

    private func finishPlacement() {
        if retakeOnly {
            store.profile.claimedLevel = claimed
            store.profile.confirmedLevel = confirmed
            store.save()
            onRetakeDone?()
        } else {
            go(.goal)
        }
    }

    private struct Goal { let count: Int; let label: String; let emoji: String }
    private let goals = [Goal(count: 3, label: "Chill", emoji: "☕️"),
                         Goal(count: 5, label: "Steady", emoji: "🚶"),
                         Goal(count: 8, label: "Intense", emoji: "🚀")]

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            backButton(to: .result)
            Text("Your daily goal")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("How many new words a day?").font(.rounded(.body)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(goals, id: \.count) { g in
                    Button { withAnimation(Theme.bouncy) { goal = g.count } } label: {
                        VStack(spacing: 6) {
                            Text(g.emoji).font(.system(size: 34))
                            Text("\(g.count)").font(.rounded(.title, weight: .heavy))
                            Text(g.label).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(goal == g.count ? Theme.red : .clear, lineWidth: 2.5))
                        .scaleEffect(goal == g.count ? 1.03 : 1)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .sensoryFeedback(.selection, trigger: goal)

            VStack(spacing: 0) {
                Toggle(isOn: $reminder) {
                    Label("Daily reminder", systemImage: "bell.badge.fill").font(.rounded(.headline))
                }
                .padding(16)
                if reminder {
                    Divider().padding(.leading, 16)
                    DatePicker("Remind me at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .font(.rounded(.body))
                        .padding(16)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .animation(Theme.spring, value: reminder)

            Spacer()
            BigButton(title: "Let's go, \(name)!", systemImage: "sparkles") { finish() }
        }
    }

    private func finish() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        var p = store.profile
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.claimedLevel = claimed
        p.confirmedLevel = confirmed
        p.dailyGoal = goal
        p.reminderOn = reminder
        p.reminderHour = c.hour ?? 19
        p.reminderMinute = c.minute ?? 0
        p.onboarded = true
        store.profile = p
        store.save()
        if reminder {
            let name = p.name
            Task { _ = await Reminders.schedule(hour: p.reminderHour, minute: p.reminderMinute, name: name) }
        }
    }
}
