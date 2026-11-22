import SwiftUI

/// Hearts left in this lesson. Losing one breaks it (pop, sound, haptic).
struct HeartsBar: View {
    let hearts: Int
    /// The heart that's breaking right now.
    @State private var breaking: Int?
    @State private var pop = false
    @State private var lostTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let total = Int(lessonHearts())

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                let broken = breaking == i
                Text(symbol(i))
                    .font(.system(size: 17))
                    .scaleEffect(broken && pop ? 1.8 : 1)
                    .rotationEffect(.degrees(broken && pop ? -14 : 0))
            }
        }
        .fixedSize()
        .onChange(of: hearts) { old, new in
            if new < old { lose(new) }
        }
        .haptic(.error, trigger: lostTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hearts) of \(total) hearts left")
    }

    private func symbol(_ i: Int) -> String {
        if i < hearts { return "❤️" }
        return breaking == i ? "💔" : "🤍"
    }

    private func lose(_ index: Int) {
        lostTick += 1
        SFX.shared.play(.heartLost)
        breaking = index
        if !reduceMotion {
            withAnimation(Theme.bouncy) { pop = true }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(Theme.spring) { pop = false }
            try? await Task.sleep(for: .milliseconds(380))
            if breaking == index {
                withAnimation(Theme.spring) { breaking = nil }
            }
        }
    }
}

/// The lesson is over: start again from scratch.
struct OutOfHeartsView: View {
    var onRetry: () -> Void
    var onQuit: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("💔").font(.system(size: 100))
                .scaleEffect(shown || reduceMotion ? 1 : 0.3)
                .accessibilityHidden(true)
            Text("out of hearts 💔").font(.rounded(.largeTitle, weight: .heavy))
                .multilineTextAlignment(.center)
            Text("加油 jiāyóu! Start over with \(lessonHearts()) fresh hearts. This try doesn't count.")
                .font(.rounded(.body, weight: .semibold)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            BigButton(title: "Retry lesson", systemImage: "arrow.counterclockwise", gradient: Theme.warmGradient) { onRetry() }
            BigButton(title: "Not now") { onQuit() }
        }
        .haptic(.error, trigger: shown)
        .onAppear {
            SFX.shared.play(.outOfHearts)
            withAnimation(Theme.bouncy) { shown = true }
        }
    }
}
