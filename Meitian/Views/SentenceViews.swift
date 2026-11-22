import SwiftUI

// MARK: - Tappable sentence

/// A sentence shown word by word, with pinyin over each word. Tap a word to see what it means.
struct TokenSentence: View {
    let tokens: [Token]
    var size: CGFloat = 24
    var alignment: HorizontalAlignment = .leading
    /// Index of a token to show as a blank (fill-the-gap).
    var gap: Int? = nil
    var gapFill: String? = nil
    var forcePinyin = false

    @AppStorage(PinyinPrefs.show) private var showPinyin = true
    @Environment(AppStore.self) private var store
    @State private var peek: PeekWord?

    var body: some View {
        FlowLayout(spacing: size * 0.12, lineSpacing: size * 0.3, alignment: alignment) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { i, t in
                tokenView(t, index: i)
            }
        }
        .sheet(item: $peek) { p in
            WordPeekSheet(word: p.word)
                .environment(store)
                .presentationDetents([.height(300)])
                .presentationCornerRadius(28)
        }
    }

    @ViewBuilder
    private func tokenView(_ t: Token, index: Int) -> some View {
        let isGap = gap == index
        let pinyinVisible = (showPinyin || forcePinyin) && !t.pinyin.isEmpty && !isGap
        VStack(spacing: 1) {
            if showPinyin || forcePinyin {
                let font = Font.system(size: max(size * 0.42, 11), weight: .semibold, design: .rounded)
                if t.isNew && pinyinVisible {
                    PinyinText(pinyin: t.pinyin, font: font).lineLimit(1).fixedSize()
                } else {
                    Text(pinyinVisible ? t.pinyin : " ")
                        .font(font)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if isGap {
                Text(gapFill ?? String(repeating: "＿", count: max(t.text.count, 1)))
                    .font(.hanzi(size, weight: .semibold))
                    .foregroundStyle(gapFill == nil ? Color.secondary : Theme.jade)
                    .padding(.horizontal, 4)
                    .background(Theme.gold.opacity(gapFill == nil ? 0.18 : 0), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text(t.text).font(.hanzi(size, weight: .medium))
                    .underline(t.wordId != nil && !t.isNew, pattern: .dot, color: Color.secondary.opacity(0.5))
                    .modifier(NewWordMark(on: t.isNew))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isGap, !t.pinyin.isEmpty else { return }
            if let core = lookupToken(text: t.text) {
                peek = PeekWord(word: Word(core))
            } else {
                Speaker.shared.say(t.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isGap ? "blank" : "\(t.isNew ? "new word, " : "")\(t.text) \(t.pinyin)")
    }
}

private struct PeekWord: Identifiable {
    let word: Word
    var id: String { word.id }
}

/// Small sheet for tap-a-word: characters, pinyin, meaning, audio, and "add to review".
struct WordPeekSheet: View {
    @Environment(AppStore.self) private var store
    let word: Word

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text(word.hanzi).font(.hanzi(56, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    PinyinText(pinyin: word.pinyin, font: .rounded(.title3, weight: .bold))
                    Text(word.meaning).font(.rounded(.body)).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                SpeakButton(text: word.hanzi, size: 48)
                Spacer()
                if store.cards[word.id] == nil {
                    Button {
                        store.addToReview([word])
                    } label: {
                        Label("Add to review", systemImage: "plus.circle.fill")
                            .font(.rounded(.headline, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.jade)
                } else {
                    Label("In your reviews", systemImage: "checkmark.circle.fill")
                        .font(.rounded(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.jade)
                }
            }
            Text(word.levelLabel).font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .onAppear { Speaker.shared.say(word.hanzi) }
    }
}

/// More example sentences for a word (from the downloaded sentence packs).
struct ExampleSentences: View {
    let word: Word
    @State private var sentences: [Sentence] = []

    var body: some View {
        Group {
            if !sentences.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("More examples").font(.rounded(.headline, weight: .bold))
                    ForEach(Array(sentences.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                TokenSentence(tokens: s.tokens, size: 20)
                                Spacer(minLength: 8)
                                SpeakButton(text: s.zh, size: 34, tint: Theme.jade)
                            }
                            Text(s.en).font(.rounded(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
        .task(id: WordBank.store.all.count) {
            sentences = sentencesForWord(wordId: word.id, limit: 4).filter { $0.zh != word.example }
        }
    }
}

// MARK: - Sentence lesson

/// Sentence exercises: build the sentence, fill the gap, listen, translate, read pinyin. From a node on the
/// learning path it's a lesson with hearts and only learned words; otherwise ten exercises of practice.
struct SentenceSession: View {
    var node: PathNode? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Indices into `exercises`; with hearts, wrong answers are asked again at the end.
    @State private var queue: [Int] = []
    @State private var solved = 0
    @State private var hearts = Int(lessonHearts())
    @State private var failed = false
    @State private var gained = 0
    @State private var exercises: [Exercise] = []
    @State private var index = 0
    @State private var picked: Int?
    @State private var built: [Int] = []          // indices into tiles, in tap order
    @State private var result: Bool?
    @State private var correct = 0
    @State private var finished = false
    @State private var shake: CGFloat = 0
    @State private var confetti = 0
    @State private var rightTick = 0
    @State private var wrongTick = 0

    private var ex: Exercise? { index < queue.count ? exercises[queue[index]] : nil }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                header
                if failed {
                    OutOfHeartsView(onRetry: start, onQuit: { dismiss() }).transition(.opacity)
                } else if finished {
                    results.transition(.scale(scale: 0.9).combined(with: .opacity))
                } else if let ex {
                    exerciseView(ex)
                        .id(index)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    Spacer()
                    Text("No sentences yet. Connect to the internet once to download lessons.")
                        .font(.rounded(.body)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(20)
            ConfettiView(trigger: confetti)
        }
        .sensoryFeedback(.success, trigger: rightTick)
        .sensoryFeedback(.error, trigger: wrongTick)
        .onAppear {
            if exercises.isEmpty { start() }
        }
    }

    /// (Re)starts from scratch. A node gives the same lesson again on a retry.
    private func start() {
        if let node {
            exercises = sentenceNodeLesson(unit: node.unit, number: node.number, dayKey: store.todayKey,
                                           knownWordIds: store.known, unitWordIds: store.unitWordIds(Int(node.unit)),
                                           canListen: Prefs.canListen)
        } else {
            exercises = sentenceLesson(maxLevel: UInt8(clamping: store.currentLevel), knownWordIds: store.known, count: 10,
                                       seed: UInt64.random(in: 0...UInt64.max), canListen: Prefs.canListen)
        }
        queue = Array(exercises.indices)
        index = 0
        picked = nil
        built = []
        result = nil
        correct = 0
        solved = 0
        hearts = Int(lessonHearts())
        withAnimation(Theme.spring) { failed = false }
        presented()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .foregroundStyle(.primary)
            .accessibilityLabel("Close")
            let done = min(node != nil ? solved : index, max(exercises.count, 1))
            ProgressView(value: Double(done), total: Double(max(exercises.count, 1)))
                .tint(Theme.jade)
                .animation(Theme.spring, value: done)
            if node != nil { HeartsBar(hearts: hearts) }
        }
    }

    private func title(_ kind: ExerciseKind) -> String {
        switch kind {
        case .wordOrder: return "Build the sentence"
        case .fillGap: return "Fill the gap"
        case .listenPick: return "What did you hear?"
        case .translatePick: return "What does it mean?"
        case .pinyinPick: return "Which one is it?"
        }
    }

    @ViewBuilder
    private func exerciseView(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title(ex.kind)).font(.rounded(.title2, weight: .bold))
            prompt(ex)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                .cardSurface()
            if ex.kind == .wordOrder {
                wordOrder(ex)
            } else {
                options(ex)
            }
            Spacer(minLength: 0)
            if let result {
                feedback(ex, right: result).transition(.move(edge: .bottom).combined(with: .opacity))
            } else if ex.kind == .wordOrder {
                BigButton(title: "Check", systemImage: "checkmark", gradient: Theme.jadeGradient,
                          enabled: built.count == ex.tiles.count) { check(ex) }
            }
        }
    }

    @ViewBuilder
    private func prompt(_ ex: Exercise) -> some View {
        let s = ex.sentence
        switch ex.kind {
        case .wordOrder:
            VStack(alignment: .leading, spacing: 10) {
                Text("“\(s.en)”").font(.rounded(.title3, weight: .semibold))
                SpeakButton(text: s.zh, size: 40, tint: Theme.sky)
            }
        case .fillGap:
            VStack(alignment: .leading, spacing: 10) {
                TokenSentence(tokens: s.tokens, size: 26, gap: Int(ex.gap),
                              gapFill: result == nil ? nil : ex.options[Int(ex.answer)])
                Text(s.en).font(.rounded(.subheadline)).foregroundStyle(.secondary)
            }
        case .listenPick:
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    SpeakButton(text: s.zh, size: 84, tint: Theme.sky)
                    Button { Speaker.shared.say(s.zh, slow: true) } label: {
                        Label("Slower", systemImage: "tortoise.fill").font(.rounded(.subheadline, weight: .bold))
                    }
                    if result != nil { TokenSentence(tokens: s.tokens, size: 20, alignment: .center) }
                }
                Spacer()
            }
        case .translatePick:
            HStack(alignment: .top) {
                TokenSentence(tokens: s.tokens, size: 28)
                Spacer(minLength: 8)
                SpeakButton(text: s.zh, size: 38, tint: Theme.sky)
            }
        case .pinyinPick:
            VStack(alignment: .leading, spacing: 8) {
                PinyinText(pinyin: s.pinyin, font: .rounded(.title2, weight: .bold))
                if result != nil { Text(s.en).font(.rounded(.subheadline)).foregroundStyle(.secondary) }
            }
        }
    }

    private func options(_ ex: Exercise) -> some View {
        let hanziOptions = ex.kind == .fillGap || ex.kind == .pinyinPick
        return VStack(spacing: 10) {
            ForEach(Array(ex.options.enumerated()), id: \.offset) { i, text in
                Button { choose(i, ex) } label: {
                    Text(text)
                        .font(hanziOptions ? .hanzi(22, weight: .medium) : .rounded(.body, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(optionColor(i, ex), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(picked == i ? Theme.ink : Color.secondary.opacity(0.2), lineWidth: picked == i ? 2 : 1))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .foregroundStyle(.primary)
                .disabled(result != nil)
            }
        }
        .modifier(ShakeEffect(amount: shake))
    }

    private func optionColor(_ i: Int, _ ex: Exercise) -> Color {
        guard result != nil else { return Theme.card }
        if i == Int(ex.answer) { return Theme.jade.opacity(0.25) }
        if i == picked { return Theme.red.opacity(0.22) }
        return Theme.card
    }

    private func wordOrder(_ ex: Exercise) -> some View {
        let newTexts = Set(ex.sentence.tokens.filter(\.isNew).map(\.text))
        return VStack(alignment: .leading, spacing: 16) {
            // answer line
            FlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(built, id: \.self) { i in
                    tile(ex.tiles[i], isNew: newTexts.contains(ex.tiles[i])) {
                        guard result == nil else { return }
                        withAnimation(Theme.bouncy) { built.removeAll { $0 == i } }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1) }
            .modifier(ShakeEffect(amount: shake))
            // tile bank
            FlowLayout(spacing: 8, lineSpacing: 10, alignment: .center) {
                ForEach(Array(ex.tiles.enumerated()), id: \.offset) { i, text in
                    tile(text, used: built.contains(i), isNew: newTexts.contains(text)) {
                        guard result == nil, !built.contains(i) else { return }
                        Speaker.shared.say(text)
                        withAnimation(Theme.bouncy) { built.append(i) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tile(_ text: String, used: Bool = false, isNew: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.hanzi(24, weight: .medium))
                .modifier(NewWordMark(on: isNew && !used))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(used ? Color.secondary.opacity(0.12) : Theme.card,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(used ? 0 : 0.35), lineWidth: 1))
                .foregroundStyle(used ? Color.clear : Color.primary)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(used)
        .accessibilityLabel(isNew ? "new word, \(text)" : text)
    }

    private func feedback(_ ex: Exercise, right: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(right ? "Nice! 对了" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.rounded(.title3, weight: .bold))
                .foregroundStyle(right ? Theme.jade : Theme.red)
            if !right || ex.kind == .wordOrder {
                TokenSentence(tokens: ex.sentence.tokens, size: 20, forcePinyin: true)
                Text(ex.sentence.en).font(.rounded(.subheadline)).foregroundStyle(.secondary)
            }
            BigButton(title: "Continue", systemImage: "arrow.right",
                      gradient: right ? Theme.jadeGradient : Theme.warmGradient) { next() }
        }
    }

    private var results: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressRing(progress: exercises.isEmpty ? 0 : Double(correct) / Double(exercises.count), lineWidth: 16,
                         gradient: [Theme.jade, Theme.sky]) {
                Text("\(correct)/\(exercises.count)").font(.rounded(.largeTitle, weight: .heavy))
            }
            .frame(width: 180, height: 180)
            Text(correct * 2 >= exercises.count ? "You're reading real Chinese! 厉害 lìhai!" : "Sentences are hard. 加油 jiāyóu!")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(node != nil && gained == 0 ? "replay · no XP" : "+\(gained) XP").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.gold)
            Spacer()
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
    }

    // MARK: actions

    private func choose(_ i: Int, _ ex: Exercise) {
        guard result == nil else { return }
        picked = i
        finish(right: i == Int(ex.answer), ex)
    }

    private func check(_ ex: Exercise) {
        let attempt = built.map { ex.tiles[$0] }
        finish(right: wordOrderCorrect(sentence: ex.sentence, attempt: attempt), ex)
    }

    private func finish(right: Bool, _ ex: Exercise) {
        withAnimation(Theme.spring) { result = right }
        if right {
            solved += 1
            if index < exercises.count { correct += 1 }   // first try
            rightTick += 1
            SFX.shared.play(.correct)
            if ex.kind != .listenPick { Speaker.shared.say(ex.sentence.zh) }
        } else {
            wrongTick += 1
            SFX.shared.play(.wrong)
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            if node != nil {
                hearts = Int(loseHeart(hearts: UInt32(hearts)))
                queue.append(queue[index])
            }
        }
    }

    private func next() {
        if node != nil && lessonFailed(hearts: UInt32(hearts)) {
            withAnimation(Theme.spring) { failed = true }
            return
        }
        if index + 1 >= queue.count {
            if let node {
                gained = store.finishPathSentences(number: Int(node.number))
            } else {
                gained = correct * 4
                store.addXP(gained)
                store.count(.sentences)
            }
            withAnimation(Theme.bouncy) { finished = true }
            if correct > 0 { confetti += 1; SFX.shared.play(.win) }
            return
        }
        withAnimation(Theme.spring) {
            index += 1
            picked = nil
            built = []
            result = nil
        }
        presented()
    }

    /// The current exercise just came up.
    private func presented() {
        if let ex { store.markSeen(ex.sentence.tokens.newIds) }
        autoplay()
    }

    private func autoplay() {
        guard let ex, ex.kind == .listenPick else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Speaker.shared.say(ex.sentence.zh) }
    }
}
