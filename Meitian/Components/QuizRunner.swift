import SwiftUI

/// Runs a list of questions one at a time: multiple choice, listening and speaking. With `useHearts` every wrong
/// answer costs a heart and comes back at the end until it's right; `onFailed` runs when the hearts are gone.
/// `onDone` gets the number of questions that were right the first time.
struct QuizRunner: View {
    let questions: [QuizQuestion]
    var showProgress = true
    /// Off for the placement test, which checks whether you can read characters.
    var allowPinyin = true
    var onAnswer: (QuizQuestion, Bool) -> Void = { _, _ in }
    /// Return false to stop early (used by the adaptive placement test).
    var shouldContinue: (Int) -> Bool = { _ in true }
    /// Lessons only: not for practice, tests or battles.
    var useHearts = false
    var onFailed: () -> Void = {}
    /// Off for the placement test.
    var tagNew = true
    var onDone: (Int) -> Void

    @State private var items: [QuizQuestion] = []
    @State private var index = 0
    @State private var picked: Word?
    @State private var answered: Bool?
    @State private var correct = 0
    @State private var shake: CGFloat = 0
    @State private var rightTick = 0
    @State private var wrongTick = 0
    @State private var listener = SpeechListener()
    @State private var speakTries = 0
    @State private var hearts = Int(lessonHearts())
    @State private var solved = 0
    @State private var newIds: Set<String> = []
    @Environment(AppStore.self) private var store
    @AppStorage(PinyinPrefs.show) private var showPinyin = true

    private var pinyinOn: Bool { allowPinyin && showPinyin }
    private var q: QuizQuestion? { index < items.count ? items[index] : nil }
    /// Questions after the original ones are wrong answers asked again.
    private var isRetry: Bool { index >= questions.count }
    private func isNew(_ q: QuizQuestion) -> Bool { !isRetry && newIds.contains(q.word.id) }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                if showProgress {
                    // with hearts the bar counts solved questions, so repeats don't push it back
                    let done = min(useHearts ? solved : index, max(questions.count, 1))
                    ProgressView(value: Double(done), total: Double(max(questions.count, 1)))
                        .tint(Theme.red)
                        .animation(Theme.spring, value: done)
                }
                if useHearts { HeartsBar(hearts: hearts) }
                pauseButton
            }
            if let q {
                VStack(spacing: 18) {
                    Text(q.prompt)
                        .font(.rounded(.headline, weight: .bold))
                        .textCase(.lowercase)
                        .foregroundStyle(.secondary)
                    promptView(q)
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .cardSurface()
                        .overlay(alignment: .topTrailing) {
                            if isNew(q) { NewBadge().padding(12) }
                        }
                    if q.kind == .speak {
                        speakControls(q)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(q.options) { option in optionButton(option, q: q) }
                        }
                        .modifier(ShakeEffect(amount: shake))
                    }
                    Spacer(minLength: 0)
                    if let answered {
                        feedback(q, right: answered)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .id(q.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .sensoryFeedback(.success, trigger: rightTick)
        .sensoryFeedback(.error, trigger: wrongTick)
        .onAppear {
            if items.isEmpty {
                if tagNew { newIds = store.newIds(questions.map(\.word)) }
                items = questions.map { $0.adjusted() }
                markSeen()
            }
            autoplay()
        }
        .onDisappear { listener.stop() }
        .onChange(of: listener.state) { _, s in
            guard let q, q.kind == .speak, answered == nil else { return }
            if s == .matched { answer(q, right: true) }
            if s == .missed { speakTries += 1 }
        }
    }

    // MARK: can't listen / speak now

    @ViewBuilder
    private var pauseButton: some View {
        if let q, answered == nil, q.kind == .listenToHanzi || q.kind == .speak {
            let listen = q.kind == .listenToHanzi
            Button {
                listener.reset()
                if listen { Prefs.pauseListening() } else { Prefs.pauseSpeaking() }
                // swap this and every later question to a silent type
                withAnimation(Theme.spring) {
                    for i in index..<items.count { items[i] = items[i].adjusted() }
                }
            } label: {
                Label(listen ? "Can't listen now" : "Can't speak now",
                      systemImage: listen ? "speaker.slash.fill" : "mic.slash.fill")
                    .font(.rounded(.caption, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.primary)
            .accessibilityHint("Pauses \(listen ? "listening" : "speaking") exercises for an hour")
        }
    }

    // MARK: prompt

    @ViewBuilder
    private func promptView(_ q: QuizQuestion) -> some View {
        switch q.kind {
        case .hanziToMeaning, .speak:
            VStack(spacing: 10) {
                if allowPinyin {
                    RubyText(hanzi: q.word.hanzi, pinyin: q.word.pinyin, size: q.word.hanzi.count > 3 ? 52 : 68,
                             weight: .semibold, alwaysShow: q.kind == .speak, alignment: .center)
                } else {
                    Text(q.word.hanzi).font(.hanzi(72, weight: .semibold)).minimumScaleFactor(0.5).lineLimit(1)
                }
                HStack(spacing: 10) {
                    SpeakButton(text: q.word.hanzi, size: 40)
                    if q.kind == .speak {
                        Text(q.word.shortMeaning).font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        case .meaningToHanzi:
            Text("“\(q.word.shortMeaning)”")
                .font(.rounded(.largeTitle, weight: .bold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
        case .listenToHanzi:
            SpeakButton(text: q.word.hanzi, size: 96, tint: Theme.sky)
        }
    }

    // MARK: speaking

    private func speakControls(_ q: QuizQuestion) -> some View {
        let listening = listener.state == .listening
        return VStack(spacing: 14) {
            Button {
                if listening { listener.stop() } else { listener.start(for: q.word) }
            } label: {
                ZStack {
                    Circle().fill(listening ? AnyShapeStyle(Theme.warmGradient) : AnyShapeStyle(Theme.card))
                    Circle().stroke(Theme.ink, lineWidth: 3)
                    Image(systemName: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(listening ? Color.white : Theme.red)
                        .symbolEffect(.variableColor.iterative, isActive: listening)
                }
                .frame(width: 104, height: 104)
                .scaleEffect(listening ? 1.08 : 1)
                .animation(Theme.bouncy, value: listening)
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(answered != nil)
            .accessibilityLabel(listening ? "Stop listening" : "Start speaking")

            Group {
                switch listener.state {
                case .listening: Text(listener.heard.isEmpty ? "Listening… say “\(q.word.hanzi)”" : "Heard: \(listener.heard)")
                case .missed: Text(!listener.problem.isEmpty ? listener.problem
                                   : listener.heard.isEmpty ? "Didn't catch that. Tap and try again." : "Heard “\(listener.heard)”. Try again!")
                case .denied: Text("Allow Microphone and Speech Recognition in Settings to use speaking.")
                case .unavailable: Text(listener.problem.isEmpty ? "Speech recognition isn't available right now." : listener.problem)
                default: Text("Tap the mic and say the word")
                }
            }
            .font(.rounded(.subheadline, weight: .semibold))
            .foregroundStyle(listener.state == .missed ? Theme.red : .secondary)
            .multilineTextAlignment(.center)

            if answered == nil && (speakTries >= 2 || listener.state == .denied || listener.state == .unavailable) {
                Button("Skip this one") { skip(q) }
                    .font(.rounded(.subheadline, weight: .bold))
            }
        }
    }

    // MARK: options

    private func optionButton(_ option: Word, q: QuizQuestion) -> some View {
        let isAnswer = option.id == q.word.id
        let isPicked = picked?.id == option.id
        let revealed = answered != nil
        let bg: Color = !revealed ? Theme.card : isAnswer ? Theme.jade.opacity(0.25) : isPicked ? Theme.red.opacity(0.22) : Theme.card
        let border: Color = !revealed ? Theme.ink : isAnswer ? Theme.jade : isPicked ? Theme.red : Theme.ink.opacity(0.3)
        let isHanzi = q.kind != .hanziToMeaning
        return Button {
            guard answered == nil else { return }
            withAnimation(Theme.bouncy) { picked = option }
            answer(q, right: isAnswer)
        } label: {
            VStack(spacing: 2) {
                Text(q.label(for: option))
                    .font(isHanzi ? .hanzi(30, weight: .medium) : .rounded(.headline, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if isHanzi && pinyinOn {
                    PinyinText(pinyin: option.pinyin, font: .rounded(.caption, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .padding(.horizontal, 8)
            .background(bg, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(border, lineWidth: 2.5))
            .opacity(revealed && !isAnswer && !isPicked ? 0.5 : 1)
            .scaleEffect(revealed && isAnswer ? 1.04 : 1)
        }
        .buttonStyle(PressableStyle())
    }

    private func answer(_ q: QuizQuestion, right: Bool) {
        guard answered == nil else { return }
        listener.stop()
        withAnimation(Theme.bouncy) { answered = right }
        if right {
            if !isRetry { correct += 1 }
            solved += 1
            rightTick += 1
            SFX.shared.play(.correct)
        } else {
            wrongTick += 1
            SFX.shared.play(.wrong)
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            if useHearts {
                hearts = Int(loseHeart(hearts: UInt32(hearts)))
                // asked again at the end until it's right
                items.append(q.again())
            }
        }
        onAnswer(q, right)
    }

    /// Can't speak here: with hearts, ask about the word silently instead of counting it as a mistake.
    private func skip(_ q: QuizQuestion) {
        guard useHearts else { answer(q, right: false); return }
        listener.reset()
        speakTries = 0
        withAnimation(Theme.spring) { items[index] = q.silent() }
    }

    private func markSeen() {
        if let q, isNew(q) { store.markSeen([q.word.id]) }
    }

    private func feedback(_ q: QuizQuestion, right: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(right ? ["太好了!", "对了!", "厉害!", "Nice!"][index % 4] : "Almost!")
                        .font(.rounded(.title3, weight: .heavy))
                        .foregroundStyle(right ? Theme.jade : Theme.red)
                    if right && index % 4 < 3 {
                        Text(["tài hǎo le · great", "duì le · correct", "lìhai · awesome"][index % 4])
                            .font(.rounded(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(q.word.hanzi) · \(q.word.pinyin)").font(.rounded(.subheadline, weight: .bold))
                    Text(q.word.meaning).font(.rounded(.footnote)).foregroundStyle(.secondary)
                }
            }
            BigButton(title: index + 1 < items.count ? "Continue" : "Finish",
                      gradient: right ? Theme.jadeGradient : Theme.warmGradient) { next() }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous).stroke(Theme.ink, lineWidth: 2.5))
    }

    private func next() {
        if useHearts && lessonFailed(hearts: UInt32(hearts)) {
            onFailed()
            return
        }
        let answeredCount = index + 1
        if answeredCount >= items.count || !shouldContinue(answeredCount) {
            onDone(correct)
            return
        }
        listener.reset()
        withAnimation(Theme.spring) {
            picked = nil
            answered = nil
            speakTries = 0
            index += 1
            items[index] = items[index].adjusted()
        }
        markSeen()
        autoplay()
    }

    private func autoplay() {
        if let q, q.kind == .listenToHanzi, Prefs.canListen {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                Speaker.shared.say(q.word.hanzi)
            }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}
