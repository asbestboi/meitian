import SwiftUI

/// Today: three daily quests that pay Arena coins, plus streak freezes to spend them on.
struct QuestCard: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @State private var paid = 0

    var body: some View {
        let quests = store.quests
        VStack(alignment: .leading, spacing: 12) {
            if let saved = store.freezeNotice {
                HStack(spacing: 10) {
                    Text("🧊").font(.title2)
                    Text("A streak freeze saved your \(saved)-day streak!").font(.rounded(.subheadline, weight: .bold))
                    Spacer(minLength: 0)
                    Button { withAnimation(Theme.spring) { store.freezeNotice = nil } } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Theme.sky.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(alignment: .firstTextBaseline) {
                Text("daily quests").font(.rounded(.headline, weight: .bold))
                Sparkle(size: 11, color: Theme.sky)
                Spacer()
                Label("\(arena.coins)", systemImage: "circle.hexagongrid.fill")
                    .font(.rounded(.subheadline, weight: .heavy)).foregroundStyle(Theme.gold)
                    .contentTransition(.numericText())
            }
            ForEach(quests, id: \.quest.id) { q in row(q) }
            Text("finish all three for +\(questsAllDoneBonus()) bonus coins")
                .font(.rounded(.caption)).foregroundStyle(.secondary)
            Divider()
            freezeRow
        }
        .cardSurface(padding: 16)
        .sensoryFeedback(.success, trigger: paid)
    }

    private func row(_ q: QuestStatus) -> some View {
        let claimed = store.isClaimed(q.quest)
        return HStack(spacing: 12) {
            Text(q.quest.emoji).font(.title2)
                .frame(width: 44, height: 44)
                .background(Theme.sky.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(q.quest.title).font(.rounded(.subheadline, weight: .bold))
                    .strikethrough(claimed).foregroundStyle(claimed ? .secondary : .primary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.sky.opacity(0.15))
                        Capsule().fill(q.done ? Theme.jade : Theme.sky)
                            .frame(width: max(8, geo.size.width * CGFloat(q.progress) / CGFloat(max(q.quest.target, 1))))
                    }
                }
                .frame(height: 8)
            }
            if q.done && !claimed {
                Button {
                    let coins = store.claimQuest(q)
                    withAnimation(Theme.bouncy) { arena.coins += coins }
                    arena.save()
                    paid += 1
                    SFX.shared.play(.coin)
                } label: {
                    Text("+\(q.quest.reward)").font(.rounded(.subheadline, weight: .heavy))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.gold, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(PressableStyle(scale: 0.92))
            } else {
                Text(claimed ? "✓" : "\(q.progress)/\(q.quest.target)")
                    .font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
            }
        }
    }

    private var freezeRow: some View {
        let price = Int(streakFreezePrice())
        return HStack(spacing: 10) {
            Text("🧊").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("streak freezes: \(store.freezes)/\(streakFreezeMax())").font(.rounded(.subheadline, weight: .bold))
                Text("covers a missed day so your streak survives").font(.rounded(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if store.canHoldMoreFreezes {
                Button {
                    guard arena.coins >= price else { return }
                    arena.coins -= price
                    arena.save()
                    store.addFreeze()
                    SFX.shared.play(.coin)
                } label: {
                    Label("\(price)", systemImage: "circle.hexagongrid.fill")
                        .font(.rounded(.caption, weight: .heavy))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.sky.opacity(arena.coins >= price ? 0.25 : 0.08), in: Capsule())
                }
                .disabled(arena.coins < price)
                .foregroundStyle(arena.coins >= price ? .primary : .secondary)
            }
        }
    }
}
