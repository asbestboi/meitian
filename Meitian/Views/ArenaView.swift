import SwiftUI

/// Player card shown on the arena, pairing and versus screens.
struct PlayerCardView<Picture: View>: View {
    let card: PlayerCard
    var compact = false
    var coins: Int? = nil
    @ViewBuilder var picture: Picture

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            picture
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                .background {
                    AuraView(auraId: card.aura ?? "au.none", radius: compact ? 28 : 40)
                        .frame(width: compact ? 120 : 170, height: compact ? 120 : 170)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(.rounded(compact ? .headline : .title2, weight: .bold))
                    .lineLimit(1)
                if let t = card.titleItem {
                    Text("\(t.symbol) · \(t.name)")
                        .font(.rounded(compact ? .caption : .subheadline, weight: .semibold))
                        .opacity(0.9)
                }
                HStack(spacing: 10) {
                    Label("HSK \(card.level)", systemImage: "graduationcap.fill")
                    Label("\(card.wins)W \(card.losses)L", systemImage: "trophy.fill")
                }
                .font(.rounded(.caption, weight: .semibold))
                .opacity(0.85)
            }
            Spacer(minLength: 0)
            if let coins {
                HStack(spacing: 4) {
                    Text("🪙")
                    Text("\(coins)").font(.rounded(.headline, weight: .heavy)).contentTransition(.numericText())
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.22), in: Capsule())
                .accessibilityLabel("\(coins) coins")
            }
        }
        .foregroundStyle(.white)
        .streetBlock(Catalog.frameGradient(card.frame), padding: compact ? 14 : 20)
        .overlay(alignment: .topTrailing) {
            if let s = card.stickerSymbol {
                Text(s).font(.system(size: compact ? 30 : 40))
                    .rotationEffect(.degrees(14))
                    .offset(x: 6, y: -14)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct ArenaView: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @State private var hub: HubStart?
    @State private var shop = false
    /// Battles need internet; ask the server whether it can be reached (nil = still checking).
    @State private var server: ServerState?
    @State private var road = false
    @State private var retry = 0

    private var myCard: PlayerCard {
        arena.card(name: store.profile.name, level: store.currentLevel, wordsLearned: store.cards.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PlayerCardView(card: myCard, coins: arena.coins) { MyPicture(size: 78) }
                    Button { road = true } label: { ArenaBadge(theme: store.arenaTheme) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Shows every arena")

                    if server == .offline || server == .outdated {
                        offline
                    } else {
                        entry("Battle", "Quick match anyone, battle friends, climb the leaderboards. iPhone + Android.",
                              "globe.asia.australia.fill", Theme.skyGradient, badge: waiting) { hub = .play }
                        entry("Party", "Up to 4 friends in one game. Share a code, pick a mode, play.",
                              "party.popper.fill", Theme.pinkGradient, badge: 0) { hub = .party }
                    }

                    tile("Shop", "Frames, titles, hits, auras, stickers", "bag.fill", Theme.goldGradient) { shop = true }

                    howItWorks
                    stats
                    rivals
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Arena")
        }
        .fullScreenCover(item: $hub) { start in
            OnlineHub(startAt: start).environment(store).environment(arena).sheetSounds()
        }
        .task(id: retry) {
            server = nil
            server = await OnlineService.shared.state()
        }
        .fullScreenCover(isPresented: $road) { ArenaRoad().environment(store) }
        .sheet(isPresented: $shop) {
            ShopView(card: myCard).environment(store).environment(arena).sheetSounds()
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
    }

    private var waiting: Int {
        (OnlineService.shared.inbox?.challenges.count ?? 0) + Int(OnlineService.shared.inbox?.requests ?? 0)
    }

    private var offline: some View {
        VStack(spacing: 10) {
            Image(systemName: server == .outdated ? "wrench.and.screwdriver.fill" : "wifi.slash").font(.system(size: 40, weight: .semibold)).foregroundStyle(.secondary)
            Text(server == .outdated ? "the battle server is being updated" : "battles need internet").font(.rounded(.title3, weight: .heavy))
            Text(server == .outdated ? "It doesn't know this version's battles yet. Come back in a little while."
                 : "Lessons, stories and reviews work offline. Come back here when you're connected.")
                .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            BigButton(title: "try again", systemImage: "arrow.clockwise") { retry += 1 }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func entry(_ title: String, _ text: String, _ icon: String, _ gradient: LinearGradient, badge: Int,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 34, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.rounded(.title3, weight: .heavy))
                    Text(text).font(.rounded(.subheadline)).opacity(0.9).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if badge > 0 { Pill(text: "\(badge) new", color: .white) }
                Image(systemName: "chevron.right").font(.headline)
            }
            .foregroundStyle(.white)
            .streetBlock(gradient)
        }
        .buttonStyle(PressableStyle())
    }

    private func tile(_ title: String, _ sub: String, _ icon: String, _ g: LinearGradient, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(g, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.rounded(.headline, weight: .bold))
                Text(sub).font(.rounded(.caption, weight: .medium)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary)
            .cardSurface(padding: 16)
        }
        .buttonStyle(PressableStyle())
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Games").font(.rounded(.headline, weight: .bold))
            ForEach(battleModes()) { m in
                HStack(alignment: .top, spacing: 12) {
                    Text(m.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.rounded(.subheadline, weight: .bold))
                        Text(m.blurb).font(.rounded(.subheadline)).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Win to earn 🪙 coins. Bigger wins and win streaks pay more.")
                .font(.rounded(.footnote, weight: .semibold))
                .foregroundStyle(Theme.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var stats: some View {
        let played = arena.wins + arena.losses + arena.draws
        let rate = played == 0 ? 0 : Int(Double(arena.wins) / Double(played) * 100)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Battle stats").font(.rounded(.headline, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                stat("\(arena.wins)", "Wins", Theme.jade)
                stat("\(arena.losses)", "Losses", Theme.red)
                stat("\(rate)%", "Win rate", Theme.sky)
                stat("\(arena.streak)", "Streak", Theme.gold)
                stat("\(arena.bestStreak)", "Best streak", Theme.plum)
                stat(arena.fastestMs.map { String(format: "%.1fs", Double($0) / 1000) } ?? "–", "Fastest", Theme.red)
            }
        }
        .cardSurface()
    }

    private func stat(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.rounded(.title2, weight: .heavy)).foregroundStyle(c).contentTransition(.numericText())
            Text(l).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rivals: some View {
        if !arena.rivals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rivals").font(.rounded(.headline, weight: .bold))
                ForEach(arena.sortedRivals) { r in
                    HStack(spacing: 12) {
                        PictureView(id: r.id, name: r.name, path: r.picture ?? "", size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.rounded(.headline, weight: .bold))
                            Text(r.lastPlayed.formatted(.relative(presentation: .named)))
                                .font(.rounded(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(r.wins) – \(r.losses)")
                            .font(.rounded(.title3, weight: .heavy))
                            .foregroundStyle(r.wins >= r.losses ? Theme.jade : Theme.red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .cardSurface()
        }
    }
}

struct ShopView: View {
    @Environment(ArenaStore.self) private var arena
    @Environment(\.dismiss) private var dismiss
    let card: PlayerCard
    @State private var kind: CosmeticKind = .frame
    @State private var boughtTick = 0
    @State private var deniedTick = 0
    @State private var confetti = 0
    @State private var demoEffect = "fx.boom"
    @State private var demoTick = 0
    @State private var shakeT: CGFloat = 1
    @State private var shakeStrength: CGFloat = 0
    @AppStorage(Prefs.swears) private var swears = false

    private var preview: PlayerCard {
        var c = card
        c.frame = arena.frame; c.title = arena.title; c.effect = arena.effect
        c.sticker = arena.sticker; c.aura = arena.aura
        return c
    }

    /// Hit preview stage: tap any hit to see it fly.
    private var demoStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.nightGradient)
            HStack {
                MyPicture(size: 48)
                Spacer()
                Text("🎯").font(.system(size: 40))
            }
            .padding(.horizontal, 24)
            HitEffectView(effectId: demoEffect, trigger: demoTick, from: UnitPoint(x: 0.14, y: 0.55),
                          to: UnitPoint(x: 0.86, y: 0.5), damage: 22) { strength in
                shakeStrength = strength
                shakeT = 0
                withAnimation(.linear(duration: 0.45)) { shakeT = 1 }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            VStack {
                Spacer()
                Text("tap a hit to try it").font(.rounded(.caption, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 8)
            }
        }
        .frame(height: 150)
        .modifier(ImpactShake(amount: shakeT, strength: shakeStrength))
        .onTapGesture { demoTick += 1 }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("Shop").font(.system(size: 30, weight: .bold, design: .rounded))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("🪙")
                        Text("\(arena.coins)").font(.rounded(.headline, weight: .heavy)).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.gold.opacity(0.18), in: Capsule())
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline.weight(.bold))
                            .frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Close")
                }
                if kind == .effect {
                    demoStage.transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    PlayerCardView(card: preview, compact: true) { MyPicture(size: 54) }
                        .animation(Theme.bouncy, value: preview)
                }
                Picker("Kind", selection: $kind) {
                    ForEach(CosmeticKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .animation(Theme.spring, value: kind)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Catalog.items(kind, swears: swears)) { item in itemTile(item) }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .padding(20)
            ConfettiView(trigger: confetti, sound: nil)
        }
        .haptic(.success, trigger: boughtTick)
        .haptic(.error, trigger: deniedTick)
    }

    private func itemTile(_ item: Cosmetic) -> some View {
        let owned = arena.owned.contains(item.id)
        let equipped = arena.equipped(item.kind) == item.id
        let affordable = arena.coins >= item.price
        return Button {
            if item.kind == .effect {
                demoEffect = item.id
                demoTick += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { SFX.shared.playHit(item.id) }
            }
            if owned {
                withAnimation(Theme.bouncy) { arena.equip(item) }
            } else if arena.buy(item) {
                boughtTick += 1
                confetti += 1
                SFX.shared.play(.purchase)
            } else {
                deniedTick += 1
                SFX.shared.play(.wrong)
            }
        } label: {
            VStack(spacing: 10) {
                itemPreview(item)
                    .frame(height: 70)
                Text(item.name).font(.rounded(.subheadline, weight: .bold)).lineLimit(1)
                Group {
                    if equipped {
                        Label("Equipped", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.jade)
                    } else if owned {
                        Text("Equip").foregroundStyle(Theme.sky)
                    } else {
                        Text("🪙 \(item.price)").foregroundStyle(affordable ? Color.primary : Color.secondary)
                    }
                }
                .font(.rounded(.caption, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(equipped ? Theme.jade : .clear, lineWidth: 2.5))
            .opacity(!owned && !affordable ? 0.6 : 1)
            .foregroundStyle(.primary)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(item.name), \(equipped ? "equipped" : owned ? "owned" : "\(item.price) coins")")
    }

    @ViewBuilder
    private func itemPreview(_ item: Cosmetic) -> some View {
        switch item.kind {
        case .effect:
            Text(item.symbol).font(.system(size: 48))
        case .aura:
            ZStack {
                AuraView(auraId: item.id, radius: 22).frame(width: 110, height: 90)
                if item.symbol.isEmpty { Text("🚫").font(.system(size: 36)) } else { MyPicture(size: 38) }
            }
        case .sticker:
            if item.symbol.isEmpty {
                Image(systemName: "nosign").font(.system(size: 36, weight: .bold)).foregroundStyle(.secondary)
            } else {
                Text(item.symbol).font(.system(size: 44))
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.ink, lineWidth: 2))
                    .rotationEffect(.degrees(-8))
            }
        case .frame:
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Catalog.frameGradient(item.id))
                .frame(width: 96, height: 60)
        case .title:
            Text(item.symbol).font(.hanzi(26, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
        }
    }
}
