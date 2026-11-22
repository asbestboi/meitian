import SwiftUI

extension Color {
    /// "#RRGGBB" → Color (falls back to white).
    init(hex: String) {
        var v: UInt64 = 0xFFFFFF
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A hit: something flies from the attacker to the target and lands with a bang. Every frame comes from the core.
/// `from` / `to` are unit coordinates (0…1) inside this view.
struct HitEffectView: View {
    let effectId: String
    let trigger: Int
    var from: UnitPoint = .bottom
    var to: UnitPoint = .top
    var damage: Int? = nil
    /// Also fire for the trigger it's created with (views that appear because of a hit).
    var fireOnAppear = false
    /// Called at impact with the shake strength, so the screen can shake.
    var onImpact: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var damageShown = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let b = CGPoint(x: to.x * size.width, y: to.y * size.height)
            ZStack {
                if let start {
                    TimelineView(.animation) { tl in
                        Canvas { ctx, s in
                            let ms = max(0, tl.date.timeIntervalSince(start) * 1000)
                            let ops = hitFrame(id: effectId, tMs: UInt32(min(ms, 60_000)), w: Float(s.width), h: Float(s.height),
                                               ax: Float(from.x * s.width), ay: Float(from.y * s.height),
                                               bx: Float(to.x * s.width), by: Float(to.y * s.height))
                            OpsRenderer.draw(ops, in: ctx, size: s)
                        }
                    }
                }
                if let d = damage {
                    Text("-\(d)")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                        .scaleEffect(damageShown ? 1 : 0.4)
                        .opacity(damageShown ? 1 : 0)
                        .position(x: b.x, y: b.y + (to.y < 0.5 ? 70 : -70))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
        .onAppear { if fireOnAppear { fire() } }
    }

    private func fire() {
        if reduceMotion {
            // no flying particles: just show the damage
            withAnimation(.easeOut(duration: 0.2)) { damageShown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { damageShown = false } }
            return
        }
        damageShown = false
        let info = hitInfo(id: effectId)
        let began = Date.now
        start = began
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(info.impactMs) / 1000) {
            guard start == began else { return }
            onImpact(CGFloat(info.shake))
            withAnimation(Theme.bouncy) { damageShown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 0.25)) { damageShown = false }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(info.durationMs) / 1000) {
            if start == began { start = nil }
        }
    }
}

/// An idle aura around an avatar (au.* cosmetics). Draws nothing for "no aura".
struct AuraView: View {
    let auraId: String
    var radius: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if hasAura(id: auraId), !reduceMotion {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let ms = UInt64(max(0, tl.date.timeIntervalSinceReferenceDate * 1000))
                    OpsRenderer.draw(auraFrame(id: auraId, tMs: ms, w: Float(size.width), h: Float(size.height), radius: Float(radius)),
                                     in: ctx, size: size)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Screen shake: animate `amount` 0 → 1; the offset decays to zero.
struct ImpactShake: GeometryEffect {
    var amount: CGFloat
    var strength: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let decay = 1 - amount
        let x = strength * decay * sin(amount * .pi * 9)
        let y = strength * 0.5 * decay * cos(amount * .pi * 7)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}
