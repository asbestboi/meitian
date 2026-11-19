import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    var goToChallenge: () -> Void
    var goToPractice: () -> Void
    @AppStorage(PinyinPrefs.show) private var showPinyin = true

    @State private var words: [Word] = []
    @State private var learning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    wordsCard
                    challengeCard
                    reviewCard
                    phraseOfTheDay
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
        }
        .onAppear { words = store.todaysWords() }
        .onChange(of: store.todayKey) { _, _ in words = store.todaysWords() }
        .onChange(of: store.profile.dailyGoal) { _, _ in words = store.todaysWords() }
        .fullScreenCover(isPresented: $learning) {
            LearnSession(words: words).environment(store)
        }
    }

    private var greeting: (hanzi: String, pinyin: String, english: String) {
        let h = Calendar.current.component(.hour, from: .now)
        if h < 11 { return ("早上好", "Zǎoshang hǎo", "Good morning") }
        if h < 14 { return ("中午好", "Zhōngwǔ hǎo", "Good noon") }
        if h < 18 { return ("下午好", "Xiàwǔ hǎo", "Good afternoon") }
        return ("晚上好", "Wǎnshang hǎo", "Good evening")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting.hanzi)，\(store.profile.name)")
                    .font(.hanzi(28, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    PinyinText(pinyin: greeting.pinyin, font: .rounded(.subheadline, weight: .bold))
                    Text("· \(greeting.english)").font(.rounded(.subheadline)).foregroundStyle(.secondary)
                }
                Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.rounded(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StreakBadge(streak: store.streak)
            XPBadge(xp: store.xp)
        }
        .padding(.top, 8)
    }

    private var wordsCard: some View {
        let done = store.today.learnedDone
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(done ? "Today's words · done" : "Today's words", systemImage: done ? "checkmark.seal.fill" : "sparkles")
                    .font(.rounded(.headline, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(words.count) words")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(words) { w in
                        VStack(spacing: 4) {
                            Text(w.hanzi).font(.hanzi(28, weight: .semibold))
                            if done || showPinyin {
                                PinyinText(pinyin: w.pinyin, font: .rounded(.caption, weight: .bold))
                            } else {
                                Text("?").font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minWidth: 64)
                        .padding(.vertical, 12).padding(.horizontal, 10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.primary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button { learning = true } label: {
                HStack {
                    Text(done ? "Practice them again" : "Learn today's words")
                    Spacer()
                    Image(systemName: done ? "arrow.clockwise" : "play.fill")
                }
                .font(.rounded(.headline, weight: .bold))
                .foregroundStyle(Theme.red)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .streetBlock(done ? Theme.jadeGradient : Theme.warmGradient)
        .overlay(alignment: .topTrailing) { TapeStrip(angle: 8).offset(x: -10, y: -10) }
    }

    private var challengeCard: some View {
        let done = store.today.challenge != nil
        let challenge = Challenge.make(dayKey: store.todayKey, words: words, friend: store.profile.preferredFriend)
        return Button(action: goToChallenge) {
            HStack(spacing: 16) {
                Text(done ? "🏆" : store.profile.preferredFriend.emoji)
                    .font(.system(size: 38))
                    .frame(width: 64, height: 64)
                    .background(Theme.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(done ? "Challenge complete!" : "Today's friend challenge")
                        .font(.rounded(.headline, weight: .bold))
                    Text(done ? "+50 XP earned. 你真棒！" : (challenge?.mission ?? "Learn today's words first."))
                        .font(.rounded(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .cardSurface(padding: 16)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var reviewCard: some View {
        let due = store.dueWords.count
        return Button(action: goToPractice) {
            HStack(spacing: 16) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title)
                    .foregroundStyle(Theme.sky)
                    .frame(width: 64, height: 64)
                    .background(Theme.sky.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(due > 0 ? "\(due) words to review" : "Reviews all caught up")
                        .font(.rounded(.headline, weight: .bold))
                    Text(due > 0 ? "Keep them fresh before they fade." : "\(store.learnedWords.count) words learned so far.")
                        .font(.rounded(.subheadline)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .cardSurface(padding: 16)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var phraseOfTheDay: some View {
        let c = Meitian.phraseOfTheDay(dayKey: store.todayKey)
        let p = (c.hanzi, c.pinyin, c.meaning)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Phrase of the day").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    RubyText(hanzi: p.0, pinyin: p.1, size: 30, weight: .bold, alwaysShow: true)
                    Text(p.2).font(.rounded(.subheadline))
                }
                Spacer()
                SpeakButton(text: p.0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Full-screen session: swipe through cards, then a quick quiz, then celebrate.
struct LearnSession: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let words: [Word]

    enum Phase { case cards, quiz, done }
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
                    QuizRunner(questions: questions, onDone: { correct in
                        score = correct
                        store.finishLearning(words, quizCorrect: correct)
                        withAnimation(Theme.bouncy) { phase = .done }
                        confetti += 1
                    })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                case .done:
                    done.transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(20)
            ConfettiView(trigger: confetti)
        }
        .sensoryFeedback(.success, trigger: confetti)
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
            Text("Now try today's challenge: use one of these words with a friend!")
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
