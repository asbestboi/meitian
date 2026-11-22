import SwiftUI

/// Today: XP earned today on its way to the next milestone. There's always a next one.
struct MilestoneCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let p = store.milestoneProgress
        let xpToday = max(store.today.xp, 0)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("today's milestones").font(.rounded(.headline, weight: .bold))
                Sparkle(size: 11, color: Theme.gold)
                Spacer()
                Text("\(xpToday) XP today").font(.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.gold).contentTransition(.numericText())
            }
            HStack(spacing: 12) {
                Text(p.next.emoji).font(.system(size: 30))
                    .frame(width: 52, height: 52)
                    .background(Theme.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(p.next.title).font(.rounded(.subheadline, weight: .bold))
                        Spacer()
                        Text("\(xpToday) / \(p.next.xp)").font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.gold.opacity(0.15))
                            Capsule().fill(Theme.goldGradient)
                                .frame(width: max(10, geo.size.width * CGFloat(min(max(p.progress, 0), 1))))
                        }
                    }
                    .frame(height: 10)
                    .animation(Theme.bouncy, value: p.progress)
                    Text("+\(p.next.bonus) bonus XP when you get there")
                        .font(.rounded(.caption)).foregroundStyle(.secondary)
                }
            }
            if p.reached > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(1...Int(p.reached), id: \.self) { i in
                            let m = milestoneAt(index: UInt32(i))
                            Text("\(m.emoji) \(m.title)")
                                .font(.rounded(.caption, weight: .bold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.gold.opacity(0.14), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .cardSurface(padding: 16)
    }
}

/// Pops up over everything when a milestone is reached, one at a time.
struct MilestoneCelebration: View {
    @Environment(AppStore.self) private var store
    @State private var confetti = 0

    var body: some View {
        ZStack {
            if let m = store.milestoneQueue.first {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { dismiss() }
                VStack(spacing: 10) {
                    Text(m.emoji).font(.system(size: 72))
                    Text("milestone \(m.index)").font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
                    Text(m.title).font(.rounded(.title, weight: .heavy))
                    Text("\(m.xp) XP today ✦ +\(m.bonus) bonus XP")
                        .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(Theme.gold)
                    let next = milestoneAt(index: m.index + 1)
                    Text("next up: \(next.emoji) \(next.title) at \(next.xp) XP")
                        .font(.rounded(.footnote)).foregroundStyle(.secondary)
                    BigButton(title: "keep going", systemImage: "arrow.right") { dismiss() }
                        .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 340)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius + 6, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
                .padding(24)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .id(m.index)
                .onAppear { confetti += 1 }
            }
            ConfettiView(trigger: confetti, sound: .milestone).allowsHitTesting(false)
        }
        .animation(Theme.bouncy, value: store.milestoneQueue.first?.index)
        .haptic(.success, trigger: confetti)
    }

    private func dismiss() {
        guard !store.milestoneQueue.isEmpty else { return }
        store.milestoneQueue.removeFirst()
    }
}
