import SwiftUI

/// Runs a list of multiple-choice questions, one at a time.
struct QuizRunner: View {
    let questions: [QuizQuestion]
    var showProgress = true
    var onAnswer: (QuizQuestion, Bool) -> Void = { _, _ in }
    /// Return false to stop early (used by the adaptive placement test).
    var shouldContinue: (Int) -> Bool = { _ in true }
    var onDone: (Int) -> Void

    @State private var index = 0
    @State private var picked: Word?
    @State private var correct = 0
    @State private var shake: CGFloat = 0
    @State private var rightTick = 0
    @State private var wrongTick = 0

    private var q: QuizQuestion? { index < questions.count ? questions[index] : nil }

    var body: some View {
        VStack(spacing: 20) {
            if showProgress {
                ProgressView(value: Double(index), total: Double(max(questions.count, 1)))
                    .tint(Theme.red)
                    .animation(Theme.spring, value: index)
            }
            if let q {
                VStack(spacing: 20) {
                    Text(q.prompt)
                        .font(.rounded(.headline, weight: .semibold))
                        .foregroundStyle(.secondary)
                    promptView(q)
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .cardSurface()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(q.options) { option in
                            optionButton(option, q: q)
                        }
                    }
                    .modifier(ShakeEffect(amount: shake))
                    Spacer(minLength: 0)
                    if let picked {
                        feedback(q, right: picked.id == q.word.id)
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
        .onAppear { autoplay() }
    }

    @ViewBuilder
    private func promptView(_ q: QuizQuestion) -> some View {
        switch q.kind {
        case .hanziToMeaning:
            VStack(spacing: 10) {
                Text(q.word.hanzi).font(.hanzi(72, weight: .semibold)).minimumScaleFactor(0.5).lineLimit(1)
                SpeakButton(text: q.word.hanzi, size: 40)
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

    private func optionButton(_ option: Word, q: QuizQuestion) -> some View {
        let isAnswer = option.id == q.word.id
        let isPicked = picked?.id == option.id
        let revealed = picked != nil
        let bg: Color = !revealed ? Theme.card : isAnswer ? Theme.jade.opacity(0.2) : isPicked ? Theme.red.opacity(0.18) : Theme.card
        let border: Color = !revealed ? .primary.opacity(0.08) : isAnswer ? Theme.jade : isPicked ? Theme.red : .primary.opacity(0.05)
        let isHanzi = q.kind != .hanziToMeaning
        return Button {
            guard picked == nil else { return }
            let right = isAnswer
            withAnimation(Theme.bouncy) { picked = option }
            if right {
                correct += 1
                rightTick += 1
            } else {
                wrongTick += 1
                withAnimation(.linear(duration: 0.4)) { shake += 1 }
            }
            onAnswer(q, right)
        } label: {
            Text(q.label(for: option))
                .font(isHanzi ? .hanzi(30, weight: .medium) : .rounded(.headline, weight: .semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 74)
                .padding(.horizontal, 8)
                .background(bg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(border, lineWidth: 2.5))
                .opacity(revealed && !isAnswer && !isPicked ? 0.5 : 1)
                .scaleEffect(revealed && isAnswer ? 1.04 : 1)
        }
        .buttonStyle(PressableStyle())
    }

    private func feedback(_ q: QuizQuestion, right: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(right ? ["太好了!", "对了!", "厉害!", "Nice!"][index % 4] : "Almost!")
                    .font(.rounded(.title3, weight: .heavy))
                    .foregroundStyle(right ? Theme.jade : Theme.red)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(q.word.hanzi) · \(q.word.pinyin)").font(.rounded(.subheadline, weight: .bold))
                    Text(q.word.meaning).font(.rounded(.footnote)).foregroundStyle(.secondary)
                }
            }
            BigButton(title: index + 1 < questions.count ? "Continue" : "Finish",
                      gradient: right ? Theme.jadeGradient : Theme.warmGradient) { next() }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func next() {
        let answered = index + 1
        if answered >= questions.count || !shouldContinue(answered) {
            onDone(correct)
            return
        }
        withAnimation(Theme.spring) {
            picked = nil
            index += 1
        }
        autoplay()
    }

    private func autoplay() {
        if let q, q.kind == .listenToHanzi {
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
