import SwiftUI

/// Two-sided word card. Front: character. Back: pinyin, meaning, example.
struct WordCardFace: View {
    let word: Word
    let flipped: Bool

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back.opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .top) {
            Theme.levelGradient(word.level)
                .frame(height: 8)
                .clipShape(Capsule())
                .padding(.horizontal, 60)
                .padding(.top, 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.ink, lineWidth: 3))
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.ink).offset(x: 5, y: 7))
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }

    private var front: some View {
        VStack(spacing: 18) {
            Pill(text: word.levelLabel, color: Theme.levelColor(word.level))
            Spacer()
            RubyText(hanzi: word.hanzi, pinyin: word.pinyin,
                     size: word.hanzi.count > 3 ? 56 : word.hanzi.count > 2 ? 68 : 96,
                     weight: .semibold, alignment: .center)
            SpeakButton(text: word.hanzi, size: 52)
            Spacer()
            Label("Tap to flip", systemImage: "hand.tap.fill")
                .font(.rounded(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }

    private var back: some View {
        VStack(spacing: 14) {
            HStack {
                Text(word.hanzi).font(.hanzi(40, weight: .semibold))
                Spacer()
                SpeakButton(text: word.hanzi)
            }
            VStack(alignment: .leading, spacing: 4) {
                PinyinText(pinyin: word.pinyin, font: .rounded(.title2, weight: .bold), color: Theme.levelColor(word.level))
                Text(word.meaning)
                    .font(.rounded(.title3, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if !word.example.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        RubyText(hanzi: word.example, pinyin: word.examplePinyin, size: 22, alwaysShow: true)
                        Spacer()
                        SpeakButton(text: word.example, size: 36, tint: Theme.jade)
                    }
                    Text(word.exampleMeaning).font(.rounded(.subheadline, weight: .medium))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(26)
        .padding(.top, 10)
    }
}

/// Tinder-style deck with 1:1 drag, momentum projection and velocity handoff.
/// Swipe right = got it, left = again (goes to the back of the deck).
struct SwipeDeck: View {
    let words: [Word]
    var onFinish: () -> Void
    var onSwipe: (Word, Bool) -> Void = { _, _ in }

    @State private var queue: [Word] = []
    @State private var offset: CGSize = .zero
    @State private var flipped = false
    @State private var feedbackKnown = 0
    @State private var feedbackAgain = 0
    @State private var started = false
    @State private var flipTick = 0

    private let commitDistance: CGFloat = 120

    var body: some View {
        VStack(spacing: 22) {
            progressDots
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(queue.prefix(3).enumerated().reversed()), id: \.element.id) { index, word in
                        card(word, index: index, width: geo.size.width)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
        }
        .onAppear {
            if !started { queue = words; started = true }
        }
        .sensoryFeedback(.success, trigger: feedbackKnown)
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackAgain)
        .sensoryFeedback(.selection, trigger: flipTick)
    }

    private var progressDots: some View {
        let done = words.count - Set(queue.map(\.id)).count
        return HStack(spacing: 6) {
            ForEach(0..<words.count, id: \.self) { i in
                Capsule()
                    .fill(i < done ? AnyShapeStyle(Theme.jadeGradient) : AnyShapeStyle(Color.primary.opacity(0.1)))
                    .frame(height: 6)
            }
        }
        .animation(Theme.spring, value: done)
    }

    @ViewBuilder
    private func card(_ word: Word, index: Int, width: CGFloat) -> some View {
        let isTop = index == 0
        let drag = isTop ? offset : .zero
        let progress = min(abs(drag.width) / commitDistance, 1)
        WordCardFace(word: word, flipped: isTop && flipped)
            .overlay(alignment: .topLeading) {
                stamp("GOT IT", color: Theme.jade, angle: -14)
                    .opacity(isTop && drag.width > 0 ? Double(progress) : 0)
                    .padding(28)
            }
            .overlay(alignment: .topTrailing) {
                stamp("AGAIN", color: Theme.gold, angle: 14)
                    .opacity(isTop && drag.width < 0 ? Double(progress) : 0)
                    .padding(28)
            }
            .scaleEffect(isTop ? 1 : 1 - CGFloat(index) * 0.05 + (index == 1 ? 0.05 * progress : 0))
            .offset(y: isTop ? 0 : CGFloat(index) * 16 - (index == 1 ? 16 * progress : 0))
            .offset(drag)
            .rotationEffect(.degrees(Double(drag.width / 18)), anchor: .bottom)
            .allowsHitTesting(isTop)
            .onTapGesture {
                flipTick += 1
                withAnimation(Theme.bouncy) { flipped.toggle() }
            }
            .gesture(dragGesture(word, width: width))
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Got it") { commit(word, known: true, width: width, velocity: 0) }
            .accessibilityAction(named: "Again") { commit(word, known: false, width: width, velocity: 0) }
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.rounded(.title2, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }

    private func dragGesture(_ word: Word, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // 1:1 tracking, no animation while the finger is down
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { offset = value.translation }
            }
            .onEnded { value in
                // project where the flick is going, then decide
                let projected = value.predictedEndTranslation.width
                let vx = value.velocity.width
                if abs(projected) > commitDistance * 1.6 || abs(value.translation.width) > commitDistance {
                    commit(word, known: projected > 0, width: width, velocity: vx)
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 22, initialVelocity: 0)) {
                        offset = .zero
                    }
                }
            }
    }

    private func commit(_ word: Word, known: Bool, width: CGFloat, velocity: CGFloat) {
        let dir: CGFloat = known ? 1 : -1
        if known { feedbackKnown += 1 } else { feedbackAgain += 1 }
        SFX.shared.play(.swoosh)
        onSwipe(word, known)
        let target = dir * (width + 200)
        let distance = max(abs(target - offset.width), 1)
        let relVelocity = abs(velocity) / distance
        withAnimation(.interpolatingSpring(stiffness: 180, damping: 26, initialVelocity: relVelocity)) {
            offset = CGSize(width: target, height: offset.height + 40)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                flipped = false
                offset = .zero
                guard !queue.isEmpty else { return }
                let w = queue.removeFirst()
                if !known { queue.append(w) }
            }
            if queue.isEmpty { onFinish() }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                if let w = queue.first { commit(w, known: false, width: 400, velocity: 0) }
            } label: {
                Label("Again", systemImage: "arrow.uturn.backward")
                    .font(.rounded(.headline, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(Theme.gold)
                    .background(Theme.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            Button {
                if let w = queue.first { commit(w, known: true, width: 400, velocity: 0) }
            } label: {
                Label("Got it", systemImage: "checkmark")
                    .font(.rounded(.headline, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Theme.jadeGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .disabled(queue.isEmpty)
    }
}
