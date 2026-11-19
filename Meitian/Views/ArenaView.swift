import SwiftUI

/// Player card shown on the arena, pairing and versus screens.
struct PlayerCardView: View {
    let card: PlayerCard
    var compact = false
    var coins: Int? = nil

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            Text(card.avatarSymbol)
                .font(.system(size: compact ? 34 : 52))
                .frame(width: compact ? 54 : 78, height: compact ? 54 : 78)
                .background(.white.opacity(0.22), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
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
    @State private var online = false
    @State private var local = false
    @State private var shop = false

    private var myCard: PlayerCard {
        arena.card(name: store.profile.name, level: store.currentLevel, wordsLearned: store.cards.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PlayerCardView(card: myCard, coins: arena.coins)

                    Button { online = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 34, weight: .semibold))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Battle a friend").font(.rounded(.title3, weight: .heavy))
                                Text("Scan each other's QR code. Works offline, no internet needed.")
                                    .font(.rounded(.subheadline)).opacity(0.9)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.headline)
                        }
                        .foregroundStyle(.white)
                        .streetBlock(Theme.warmGradient)
                    }
                    .buttonStyle(PressableStyle())

                    HStack(spacing: 12) {
                        tile("Same phone", "Split screen duel on one phone", "iphone.gen3", Theme.skyGradient) { local = true }
                        tile("Shop", "Avatars, frames, titles, effects", "bag.fill", Theme.goldGradient) { shop = true }
                    }

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
        .fullScreenCover(isPresented: $online) {
            OnlineDuelView().environment(store).environment(arena)
        }
        .fullScreenCover(isPresented: $local) {
            LocalDuelView().environment(store).environment(arena)
        }
        .sheet(isPresented: $shop) {
            ShopView(card: myCard).environment(arena)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
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
            ForEach(DuelMode.allCases) { m in
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
                        Text(Catalog.item(r.avatar)?.symbol ?? "🐣").font(.title)
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
    @State private var kind: CosmeticKind = .avatar
    @State private var boughtTick = 0
    @State private var deniedTick = 0
    @State private var confetti = 0
    @AppStorage(Prefs.swears) private var swears = false

    private var preview: PlayerCard {
        var c = card
        c.avatar = arena.avatar; c.frame = arena.frame; c.title = arena.title; c.effect = arena.effect
        c.sticker = arena.sticker
        return c
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
                PlayerCardView(card: preview, compact: true)
                    .overlay(alignment: .topTrailing) {
                        Text(preview.effectSymbol).font(.title).padding(10)
                    }
                    .animation(Theme.bouncy, value: preview)
                Picker("Kind", selection: $kind) {
                    ForEach(CosmeticKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
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
        .sensoryFeedback(.success, trigger: boughtTick)
        .sensoryFeedback(.error, trigger: deniedTick)
    }

    private func itemTile(_ item: Cosmetic) -> some View {
        let owned = arena.owned.contains(item.id)
        let equipped = arena.equipped(item.kind) == item.id
        let affordable = arena.coins >= item.price
        return Button {
            if owned {
                withAnimation(Theme.bouncy) { arena.equip(item) }
            } else if arena.buy(item) {
                boughtTick += 1
                confetti += 1
                SFX.shared.play(.coin)
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
        case .avatar, .effect:
            Text(item.symbol).font(.system(size: 48))
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
