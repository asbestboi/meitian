import SwiftUI

/// A battle in a server room, from joining to the result. `partyCode` is shown in a party's lobby.
struct BattleScreen: View {
    let path: String
    let auto: BattleMode?
    var partyCode: String? = nil
    var waitingFor: [OnlineProfile] = []
    /// Our own open invitation (its room), to take back if we leave before they come.
    var invited: String? = nil
    let close: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @State private var session: BattleSession?
    @State private var confetti = 0
    @State private var shakeT: CGFloat = 1
    @State private var shakeStrength: CGFloat = 0

    var body: some View {
        ZStack {
            ArenaBackground(theme: store.arenaTheme, strength: 0.62).ignoresSafeArea()
            if let session { content(session) }
            ConfettiView(trigger: confetti, sound: nil)
        }
        .modifier(ImpactShake(amount: shakeT, strength: shakeStrength))
        .onAppear {
            begin()
            Invites.shared.busy = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            session?.leave()
            Invites.shared.busy = false
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await OnlineService.shared.sync(store: store, arena: arena, force: true) }
        }
        .onChange(of: session?.view.phase) { _, phase in
            if phase == .finished, session?.view.result?.outcome == .win { confetti += 1 }
        }
        .haptic(.impact(weight: .heavy), trigger: session?.hit?.tick)
    }

    private func begin() {
        guard session == nil else { return }
        let card = arena.card(name: store.profile.name, level: store.currentLevel, wordsLearned: store.cards.count)
        let s = BattleSession(path: path, me: card, auto: auto) { [arena] result, rival in
            arena.record(result, rival: rival?.playerCard, picture: rival?.picture)
        }
        s.open()
        session = s
    }

    private func leave() {
        // gave up before they came: take the invitation back
        if let invited, let phase = session?.view.phase, phase == .waiting || phase == .lobby {
            Task { try? await OnlineService.shared.decline(invited) }
        }
        session?.leave()
        close()
    }

    private func content(_ session: BattleSession) -> some View {
        let v = session.view
        return VStack(spacing: 12) {
            topBar(v)
            switch v.phase {
            case .gone: message("🚫", "can't battle", v.problem)
            case .waiting: BattleConnecting(people: waitingFor)
            case .lobby:
                if v.group { GroupLobby(session: session, code: partyCode) }
                else { DuoLobby(session: session, waitingFor: waitingFor) }
            case .countdown: countdown(v)
            case .playing, .roundResult:
                BattleGame(session: session) { strength in
                    shakeStrength = strength
                    shakeT = 0
                    withAnimation(.linear(duration: 0.45)) { shakeT = 1 }
                }
            case .finished: BattleResults(session: session, leave: leave)
            }
        }
        .padding(18)
        .animation(Theme.spring, value: v.phase)
        .overlay(alignment: .top) { notes(v).padding(.top, 66) }
        .overlay { if v.paused { paused(v) } }
    }

    private func topBar(_ v: BattleView) -> some View {
        HStack {
            Button(action: leave) {
                Image(systemName: "xmark").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .foregroundStyle(.primary)
            .accessibilityLabel("Leave")
            Spacer()
            if let mode = v.mode?.info, v.phase != .lobby {
                Text("\(mode.emoji) \(mode.title.lowercased())").font(.rounded(.headline, weight: .bold))
            }
            Spacer()
            Circle().fill(v.connected ? Theme.jade : Theme.red).frame(width: 10, height: 10)
                .frame(width: 40, height: 40)
                .accessibilityLabel(v.connected ? "Connected" : "Not connected")
        }
    }

    @ViewBuilder
    private func notes(_ v: BattleView) -> some View {
        let text: String? = {
            if !v.notice.isEmpty { return v.notice }
            guard let r = v.rating else { return nil }
            return r.counted ? "rating \(r.rating) (\(r.delta >= 0 ? "+" : "")\(r.delta))" : "the phones disagreed: no rating change"
        }()
        if let text {
            Text(text).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.nightGradient, in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func message(_ emoji: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(emoji).font(.system(size: 80))
            Text(title).font(.street(40))
            Text(text).font(.rounded(.body)).multilineTextAlignment(.center)
            Spacer()
            BigButton(title: "Close", systemImage: "xmark", action: leave)
        }
    }

    private func countdown(_ v: BattleView) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text("\(v.count)")
                .font(.system(size: 140, weight: .black, design: .rounded))
                .foregroundStyle(Theme.warmGradient)
                .id(v.count)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
            if let mode = v.mode?.info { Text(mode.blurb).font(.rounded(.headline)).multilineTextAlignment(.center) }
            if v.mode == .team2v2, let me = v.players.first(where: { $0.id == v.me }) {
                let mate = v.players.first { $0.team == me.team && $0.id != me.id }
                Text("your partner: \(mate?.name ?? "?") 🤝").font(.rounded(.headline, weight: .bold))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.bouncy, value: v.count)
        .haptic(.impact(weight: .medium), trigger: v.count)
    }

    private func paused(_ v: BattleView) -> some View {
        let away = v.players.filter { !$0.here && $0.id != v.me }.map(\.name).joined(separator: ", ")
        return ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(v.connected ? "Waiting for \(away) to reconnect…" : "Reconnecting…")
                    .font(.rounded(.headline, weight: .bold)).multilineTextAlignment(.center)
                Text(v.connected ? "If they're gone for 30 seconds, they forfeit." : "The battle continues where it left off.")
                    .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Leave battle", role: .destructive, action: leave).font(.rounded(.headline, weight: .bold))
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

private struct BattleConnecting: View {
    let people: [OnlineProfile]

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            HStack(spacing: 10) { ForEach(people, id: \.id) { OnlineAvatar(profile: $0, size: 84) } }
            Text(people.isEmpty ? "connecting…" : people.map(\.nickname).joined(separator: ", "))
                .font(.rounded(.title2, weight: .heavy)).multilineTextAlignment(.center)
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BattlePicture: View {
    let player: BattlePlayer
    var size: CGFloat = 46
    var body: some View { PictureView(id: player.id, name: player.name, path: player.picture, size: size) }
}

/// A player's picture with their aura around it.
private struct DressedPicture: View {
    let player: BattlePlayer
    var size: CGFloat = 46
    var body: some View {
        BattlePicture(player: player, size: size)
            .background { AuraView(auraId: player.playerCard?.aura ?? "au.none", radius: size / 2 + 2).frame(width: size * 2.1, height: size * 2.1) }
    }
}

private extension BattlePlayer {
    /// The title whose colours their name wears.
    var titleId: String { playerCard?.title ?? profile?.cosmeticTitle ?? "" }
}

private extension View {
    /// A player's equipped frame around their bar, and their sticker slapped on its corner.
    func dressed(_ player: BattlePlayer, radius: CGFloat = 22, width: CGFloat = 5, sticker: CGFloat = 28) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Catalog.frameGradient(player.playerCard?.frame ?? "fr.lantern"), lineWidth: width).allowsHitTesting(false))
            .overlay(alignment: .topTrailing) {
                if let s = player.playerCard?.stickerSymbol {
                    Text(s).font(.system(size: sticker)).rotationEffect(.degrees(14)).offset(x: 6, y: -12).accessibilityHidden(true)
                }
            }
    }
}

// MARK: - lobby

private struct DuoLobby: View {
    let session: BattleSession
    let waitingFor: [OnlineProfile]
    @Environment(ArenaStore.self) private var arena

    var body: some View {
        let v = session.view
        let opp = v.players.first { $0.id != v.me }
        if let opp, let card = opp.playerCard {
            VStack(spacing: 14) {
                PlayerCardView(card: session.me, compact: true) { MyPicture(size: 54) }
                Text("VS").font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(Theme.warmGradient)
                PlayerCardView(card: card, compact: true) { BattlePicture(player: opp, size: 54) }
                ArenaBadge(theme: arenaFor(level: opp.level, unit: 1))
                if let rival = arena.rivals[card.id] {
                    Text("Head to head: you \(rival.wins) – \(rival.losses) \(opp.name)").font(.rounded(.subheadline, weight: .bold))
                } else {
                    Text("First battle against \(opp.name)!").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ModeMenu(session: session, players: 2)
            }
        } else {
            VStack {
                BattleConnecting(people: opp?.profile.map { [$0] } ?? waitingFor)
                Text("they got your invitation ✉️ it stays open for 30 minutes. The battle starts as soon as they accept.")
                    .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

private struct SeatSurface: ViewModifier {
    let player: BattlePlayer?
    func body(content: Content) -> some View {
        if let player { content.dressed(player, width: 3, sticker: 22) }
        else { content.background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }
    }
}

private struct GroupLobby: View {
    let session: BattleSession
    let code: String?

    var body: some View {
        let v = session.view
        let here = v.players.filter { $0.here && !$0.card.isEmpty }.count
        VStack(spacing: 14) {
            if let code {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("party code").font(.rounded(.caption, weight: .bold)).opacity(0.85)
                        Text(code).font(.system(size: 32, weight: .heavy, design: .rounded)).textSelection(.enabled)
                    }
                    Spacer()
                    ShareLink(item: "Join my Měitiān party: \(code)") { Pill(text: "share", color: .white, systemImage: "square.and.arrow.up") }
                }
                .foregroundStyle(.white)
                .streetBlock(Theme.pinkGradient, padding: 16)
            }
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in seat(i < v.players.count ? v.players[i] : nil, host: v.host) }
            }
            if let code, v.players.count < 4 { InviteFriends(code: code, inParty: v.players.map(\.id)) }
            Spacer(minLength: 0)
            ModeMenu(session: session, players: here)
        }
    }

    private func seat(_ p: BattlePlayer?, host: String) -> some View {
        VStack(spacing: 4) {
            if let p {
                DressedPicture(player: p, size: 52)
                Text(p.name).font(.rounded(.caption, weight: .bold)).titled(p.titleId)
                Text(p.id == host ? "host 👑" : "\(arenaFor(level: p.level, unit: 1).emoji) HSK \(p.level)")
                    .font(.rounded(.caption2)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Image(systemName: "plus").font(.headline).foregroundStyle(.secondary)
                    .frame(width: 52, height: 52).background(Color.secondary.opacity(0.15), in: Circle())
                Text("free").font(.rounded(.caption)).foregroundStyle(.secondary)
                Text(" ").font(.rounded(.caption2))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .modifier(SeatSurface(player: p))
        .opacity(p?.here ?? true ? 1 : 0.4)
    }
}

/// Friends who aren't in the party yet: one tap puts an invitation into their inbox.
private struct InviteFriends: View {
    let code: String
    let inParty: [String]
    @State private var friends: [OnlineProfile] = []
    @State private var invited: Set<String> = []

    var body: some View {
        let free = friends.filter { !inParty.contains($0.id) }.prefix(6)
        VStack(alignment: .leading, spacing: 8) {
            if !free.isEmpty {
                Text("invite friends").font(.rounded(.footnote, weight: .bold)).foregroundStyle(.secondary)
                ForEach(Array(free), id: \.id) { f in
                    HStack(spacing: 10) {
                        OnlineAvatar(profile: f, size: 34)
                        Text(f.nickname + (f.online ? " · online" : "")).font(.rounded(.subheadline, weight: .bold)).lineLimit(1)
                        Spacer()
                        Button {
                            Task {
                                if (try? await OnlineService.shared.inviteToParty(code, friendId: f.id)) != nil { invited.insert(f.id) }
                            }
                        } label: { Pill(text: invited.contains(f.id) ? "invited ✓" : "invite", color: invited.contains(f.id) ? .secondary : Theme.jade) }
                        .disabled(invited.contains(f.id))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardIf(on: !free.isEmpty))
        .task { friends = (try? await OnlineService.shared.friends().friends) ?? [] }
    }
}

private struct CardIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.cardSurface(padding: 12) } else { content }
    }
}

/// The host picks a game; everyone else waits.
private struct ModeMenu: View {
    let session: BattleSession
    let players: Int

    var body: some View {
        let v = session.view
        if !v.isHost {
            let host = v.players.first { $0.id == v.host }?.name ?? "The host"
            note(v.mode != nil ? "starting soon…" : "\(host) is picking a game…")
        } else if v.mode != nil {
            note("starting as soon as everyone is here…")
        } else if !v.canStart {
            note("you need at least one more player")
        } else {
            VStack(spacing: 10) {
                Text("pick a game").font(.rounded(.headline, weight: .bold))
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(modesFor(players: UInt32(clamping: players))) { mode in
                            Button { session.start(mode.mode) } label: {
                                HStack(spacing: 12) {
                                    Text(mode.emoji).font(.system(size: 30))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title).font(.rounded(.headline, weight: .heavy))
                                        Text(mode.blurb).font(.rounded(.caption)).opacity(0.9)
                                            .multilineTextAlignment(.leading).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "play.fill")
                                }
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(mode.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 360)
            }
        }
    }

    private func note(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).font(.rounded(.headline, weight: .semibold)).multilineTextAlignment(.center)
        }
        .padding(.bottom, 30)
    }
}

// MARK: - the game

/// Where everybody is on screen, so hits can fly there.
private struct SpotsKey: PreferenceKey {
    static var defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func spot(_ id: String) -> some View {
        background(GeometryReader { geo in
            let f = geo.frame(in: .named("battle"))
            Color.clear.preference(key: SpotsKey.self, value: [id: CGPoint(x: f.midX, y: f.midY)])
        })
    }
}

private struct BattleGame: View {
    let session: BattleSession
    let onImpact: (CGFloat) -> Void
    @State private var spots: [String: CGPoint] = [:]

    var body: some View {
        let v = session.view
        let mode = v.mode ?? .duel
        let others = v.players.filter { $0.id != v.me }
        let me = v.players.first { $0.id == v.me }
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 10) {
                    if others.count == 1, let opp = others.first {
                        PlayerBar(player: opp, mode: mode, view: v)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(others) { PlayerChip(player: $0, mode: mode, view: v) }
                        }
                    }
                    timeBar(v, mode)
                    Spacer(minLength: 0)
                    if mode.isRace && me?.done == true {
                        waiting("time! waiting for the others…")
                    } else if v.spectating {
                        waiting("you're out 👀 watching")
                    } else if let q = v.question {
                        BattleQuestionPanel(question: q, view: v) { session.answer($0) }
                            .id(v.index)
                    }
                    banner(v, mode)
                    Spacer(minLength: 0)
                    if let me { PlayerBar(player: me, mode: mode, view: v, mine: true) }
                    if v.maxLives > 0 {
                        HStack(spacing: 4) {
                            ForEach(0..<Int(v.maxLives), id: \.self) { i in Text(i < Int(v.lives) ? "❤️" : "🤍").font(.title3) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(v.lives) lives left")
                    }
                }
                if let hit = session.hit {
                    let effect = v.players.first { $0.id == hit.attacker }?.playerCard?.effect ?? "fx.boom"
                    ForEach(hit.targets, id: \.self) { target in
                        HitEffectView(effectId: effect, trigger: hit.tick, from: unit(hit.attacker, geo.size, .bottom),
                                      to: unit(target, geo.size, .top), damage: hit.damage, fireOnAppear: true, onImpact: onImpact)
                    }
                }
            }
        }
        .coordinateSpace(name: "battle")
        .onPreferenceChange(SpotsKey.self) { spots = $0 }
    }

    private func unit(_ id: String, _ size: CGSize, _ fallback: UnitPoint) -> UnitPoint {
        guard let p = spots[id], size.width > 0, size.height > 0 else { return fallback }
        return UnitPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).font(.rounded(.headline, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    @ViewBuilder
    private func timeBar(_ v: BattleView, _ mode: BattleMode) -> some View {
        if v.timeTotalMs > 0 {
            let left = Double(v.timeLeftMs), total = Double(v.timeTotalMs)
            let low = left < 3000 || (mode.isRace && left < 10000)
            VStack(spacing: 4) {
                if mode.isRace {
                    Text(String(format: "%.0f", (left / 1000).rounded(.up)))
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(low ? Theme.red : .primary)
                        .contentTransition(.numericText(countsDown: true))
                }
                ProgressView(value: min(left, total), total: total).tint(low ? Theme.red : Theme.sky)
            }
        } else {
            Color.clear.frame(height: 6)
        }
    }

    private func banner(_ v: BattleView, _ mode: BattleMode) -> some View {
        let (text, color) = bannerText(v, mode)
        return VStack(spacing: 2) {
            Text(text).font(.rounded(.headline, weight: .heavy)).foregroundStyle(color)
            if v.reveal && v.phase == .roundResult, let q = v.question {
                Text(q.solution).font(.rounded(.subheadline, weight: .semibold))
            }
        }
        .multilineTextAlignment(.center)
        .frame(minHeight: 44)
    }

    private func bannerText(_ v: BattleView, _ mode: BattleMode) -> (String, Color) {
        let seconds = String(format: "%.1fs", Double(v.lastMs) / 1000)
        if v.phase == .roundResult {
            if mode == .battleRoyale { return ("\(v.players.filter { !$0.out }.count) still in", .primary) }
            if v.roundWinner == v.me && !v.me.isEmpty {
                return (mode.hasHP ? "hit! -\(v.lastDamage) · \(seconds) ⚡️" : "point! \(seconds) ⚡️", Theme.jade)
            }
            if let w = v.players.first(where: { $0.id == v.roundWinner }) { return ("\(w.name) was faster!", Theme.red) }
            return (v.reveal ? "nobody got it" : " ", .secondary)
        }
        if v.locked && mode.isRace { return (mode == .survival ? "ouch! -1 life" : "oops! 1 s penalty", Theme.red) }
        if v.locked { return ("not quite, try again", Theme.red) }
        if v.answered && !mode.isRace { return ("waiting…", .secondary) }
        return (" ", .primary)
    }
}

private func scoreText(_ p: BattlePlayer, _ mode: BattleMode, _ v: BattleView) -> String {
    if mode.hasHP { return "\(p.hp) HP" }
    if mode == .battleRoyale { return p.out ? "out" : "in 👑" }
    if v.target > 0 { return "\(p.score) / \(v.target)" }
    return "\(p.score)" + (p.done ? " ✓" : "")
}

private struct HPBar: View {
    let hp: UInt32
    var tint: Color
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(hp <= 30 ? AnyShapeStyle(Theme.warmGradient) : AnyShapeStyle(tint))
                    .frame(width: geo.size.width * CGFloat(min(hp, 100)) / 100)
            }
        }
        .frame(height: height)
        .animation(Theme.bouncy, value: hp)
    }
}

/// Wide bar: me, or the only opponent.
private struct PlayerBar: View {
    let player: BattlePlayer
    let mode: BattleMode
    let view: BattleView
    var mine = false

    var body: some View {
        HStack(spacing: 10) {
            DressedPicture(player: player, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mine ? "\(player.name) (you)" : player.name).font(.rounded(.subheadline, weight: .heavy)).titled(player.titleId)
                        if let t = player.playerCard?.titleItem {
                            Text("\(t.symbol) · \(t.name)").font(.rounded(.caption2, weight: .bold)).titled(t.id)
                        }
                    }
                    Spacer()
                    if mode == .team2v2 { Pill(text: "team \(player.team == 0 ? "🔴" : "🔵")", color: .secondary) }
                    Text(scoreText(player, mode, view)).font(.rounded(.subheadline, weight: .heavy))
                        .contentTransition(.numericText())
                        .foregroundStyle(mode.hasHP && player.hp <= 30 ? Theme.red : .primary)
                }
                if mode.hasHP { HPBar(hp: player.hp, tint: mine ? Theme.jade : Theme.sky) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .dressed(player)
        .opacity(player.out ? 0.5 : 1)
        .spot(player.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mine ? "You" : player.name), \(scoreText(player, mode, view))")
    }
}

/// Narrow card: one of several opponents.
private struct PlayerChip: View {
    let player: BattlePlayer
    let mode: BattleMode
    let view: BattleView

    var body: some View {
        VStack(spacing: 4) {
            DressedPicture(player: player, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    if mode == .team2v2 { Text(player.team == 0 ? "🔴" : "🔵").font(.caption2) }
                }
                .overlay(alignment: .topTrailing) {
                    if player.answered && view.phase == .playing { Text("💬").font(.caption2) }
                }
            Text(player.name).font(.rounded(.caption, weight: .bold)).titled(player.titleId)
            Text(player.out ? "out" : scoreText(player, mode, view))
                .font(.rounded(.caption, weight: .heavy)).foregroundStyle(player.out ? Theme.red : .primary)
            if mode.hasHP { HPBar(hp: player.hp, tint: Theme.sky, height: 8) }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .dressed(player, width: 4, sticker: 22)
        .opacity(player.out || !player.here ? 0.45 : 1)
        .spot(player.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.name), \(player.out ? "out" : scoreText(player, mode, view))")
    }
}

/// A question with its way of answering: four options, word tiles or a pinyin field.
struct BattleQuestionPanel: View {
    let question: BattleQuestion
    let view: BattleView
    let answer: (BattleAnswer) -> Void

    @AppStorage(PinyinPrefs.show) private var showPinyin = true
    @State private var built: [Int] = []
    @State private var text = ""
    @FocusState private var typing: Bool

    private var isOpen: Bool { view.phase == .playing && !view.answered && !view.locked }

    var body: some View {
        VStack(spacing: 12) {
            prompt
                .frame(maxWidth: .infinity, minHeight: 100)
                .cardSurface(padding: 12)
            switch question.ask {
            case .sentence: tiles
            case .pinyin: field
            default: options
            }
        }
        .onAppear {
            if !question.say.isEmpty && view.phase == .playing { Speaker.shared.say(question.say) }
            if question.ask == .pinyin { typing = true }
        }
        // the finished sentence, once the round is over
        .onChange(of: view.phase) { _, phase in
            let say = sayAfterRound(question: question)
            if phase == .roundResult, !say.isEmpty { Speaker.shared.say(say) }
        }
    }

    @ViewBuilder
    private var prompt: some View {
        switch question.ask {
        case .listen, .tone:
            VStack(spacing: 6) {
                SpeakButton(text: question.say, size: 76, tint: Theme.jade)
                Text(question.ask == .tone ? "which tone? “\(question.prompt)”" : "listen and tap it")
                    .font(.rounded(.footnote, weight: .bold)).foregroundStyle(.secondary)
            }
        case .meaning:
            RubyText(hanzi: question.prompt, pinyin: question.promptPinyin, size: question.prompt.count > 3 ? 44 : 56,
                     weight: .semibold, alignment: .center)
        case .pinyin:
            HStack(spacing: 14) {
                Text(question.prompt).font(.hanzi(question.prompt.count > 3 ? 44 : 60, weight: .semibold))
                SpeakButton(text: question.prompt, size: 48, tint: Theme.jade)
            }
        case .hanzi, .sentence:
            Text("“\(question.prompt)”").font(.rounded(.title2, weight: .bold))
                .multilineTextAlignment(.center).minimumScaleFactor(0.5)
        }
    }

    private var options: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { i, o in option(i, o) }
        }
    }

    private func option(_ i: Int, _ o: BattleOption) -> some View {
        let right = i == Int(question.answer)
        let mine = view.myOption.map { Int($0) == i } ?? false
        let chinese = question.ask != .meaning
        let bg: Color = view.reveal && right ? Theme.jade.opacity(0.25)
            : mine ? (right ? Theme.jade.opacity(0.25) : Theme.red.opacity(0.22)) : Theme.card
        return Button { answer(.option(index: UInt32(i))) } label: {
            VStack(spacing: 1) {
                Text(o.label)
                    .font(chinese ? .hanzi(26, weight: .medium) : .rounded(.headline, weight: .semibold))
                    .foregroundStyle(question.ask == .tone ? Pinyin.toneColor(i + 1) : Color.primary)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                if !o.pinyin.isEmpty && showPinyin {
                    PinyinText(pinyin: o.pinyin, font: .rounded(.caption2, weight: .semibold)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.horizontal, 6)
            .background(bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(!isOpen && !mine && !(view.reveal && right) ? 0.5 : 1)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
        .disabled(!isOpen)
        .accessibilityLabel(question.ask == .tone ? "tone \(i + 1)" : o.label)
    }

    private var tiles: some View {
        VStack(spacing: 12) {
            FlowLayout(spacing: 6, lineSpacing: 8) {
                ForEach(built, id: \.self) { i in
                    tile(question.tiles[i]) { withAnimation(Theme.bouncy) { built.removeAll { $0 == i } } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(height: 1) }
            FlowLayout(spacing: 6, lineSpacing: 8, alignment: .center) {
                ForEach(Array(question.tiles.enumerated()), id: \.offset) { i, t in
                    tile(t, used: built.contains(i)) {
                        Speaker.shared.say(t)
                        withAnimation(Theme.bouncy) { built.append(i) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            BigButton(title: "check", systemImage: "checkmark", gradient: Theme.jadeGradient,
                      enabled: isOpen && built.count == question.tiles.count) {
                answer(.tiles(tiles: built.map { question.tiles[$0] }))
            }
        }
    }

    private func tile(_ text: String, used: Bool = false, action: @escaping () -> Void) -> some View {
        Button { if isOpen && !used { action() } } label: {
            Text(text).font(.hanzi(23, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(used ? Color.secondary.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(used ? Color.clear : Color.primary)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(used)
    }

    private var field: some View {
        VStack(spacing: 10) {
            TextField("pinyin, e.g. nihao", text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                .focused($typing)
                .font(.rounded(.title3, weight: .semibold))
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onSubmit { submit() }
            BigButton(title: "go", gradient: Theme.jadeGradient, enabled: isOpen && !text.isEmpty) { submit() }
        }
    }

    private func submit() {
        guard isOpen, !text.isEmpty else { return }
        answer(.text(text: text))
        typing = true
    }
}

// MARK: - result

private struct BattleResults: View {
    let session: BattleSession
    let leave: () -> Void
    @Environment(ArenaStore.self) private var arena

    var body: some View {
        let v = session.view
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            headline(v)
            Text("+\(session.coins) 🪙")
                .font(.rounded(.title, weight: .heavy))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.gold.opacity(0.18), in: Capsule())
            VStack(spacing: 8) {
                ForEach(v.players.sorted { $0.place < $1.place }) { p in
                    HStack(spacing: 10) {
                        Text("\(p.place)").font(.rounded(.headline, weight: .heavy)).foregroundStyle(.secondary)
                        DressedPicture(player: p, size: 36)
                        Text(p.id == v.me ? "\(p.name) (you)" : p.name).font(.rounded(.subheadline, weight: .heavy)).titled(p.titleId)
                        if let s = p.playerCard?.stickerSymbol { Text(s) }
                        Spacer()
                        if let mode = v.mode {
                            Text(scoreText(p, mode, v)).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .cardSurface(padding: 14)
            if let r = v.result {
                HStack(spacing: 12) {
                    if v.mode?.hasHP == true { stat("\(r.damage)", "damage") }
                    stat(r.fastestMs.map { String(format: "%.1fs", Double($0) / 1000) } ?? "–", "fastest")
                    if r.ranked { stat("\(arena.streak)", "win streak") }
                }
            }
            Spacer(minLength: 0)
            if v.canRematch {
                BigButton(title: v.group ? "play again" : "rematch", systemImage: "arrow.clockwise") { session.rematch() }
            } else {
                let host = v.players.first { $0.id == v.host }?.name ?? "the host"
                Text("waiting for \(host) to start the next game…").font(.rounded(.subheadline, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            Button("Done", action: leave).font(.rounded(.headline, weight: .semibold))
        }
        .haptic(v.result?.outcome == .win ? .success : .warning, trigger: v.phase)
    }

    @ViewBuilder
    private func headline(_ v: BattleView) -> some View {
        if v.group {
            let place = Int(v.result?.place ?? 4)
            Text(["🥇", "🥈", "🥉", "🎖️"][min(max(place - 1, 0), 3)]).font(.system(size: 84))
            Text(["第一名 · first place!", "第二名 · second", "第三名 · third", "第四名 · fourth"][min(max(place - 1, 0), 3)])
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(place == 1 ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.primary))
        } else {
            let won = v.result?.outcome == .win
            let draw = v.result?.outcome == .draw
            Text(draw ? "🤝" : won ? "🏆" : "😤").font(.system(size: 84))
            Text(draw ? "平局 · Draw!" : won ? "胜利 · Victory!" : "失败 · Defeat")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(won ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.primary))
            Text(draw ? "píngjú" : won ? "shènglì" : "shībài")
                .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.rounded(.title2, weight: .heavy))
            Text(l).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
