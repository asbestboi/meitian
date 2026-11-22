import Observation
import SwiftUI

/// How far something scrolled, readable by a background without redrawing the rest of the screen.
@Observable
final class ScrollOffset {
    var y: CGFloat = 0
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private final class SceneParticles {
    let system = ParticleSystem()
    var debt = 0.0
}

/// An arena's scenery (sky, three silhouettes, drifting particles), drawn from the core's numbers. `strength` fades
/// it into the paper colour so text on top stays readable; `scroll` moves the silhouettes a little (parallax).
struct ArenaBackground: View {
    let theme: ArenaTheme
    var strength: Double = 0.55
    var scroll: ScrollOffset? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles = SceneParticles()

    var body: some View {
        let look = arenaLook(theme: theme)
        let dark = scheme == .dark
        let offset = reduceMotion ? 0 : (scroll?.y ?? 0)
        ZStack {
            LinearGradient(colors: (dark ? look.skyDark : look.skyLight).map { Color(hex: $0) }, startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for layer in look.layers {
                    let limit = size.height * 0.12
                    let shift = min(max(-offset * CGFloat(layer.parallax), -limit), limit)
                    ctx.fill(silhouette(layer.heights, size, shift), with: .color(Color(hex: dark ? layer.colorDark : layer.colorLight)))
                }
            }
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    Canvas { ctx, size in
                        drift(look, now: tl.date, size: size)
                        particles.system.draw(&ctx, spec: look.particles)
                    }
                }
            }
            Theme.background.opacity(1 - strength)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func silhouette(_ heights: [Float], _ size: CGSize, _ shift: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: size.height))
        for (i, h) in heights.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(max(heights.count - 1, 1))
            p.addLine(to: CGPoint(x: x, y: size.height - size.height * CGFloat(h) + shift))
        }
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.closeSubpath()
        return p
    }

    private func drift(_ look: ArenaLook, now: Date, size: CGSize) {
        let dt = particles.system.step(to: now, gravity: Double(look.particles.gravity))
        particles.debt += Double(look.particles.rate) * dt
        while particles.debt >= 1 {
            particles.debt -= 1
            let y = look.rising ? size.height * CGFloat.random(in: 0.75...1) : -10
            particles.system.burst(look.particles, at: CGPoint(x: CGFloat.random(in: 0...max(size.width, 1)), y: y), count: 1,
                                   direction: look.rising ? -Double.pi / 2 : Double.pi / 2)
        }
    }
}

/// Rank badge: the arena somebody plays in.
struct ArenaBadge: View {
    let theme: ArenaTheme
    var fill: Color = Theme.card

    var body: some View {
        HStack(spacing: 5) {
            Text(theme.emoji)
            Text("\(theme.nameZh) · \(theme.nameEn)").lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.rounded(.caption, weight: .bold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(fill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arena: \(theme.nameEn)")
    }
}

/// Full screen: the learner crossed into a new arena.
struct ArenaReveal: View {
    let theme: ArenaTheme
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var popped = false

    var body: some View {
        // light skies get dark text, hellish ones white
        let ink: Color = scheme == .dark || theme.tier >= 5 ? .white : Color(red: 0.09, green: 0.09, blue: 0.11)
        ZStack {
            ArenaBackground(theme: theme, strength: 1).ignoresSafeArea()
            VStack(spacing: 8) {
                Spacer()
                VStack(spacing: 6) {
                    Text("new arena unlocked!").font(.rounded(.headline, weight: .heavy)).opacity(0.85)
                    Text(theme.emoji).font(.system(size: 88)).accessibilityHidden(true)
                    Text(theme.nameZh).font(.hanzi(58, weight: .black)).multilineTextAlignment(.center)
                    Text(theme.pinyin).font(.rounded(.headline, weight: .bold)).opacity(0.85)
                    Text(theme.nameEn).font(.street(28)).multilineTextAlignment(.center)
                    Text("arena \(theme.tier) of 6").font(.rounded(.subheadline, weight: .bold)).opacity(0.75)
                }
                .foregroundStyle(ink)
                .scaleEffect(popped || reduceMotion ? 1 : 0.4)
                Spacer()
                Spacer()
                BigButton(title: "enter", systemImage: "arrow.right", action: close)
            }
            .padding(24)
        }
        .opacity(shown ? 1 : 0)
        .haptic(.impact(weight: .heavy), trigger: popped)
        .onAppear {
            SFX.shared.play(.arenaUnlock)
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.7)) { shown = true }
            withAnimation(Theme.bouncy.delay(reduceMotion ? 0 : 0.45)) { popped = true }
        }
    }
}
