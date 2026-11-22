import SwiftUI

/// Today: the spins earned by finishing units and the won sentence, pinned above the path.
struct SlotCard: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @Environment(ContentSync.self) private var content
    @State private var machine = false
    @State private var lesson: SlotSentenceRef?

    var body: some View {
        // re-read once a pack arrives
        let sentence = content.generation >= 0 ? store.slotSentence : nil
        HStack(spacing: 8) {
            spinCard(left: store.spinsLeft)
            if let sentence { sentenceCard(sentence) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .fullScreenCover(isPresented: $machine) {
            SlotMachineView().environment(store).environment(arena).sheetSounds()
        }
        .fullScreenCover(item: $lesson) { ref in
            SentenceOfTheDayView(sentence: ref.sentence).environment(store)
        }
    }

    private func spinCard(left: Int) -> some View {
        let ready = left > 0
        let next = store.learnPath.first { $0.nodes.contains { $0.kind == .story && $0.state != .done } }?.number
        return Button { machine = true } label: {
            HStack(spacing: 10) {
                Text("🎰").font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(left == 1 ? "you have a spin!" : ready ? "you have \(left) spins!" : "next spin")
                        .font(.rounded(ready ? .subheadline : .caption, weight: .heavy))
                        .opacity(ready ? 1 : 0.6)
                    Text(ready ? "one for every finished unit" : next.map { "finish unit \($0)" } ?? "finish a unit")
                        .font(.rounded(ready ? .caption : .subheadline, weight: .bold))
                        .opacity(ready ? 0.7 : 1)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ready ? Color.black : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(ready ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func sentenceCard(_ sentence: Sentence) -> some View {
        let done = store.slots.sentenceDone
        return Button { lesson = SlotSentenceRef(sentence: sentence) } label: {
            HStack(spacing: 10) {
                Text(done ? "✅" : "📝").font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("bonus sentence").font(.rounded(.caption, weight: .heavy)).foregroundStyle(.secondary)
                    Text(done ? sentence.zh : "+\(spinSentenceXp()) XP").font(.rounded(.subheadline, weight: .bold))
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct SlotSentenceRef: Identifiable {
    let sentence: Sentence
    var id: UInt64 { sentence.id }
}

/// The slot machine: a free spin for every finished unit, and spins stack up.
struct SlotMachineView: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reels = ["🪙", "🎨", "📝"]
    @State private var popped: Int?
    @State private var leverDown = false
    @State private var glow = false
    @State private var busy = false
    @State private var won: SpinResult?
    @State private var confetti = 0
    @State private var stopTick = 0
    @State private var winTick = 0
    @State private var lesson: SlotSentenceRef?

    private let symbols = slotSymbols()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline.weight(.bold))
                            .frame(width: 40, height: 40)
                            .background(Theme.card, in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("lucky spin").font(.rounded(.title3, weight: .heavy))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                Spacer()
                HStack(spacing: 12) {
                    cabinet
                    lever
                }
                if let won { prizeView(won.prize) }
                Spacer()
                bottom(left: store.spinsLeft)
                Text("A free spin for every finished unit; they stack up. Coins, cosmetics and sentences only.")
                    .font(.rounded(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            ConfettiView(trigger: confetti, sound: nil)
        }
        .haptic(.impact(weight: .heavy), trigger: stopTick)
        .haptic(.success, trigger: winTick)
        .fullScreenCover(item: $lesson) { ref in
            SentenceOfTheDayView(sentence: ref.sentence).environment(store)
        }
    }

    private var cabinet: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Text(reels[i])
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(Color(red: 0.82, green: 0.01, blue: 0.11))
                    .scaleEffect(popped == i ? 1.35 : 1)
                    .frame(width: 78, height: 108)
                    .background(Color(red: 1, green: 0.97, blue: 0.91), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.gold, lineWidth: 3))
            }
        }
        .streetBlock(Theme.warmGradient, padding: 14)
        .scaleEffect(glow ? 1.12 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(won == nil ? "Slot machine" : "Reels: \(reels.joined(separator: " "))")
    }

    private var lever: some View {
        Button { spin() } label: {
            ZStack(alignment: .top) {
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 8, height: 110)
                Circle().fill(Theme.red).frame(width: 28, height: 28).offset(y: leverDown ? 80 : 0)
            }
            .frame(width: 28, height: 130)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || store.spinsLeft == 0)
        .accessibilityLabel("Pull the lever")
    }

    @ViewBuilder
    private func bottom(left: Int) -> some View {
        if busy {
            BigButton(title: "…", enabled: false) {}
        } else if left > 0 {
            VStack(spacing: 6) {
                if left > 1 { Text("\(left) spins left").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary) }
                BigButton(title: won == nil ? "spin! 🎰" : "spin again 🎰", gradient: Theme.goldGradient) { spin() }
            }
        } else {
            VStack(spacing: 6) {
                Text("finish a unit to earn another spin").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func prizeView(_ prize: SlotPrize) -> some View {
        VStack(spacing: 8) {
            switch prize {
            case .coins(let amount, let jackpot):
                if jackpot { Text("大奖！ JACKPOT!").font(.street(36)).foregroundStyle(Theme.red) }
                Text("+\(amount) 🪙").font(.street(jackpot ? 56 : 40)).foregroundStyle(Theme.gold)
            case .cosmetic(let id):
                if let item = Catalog.item(id) {
                    let on = arena.equipped(item.kind) == item.id
                    Text("new from the shop: \(item.kind.label.lowercased())").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                    Text("\(item.symbol) \(item.name)").font(.rounded(.title, weight: .heavy))
                    Button { withAnimation(Theme.bouncy) { arena.equip(item) } } label: {
                        Pill(text: on ? "equipped ✓" : "equip", color: on ? .secondary : Theme.jade)
                    }
                    .disabled(on)
                }
            case .sentence(let sentence):
                Text("a bonus sentence 📝").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                TokenSentence(tokens: sentence.tokens, size: 26, alignment: .center)
                BigButton(title: "learn it · +\(spinSentenceXp()) XP", gradient: Theme.jadeGradient) {
                    lesson = SlotSentenceRef(sentence: sentence)
                }
            }
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: spinning

    private func spin() {
        guard !busy else { return }
        busy = true
        won = nil
        stopTick += 1
        withAnimation(.easeIn(duration: 0.16)) { leverDown = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            withAnimation(Theme.bouncy) { leverDown = false }
        }
        Task { @MainActor in await run() }
    }

    @MainActor
    private func run() async {
        // the prize is decided and saved before the reels move
        guard let result = store.spin(arena: arena) else {
            busy = false
            return
        }
        if !reduceMotion { await roll(to: result.reels) }
        reels = result.reels
        withAnimation(Theme.bouncy) { won = result }
        busy = false
        winTick += 1
        var small = false
        var jackpot = false
        if case .coins(let amount, let isJackpot) = result.prize {
            small = amount <= 20
            jackpot = isJackpot
        }
        guard jackpot else {
            if !small { confetti += 1 }
            SFX.shared.play(small ? .coin : .win)
            return
        }
        SFX.shared.play(.jackpot)
        for _ in 0..<3 {
            confetti += 1
            winTick += 1
            withAnimation(Theme.bouncy) { glow = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(Theme.bouncy) { glow = false }
            try? await Task.sleep(for: .milliseconds(450))
        }
    }

    /// The reels run and stop one after the other.
    @MainActor
    private func roll(to target: [String]) async {
        let start = Date.now
        var stopped = 0
        var at = 0
        while stopped < 3 {
            for i in stopped..<3 { reels[i] = symbols[(at + i * 3) % symbols.count] }
            at += 1
            SFX.shared.play(.reelTick)
            if Date.now.timeIntervalSince(start) > 1.0 + 0.65 * Double(stopped) {
                let i = stopped
                stopped += 1
                reels[i] = target[i]
                stopTick += 1
                SFX.shared.play(.reelStop)
                popped = i
                withAnimation(Theme.bouncy) { popped = nil }
            }
            try? await Task.sleep(for: .milliseconds(75))
        }
        try? await Task.sleep(for: .milliseconds(250))
    }
}

/// A three-step mini-lesson: hear the sentence, build it, type it.
struct SentenceOfTheDayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sentence: Sentence

    @State private var step = 0
    @State private var wrong = false
    @State private var gained = 0
    @State private var confetti = 0
    @State private var tiles: [String] = []
    @State private var built: [Int] = []
    @State private var text = ""
    @State private var rightTick = 0
    @State private var wrongTick = 0
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.headline.weight(.bold))
                                .frame(width: 40, height: 40)
                                .background(Theme.card, in: Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Close")
                        Spacer()
                        Text("bonus sentence").font(.rounded(.headline, weight: .heavy))
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    Text(["1 · listen", "2 · build it", "3 · type the pinyin", "done! 完成了"][min(step, 3)])
                        .font(.rounded(.title2, weight: .heavy))
                    card
                    switch step {
                    case 0: BigButton(title: "got it", systemImage: "arrow.right", gradient: Theme.jadeGradient) { withAnimation(Theme.spring) { step = 1 } }
                    case 1: builder
                    case 2: typer
                    default: finished
                    }
                    if wrong {
                        Text("not quite, try again").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            ConfettiView(trigger: confetti, sound: nil)
        }
        .haptic(.success, trigger: rightTick)
        .haptic(.error, trigger: wrongTick)
        .onAppear {
            if tiles.isEmpty { tiles = shuffledTiles(sentence: sentence, seed: UInt64.random(in: 0...UInt64.max)) }
            store.markSeen(sentence.tokens.newIds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Speaker.shared.say(sentence.zh) }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Group {
                    switch step {
                    case 1: Text("“\(sentence.en)”").font(.rounded(.title3, weight: .semibold))
                    case 2: Text(sentence.zh).font(.hanzi(28))
                    default: TokenSentence(tokens: sentence.tokens, size: 28, forcePinyin: true)
                    }
                }
                Spacer(minLength: 8)
                SpeakButton(text: sentence.zh, size: 44, tint: Theme.sky)
            }
            if step == 0 || step >= 3 { Text(sentence.en).font(.rounded(.subheadline)).foregroundStyle(.secondary) }
            if step == 0 {
                Button { Speaker.shared.say(sentence.zh, slow: true) } label: {
                    Label("Slower", systemImage: "tortoise.fill").font(.rounded(.subheadline, weight: .bold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var builder: some View {
        VStack(spacing: 14) {
            FlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(built, id: \.self) { i in
                    tile(tiles[i]) { withAnimation(Theme.bouncy) { built.removeAll { $0 == i } } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1) }
            FlowLayout(spacing: 8, lineSpacing: 10, alignment: .center) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                    tile(t, used: built.contains(i)) {
                        Speaker.shared.say(t)
                        withAnimation(Theme.bouncy) { built.append(i) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            BigButton(title: "check", systemImage: "checkmark", gradient: Theme.jadeGradient, enabled: !tiles.isEmpty && built.count == tiles.count) {
                let right = wordOrderCorrect(sentence: sentence, attempt: built.map { tiles[$0] })
                if !right { withAnimation(Theme.spring) { built = [] } }
                answer(right)
            }
        }
    }

    private func tile(_ text: String, used: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.hanzi(24, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(used ? Color.secondary.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(used ? Color.clear : Color.primary)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(used)
    }

    private var typer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("pinyin, no tones needed", text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($typing)
                .font(.rounded(.title3, weight: .semibold))
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onSubmit { submit() }
                .onAppear { typing = true }
            BigButton(title: "check", systemImage: "checkmark", gradient: Theme.jadeGradient, enabled: !text.isEmpty) { submit() }
            if wrong { Text("hint: \(sentence.pinyin)").font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary) }
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Text(gained > 0 ? "+\(gained) XP" : "already done · no XP")
                .font(.rounded(.title, weight: .heavy))
                .foregroundStyle(gained > 0 ? Theme.gold : Color.secondary)
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard !text.isEmpty else { return }
        answer(pinyinTypedOk(typed: text, pinyin: sentence.pinyin))
    }

    private func answer(_ right: Bool) {
        withAnimation(Theme.spring) { wrong = !right }
        SFX.shared.play(right ? .correct : .wrong)
        guard right else { wrongTick += 1; return }
        rightTick += 1
        withAnimation(Theme.spring) { step += 1 }
        if step == 3 {
            typing = false
            gained = store.finishSlotSentence()
            confetti += 1
            SFX.shared.play(.win)
            Speaker.shared.say(sentence.zh)
        }
    }
}
