import SwiftUI

// MARK: - Shared pieces

/// Question + four options used by every battle mode.
struct DuelQuestionPanel: View {
    let question: QuizQuestion
    var picked: Word?
    var locked: Bool
    /// Show which option was right (after the round).
    var reveal: Bool
    var compact = false
    var onPick: (Word) -> Void

    @AppStorage(PinyinPrefs.show) private var showPinyin = true

    var body: some View {
        VStack(spacing: compact ? 10 : 16) {
            Group {
                if question.kind == .hanziToMeaning {
                    RubyText(hanzi: question.word.hanzi, pinyin: question.word.pinyin,
                             size: compact ? 42 : (question.word.hanzi.count > 3 ? 48 : 60),
                             weight: .semibold, alignment: .center)
                } else {
                    Text("“\(question.word.shortMeaning)”")
                        .font(.rounded(compact ? .title2 : .title, weight: .bold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 70 : 110)
            .padding(.vertical, compact ? 8 : 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .id(question.id)
            .transition(.scale(scale: 0.9).combined(with: .opacity))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(question.options) { option in optionButton(option) }
            }
        }
        .animation(Theme.bouncy, value: question.id)
    }

    private func optionButton(_ option: Word) -> some View {
        let isAnswer = option.id == question.word.id
        let isPicked = picked?.id == option.id
        let isHanzi = question.kind == .meaningToHanzi
        let bg: Color = reveal && isAnswer ? Theme.jade.opacity(0.22)
            : isPicked && !isAnswer ? Theme.red.opacity(0.2)
            : isPicked ? Theme.jade.opacity(0.22) : Theme.card
        let border: Color = reveal && isAnswer ? Theme.jade : isPicked ? (isAnswer ? Theme.jade : Theme.red) : .primary.opacity(0.08)
        return Button { onPick(option) } label: {
            VStack(spacing: 1) {
                Text(isHanzi ? option.hanzi : option.shortMeaning)
                    .font(isHanzi ? .hanzi(compact ? 24 : 28, weight: .medium) : .rounded(compact ? .subheadline : .headline, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if isHanzi && showPinyin {
                    PinyinText(pinyin: option.pinyin, font: .rounded(.caption2, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: compact ? 54 : 68)
            .padding(.horizontal, 6)
            .background(bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(border, lineWidth: 2.5))
            .opacity(locked && !isPicked && !(reveal && isAnswer) ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(locked || picked != nil)
    }
}

/// Health bar with avatar.
struct HealthBar: View {
    let name: String
    let avatar: String
    let hp: Int
    var tint: Color = Theme.jade
    var hitTick: Int = 0
    var aura: String? = nil

    @State private var shake: CGFloat = 0
    @State private var flashRed = false

    var body: some View {
        HStack(spacing: 10) {
            Text(avatar).font(.system(size: 30))
                .background { AuraView(auraId: aura ?? "au.none", radius: 20).frame(width: 90, height: 90) }
                .modifier(ShakeEffect(amount: shake))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.rounded(.subheadline, weight: .bold)).lineLimit(1)
                    Spacer()
                    Text("\(hp) HP").font(.rounded(.subheadline, weight: .heavy)).contentTransition(.numericText())
                        .foregroundStyle(hp <= 30 ? Theme.red : .primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(hp <= 30 ? AnyShapeStyle(Theme.warmGradient) : AnyShapeStyle(tint))
                            .frame(width: geo.size.width * CGFloat(hp) / CGFloat(DuelMatch.maxHP))
                    }
                }
                .frame(height: 12)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.red.opacity(flashRed ? 0.25 : 0)).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        .animation(Theme.bouncy, value: hp)
        .onChange(of: hitTick) { _, _ in
            // land the shake when the projectile arrives
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                withAnimation(.linear(duration: 0.45)) { shake += 1 }
                flashRed = true
                withAnimation(.easeOut(duration: 0.5)) { flashRed = false }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(hp) health")
    }
}

/// Big flying emoji when someone lands a hit.
struct HitBurst: View {
    let symbol: String
    let damage: Int
    let trigger: Int
    var towardTop: Bool

    @State private var visible = false
    @State private var travel: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            Text(symbol).font(.system(size: 80))
            Text("-\(damage)").font(.rounded(.largeTitle, weight: .black)).foregroundStyle(Theme.red)
        }
        .scaleEffect(visible ? 1.15 : 0.3)
        .offset(y: travel)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            travel = 0
            withAnimation(Theme.bouncy) { visible = true }
            withAnimation(.easeIn(duration: 0.45).delay(0.35)) { travel = towardTop ? -260 : 260 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.2)) { visible = false }
            }
        }
    }
}

private struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.headline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .foregroundStyle(.primary)
        .accessibilityLabel("Close")
    }
}

// MARK: - Online duel (QR pairing + Multipeer)

struct OnlineDuelView: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var connection: DuelConnection?
    @State private var match: DuelMatch?
    @State private var scanning = false
    @State private var scanMessage: String?
    @State private var confetti = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let match, let connection, match.opponent != nil {
                MatchScreen(match: match, confetti: $confetti, close: close)
                    .transition(.opacity)
                    .disabled(connection.state != .connected)
                    .blur(radius: connection.state == .connected ? 0 : 6)
                if connection.state != .connected {
                    ReconnectOverlay(connection: connection, name: match.opponent?.name ?? "your friend", leave: close)
                        .transition(.opacity)
                }
            } else {
                pairing
            }
            ConfettiView(trigger: confetti)
        }
        .animation(Theme.spring, value: match?.opponent)
        .animation(Theme.spring, value: connection?.state)
        .onAppear {
            setUp()
            UIApplication.shared.isIdleTimerDisabled = true // screen lock would cut the link
        }
        .onDisappear {
            connection?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { connection?.wake() }
        }
        .onChange(of: connection?.state) { _, s in
            if s == .connected { match?.sayHello() }
        }
        .sheet(isPresented: $scanning) { scanner }
    }

    private func setUp() {
        guard connection == nil else { return }
        let card = arena.card(name: store.profile.name, level: store.currentLevel, wordsLearned: store.cards.count)
        let c = DuelConnection(myId: arena.playerId, name: store.profile.name)
        let m = DuelMatch(connection: c, me: card)
        m.onFinish = { [arena, weak m] outcome, bonus, damage, fastest in
            guard let m, let opp = m.opponent else { return 0 }
            return arena.record(outcome, mode: m.mode, against: opp, bonus: bonus, damage: damage, fastest: fastest)
        }
        c.start()
        connection = c
        match = m
    }

    private func close() {
        connection?.stop()
        dismiss()
    }

    private var statusText: (String, Color) {
        switch connection?.state ?? .idle {
        case .connecting: return ("Connecting… keep the phones close", Theme.gold)
        case .connected: return ("Connected! Saying hello…", Theme.jade)
        case .reconnecting: return ("Reconnecting…", Theme.gold)
        default: return ("Waiting for your friend", .secondary)
        }
    }

    private var pairing: some View {
        VStack(spacing: 18) {
            HStack {
                CloseButton(action: close)
                Spacer()
                Text("Battle a friend").font(.rounded(.headline, weight: .bold))
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer(minLength: 0)
            if let card = match?.me {
                PlayerCardView(card: card, compact: true)
            }
            QRCodeView(text: DuelQR.payload(for: arena.playerId))
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .frame(maxWidth: 260)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            Text("Your friend scans this code, or you scan theirs.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                if case .connecting = connection?.state ?? .idle { ProgressView() }
                else if connection?.state == .searching { ProgressView() }
                Text(statusText.0).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(statusText.1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(Theme.spring, value: connection?.state)
            if let scanMessage {
                Text(scanMessage).font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.red)
            }
            Spacer(minLength: 0)
            BigButton(title: "Scan friend's code", systemImage: "qrcode.viewfinder") {
                scanMessage = nil
                scanning = true
            }
            Text("Both phones need Bluetooth or Wi‑Fi turned on. No internet or account needed.")
                .font(.rounded(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var scanner: some View {
        ZStack {
            QRScannerView { code in
                if let id = DuelQR.playerId(from: code) {
                    if id == arena.playerId {
                        scanMessage = "That's your own code 😄"
                    } else {
                        connection?.connect(to: id)
                    }
                } else {
                    scanMessage = "That's not a Měitiān duel code."
                }
                scanning = false
            }
            .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white, style: StrokeStyle(lineWidth: 5, dash: [30, 14]))
                .frame(width: 250, height: 250)
            VStack {
                HStack {
                    Spacer()
                    Button { scanning = false } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityLabel("Cancel scanning")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                Text("Point at your friend's code")
                    .font(.rounded(.headline, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
                Spacer()
                Button("Cancel") { scanning = false }
                    .font(.rounded(.headline, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 40)
            }
        }
        .presentationDetents([.large])
    }
}

/// Shown over the match while the phones find each other again.
private struct ReconnectOverlay: View {
    let connection: DuelConnection
    let name: String
    let leave: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let waited = connection.reconnectingSince.map { tl.date.timeIntervalSince($0) } ?? 0
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Reconnecting to \(name)…").font(.rounded(.title3, weight: .bold))
                Text("Keep both phones close with the app open. The match continues where it left off.")
                    .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if waited > 20 {
                    Text("Still trying… check that Bluetooth and Wi‑Fi are on for both phones.")
                        .font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.gold)
                        .multilineTextAlignment(.center)
                    Button("Leave match", role: .destructive, action: leave)
                        .font(.rounded(.headline, weight: .bold))
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .animation(Theme.spring, value: waited > 20)
        }
    }
}

/// Everything after the phones are connected.
private struct MatchScreen: View {
    @Environment(ArenaStore.self) private var arena
    let match: DuelMatch
    @Binding var confetti: Int
    let close: () -> Void
    @State private var shakeT: CGFloat = 1
    @State private var shakeStrength: CGFloat = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CloseButton(action: close)
                Spacer()
                if match.phase != .lobby {
                    Text("\(match.mode.emoji) \(match.mode.title)").font(.rounded(.headline, weight: .bold))
                }
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            if match.incompatible {
                incompatible
            } else {
                switch match.phase {
                case .lobby: lobby
            case .countdown(let n): countdown(n)
            case .playing, .roundResult:
                if match.mode == .duel { duel } else { blitz }
                case .finished: finished
                }
            }
        }
        .padding(20)
        .animation(Theme.spring, value: match.phase)
        .sensoryFeedback(.impact(weight: .heavy), trigger: match.hitTick)
    }

    // MARK: lobby

    private var incompatible: some View {
        let opp = match.opponent
        let mine = match.me.swearsOn
        return VStack(spacing: 18) {
            Spacer()
            Text("🚫").font(.system(size: 80))
            Text("can't battle").font(.street(48))
            Text(mine
                 ? "You have swear words ON, \(opp?.name ?? "your friend") has them OFF."
                 : "You have swear words OFF, \(opp?.name ?? "your friend") has them ON.")
                .font(.rounded(.headline, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Players can only battle with the same swear setting. One of you can change it in Progress → Content, then pair again.")
                .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            BigButton(title: "Close", systemImage: "xmark", gradient: Theme.inkGradient, action: close)
        }
        .onAppear { SFX.shared.play(.wrong) }
    }

    private var lobby: some View {
        let opp = match.opponent!
        let rival = arena.rivals[opp.id]
        return VStack(spacing: 14) {
            PlayerCardView(card: match.me, compact: true)
            HStack {
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                Text("VS").font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(Theme.warmGradient)
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            }
            PlayerCardView(card: opp, compact: true)
            if let rival {
                Text("Head to head: you \(rival.wins) – \(rival.losses) \(opp.name)")
                    .font(.rounded(.subheadline, weight: .bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            } else {
                Text("First battle against \(opp.name)!").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if match.isHost {
                Text("Pick a game").font(.rounded(.headline, weight: .bold))
                ForEach(DuelMode.allCases) { mode in
                    Button { match.hostStart(mode: mode) } label: {
                        HStack(spacing: 14) {
                            Text(mode.emoji).font(.system(size: 34))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.rounded(.headline, weight: .heavy))
                                Text(mode.blurb).font(.rounded(.caption)).opacity(0.9).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "play.fill")
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(mode == .duel ? Theme.warmGradient : Theme.skyGradient,
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("\(opp.name) is picking a game…").font(.rounded(.headline, weight: .semibold))
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func countdown(_ n: Int) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text("\(n)")
                .font(.system(size: 140, weight: .black, design: .rounded))
                .foregroundStyle(Theme.warmGradient)
                .contentTransition(.numericText(countsDown: true))
                .id(n)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
            Text(match.mode.blurb).font(.rounded(.headline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: n)
    }

    // MARK: duel

    private var duel: some View {
        let opp = match.opponent!
        let iWon = match.roundWinner == match.me.id
        return ZStack {
            VStack(spacing: 14) {
                HealthBar(name: opp.name, avatar: opp.avatarSymbol, hp: match.hp(of: opp.id), tint: Theme.sky,
                          hitTick: iWon ? match.hitTick : 0, aura: opp.aura)
                Spacer(minLength: 0)
                if let q = match.currentQuestion {
                    DuelQuestionPanel(question: q, picked: match.myPick, locked: match.lockedOut || match.phase == .roundResult,
                                      reveal: match.phase == .roundResult) { match.pick($0) }
                }
                roundBanner.frame(height: 44)
                Spacer(minLength: 0)
                HealthBar(name: match.me.name, avatar: match.me.avatarSymbol, hp: match.hp(of: match.me.id),
                          hitTick: !iWon && match.roundWinner != nil ? match.hitTick : 0, aura: match.me.aura)
            }
            HitEffectView(effectId: iWon ? match.me.effect : opp.effect, trigger: match.hitTick,
                          from: UnitPoint(x: 0.5, y: iWon ? 0.9 : 0.1), to: UnitPoint(x: 0.5, y: iWon ? 0.1 : 0.9),
                          damage: match.lastDamage) { strength in
                shakeStrength = strength
                shakeT = 0
                withAnimation(.linear(duration: 0.45)) { shakeT = 1 }
            }
        }
        .modifier(ImpactShake(amount: shakeT, strength: shakeStrength))
    }

    @ViewBuilder
    private var roundBanner: some View {
        if match.phase == .roundResult {
            let w = match.roundWinner
            Text(w == nil ? "Nobody got it. It was \(match.currentQuestion?.word.hanzi ?? "")"
                 : w == match.me.id ? "Hit! \(String(format: "%.1fs", Double(match.lastHitMs) / 1000)) ⚡️"
                 : "\(match.opponent?.name ?? "They") was faster!")
                .font(.rounded(.headline, weight: .heavy))
                .foregroundStyle(w == nil ? Color.secondary : w == match.me.id ? Theme.jade : Theme.red)
                .transition(.scale.combined(with: .opacity))
        } else if match.lockedOut {
            Text("Wrong! Locked out this round 🔒").font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.red)
        } else if match.myPick != nil {
            Text("Waiting…").font(.rounded(.headline, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: blitz

    private var blitz: some View {
        let opp = match.opponent!
        return VStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 0.2)) { tl in
                let left = max(0, match.blitzEnds.map { $0.timeIntervalSince(tl.date) } ?? Double(DuelMatch.blitzSeconds))
                VStack(spacing: 6) {
                    Text(match.myDone ? "Time!" : String(format: "%.0f", left.rounded(.up)))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(left < 10 ? Theme.red : .primary)
                        .contentTransition(.numericText(countsDown: true))
                    ProgressView(value: left, total: Double(DuelMatch.blitzSeconds)).tint(left < 10 ? Theme.red : Theme.sky)
                }
            }
            HStack(spacing: 12) {
                scoreBox(match.me.avatarSymbol, "You", match.myScore, Theme.jade)
                scoreBox(opp.avatarSymbol, opp.name, match.opponentScore, Theme.sky)
            }
            Spacer(minLength: 0)
            if match.myDone {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for \(opp.name) to finish…").font(.rounded(.headline))
                }
            } else if let q = match.currentQuestion {
                DuelQuestionPanel(question: q, picked: match.myPick, locked: match.lockedOut,
                                  reveal: match.lockedOut) { match.pick($0) }
                Text(match.lockedOut ? "Oops! 1 s penalty" : " ")
                    .font(.rounded(.headline, weight: .bold)).foregroundStyle(Theme.red)
            }
            Spacer(minLength: 0)
        }
        .sensoryFeedback(.success, trigger: match.myScore)
    }

    private func scoreBox(_ avatar: String, _ name: String, _ score: Int, _ c: Color) -> some View {
        VStack(spacing: 4) {
            Text(avatar).font(.title)
            Text("\(score)").font(.rounded(.largeTitle, weight: .black)).foregroundStyle(c).contentTransition(.numericText())
            Text(name).font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(Theme.bouncy, value: score)
    }

    // MARK: finished

    private var finished: some View {
        let w = match.winner ?? nil
        let won = w == match.me.id
        let draw = w == nil
        return VStack(spacing: 18) {
            Spacer()
            Text(draw ? "🤝" : won ? "🏆" : "😤").font(.system(size: 96))
            Text(draw ? "平局 · Draw!" : won ? "胜利 · Victory!" : "失败 · Defeat")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(won ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.primary))
            Text(draw ? "píngjú" : won ? "shènglì" : "shībài")
                .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
            Text("+\(match.coinsEarned) 🪙")
                .font(.rounded(.title, weight: .heavy))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.gold.opacity(0.18), in: Capsule())
            HStack(spacing: 12) {
                if match.mode == .duel {
                    resultStat("\(match.damageDealt)", "damage")
                    resultStat(match.fastestMs.map { String(format: "%.1fs", Double($0) / 1000) } ?? "–", "fastest")
                } else {
                    resultStat("\(match.myScore)", "you")
                    resultStat("\(match.opponentScore)", match.opponent?.name ?? "them")
                }
                resultStat("\(arena.streak)", "win streak")
            }
            Spacer()
            BigButton(title: "Rematch", systemImage: "arrow.clockwise") { match.backToLobby() }
            Button("Done", action: close).font(.rounded(.headline, weight: .semibold))
        }
        .onAppear { if won { confetti += 1 } }
        .sensoryFeedback(won ? .success : .warning, trigger: match.phase)
    }

    private func resultStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.rounded(.title2, weight: .heavy))
            Text(l).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Same-phone duel

/// Two players, one phone lying flat between them. The top half is upside down.
struct LocalDuelView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var hp = [DuelMatch.maxHP, DuelMatch.maxHP]
    @State private var picks: [Word?] = [nil, nil]
    @State private var locked = [false, false]
    @State private var roundWinner: Int?
    @State private var resolved = false
    @State private var winner: Int?
    @State private var hitTick = 0
    @State private var lastDamage = 0
    @State private var shownAt = Date.now
    @State private var started = false
    @State private var confetti = 0

    private let names = ["Player 1", "Player 2"]
    private let avatars = ["🐼", "🐯"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if !started {
                intro
            } else if let winner {
                result(winner)
            } else {
                VStack(spacing: 0) {
                    half(1).rotationEffect(.degrees(180))
                    middle
                    half(0)
                }
                .padding(.horizontal, 14)
            }
            ConfettiView(trigger: confetti)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: hitTick)
        .animation(Theme.spring, value: started)
        .animation(Theme.spring, value: winner)
    }

    private var intro: some View {
        VStack(spacing: 20) {
            HStack { CloseButton { dismiss() }; Spacer() }
            Spacer()
            Text("🐼 vs 🐯").font(.system(size: 64))
            Text("Same‑phone duel").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Lay the phone flat between you. Each player gets their own half of the screen. Same question for both: first right answer hits, a wrong answer locks you out for the round.")
                .font(.rounded(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Friendly match: no coins. Battle a friend on two phones to earn 🪙.")
                .font(.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.gold).multilineTextAlignment(.center)
            Spacer()
            BigButton(title: "Start", systemImage: "play.fill") { start() }
        }
        .padding(20)
    }

    private var middle: some View {
        HStack {
            CloseButton { dismiss() }
            Spacer()
            Text(roundWinner.map { "\(names[$0]) hits! -\(lastDamage)" } ?? (resolved ? "Nobody got it" : "Round \(index + 1)"))
                .font(.rounded(.headline, weight: .heavy))
                .foregroundStyle(roundWinner == nil ? Color.secondary : Theme.red)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.vertical, 6)
    }

    private func half(_ p: Int) -> some View {
        VStack(spacing: 10) {
            HealthBar(name: names[p], avatar: avatars[p], hp: hp[p], tint: p == 0 ? Theme.jade : Theme.sky,
                      hitTick: roundWinner != nil && roundWinner != p ? hitTick : 0)
            if index < questions.count {
                DuelQuestionPanel(question: questions[index], picked: picks[p], locked: locked[p] || resolved,
                                  reveal: resolved, compact: true) { pick(p, $0) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
    }

    private func start() {
        let level = max(1, store.currentLevel)
        var pool = WordBank.all.filter { $0.level <= level }
        if Prefs.swearsOn { pool += WordBank.swears }
        questions = WireQuestion.make(pool: pool, count: 60).compactMap(\.question)
        index = 0
        hp = [DuelMatch.maxHP, DuelMatch.maxHP]
        winner = nil
        nextRound(0)
        started = true
    }

    private func nextRound(_ i: Int) {
        index = i % max(questions.count, 1)
        picks = [nil, nil]
        locked = [false, false]
        roundWinner = nil
        resolved = false
        shownAt = .now
    }

    private func pick(_ p: Int, _ option: Word) {
        guard !resolved, picks[p] == nil, !locked[p], index < questions.count else { return }
        picks[p] = option
        let correct = option.id == questions[index].word.id
        if correct {
            let ms = Int(Date.now.timeIntervalSince(shownAt) * 1000)
            let damage = Int(duelDamage(reactionMs: UInt32(clamping: ms)))
            lastDamage = damage
            roundWinner = p
            resolved = true
            hp[1 - p] = max(0, hp[1 - p] - damage)
            hitTick += 1
            SFX.shared.play(.hit)
        } else {
            locked[p] = true
            SFX.shared.play(.wrong)
            if locked[0] && locked[1] { resolved = true }
        }
        guard resolved else { return }
        let i = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if hp.contains(0) {
                winner = hp[0] == 0 ? 1 : 0
                confetti += 1
            } else if index == i {
                withAnimation(Theme.spring) { nextRound(i + 1) }
            }
        }
    }

    private func result(_ w: Int) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Text(avatars[w]).font(.system(size: 96))
            Text("\(names[w]) wins!").font(.system(size: 34, weight: .black, design: .rounded))
            Text("胜利 shènglì · victory").font(.rounded(.headline)).foregroundStyle(.secondary)
            Spacer()
            BigButton(title: "Rematch", systemImage: "arrow.clockwise") { start() }
            Button("Done") { dismiss() }.font(.rounded(.headline, weight: .semibold))
        }
        .padding(20)
        .rotationEffect(.degrees(w == 1 ? 180 : 0))
    }
}
