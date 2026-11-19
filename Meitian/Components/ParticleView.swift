import SwiftUI

extension Color {
    /// "#RRGGBB" → Color (falls back to white).
    init(hex: String) {
        var v: UInt64 = 0xFFFFFF
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A tiny particle simulation, stepped and drawn inside a Canvas. Reference type on purpose:
/// the Canvas closure mutates it every frame without invalidating the view.
final class ParticleSystem {
    struct Particle {
        var pos: CGPoint
        var vel: CGVector
        var age: Double = 0
        var life: Double
        var size: CGFloat
        var color: Color
        var glyph: String?
        var rot: Double
        var spin: Double
    }

    private(set) var particles: [Particle] = []
    private var lastTime: Date?
    private var emitDebt: Double = 0
    static let maxParticles = 320

    var isIdle: Bool { particles.isEmpty }

    func burst(_ spec: EffectSpec, at p: CGPoint, count: Int? = nil, direction: Double = -.pi / 2) {
        let n = count ?? Int(spec.burst)
        for _ in 0..<n { spawn(spec, at: p, direction: direction, speedScale: Double.random(in: 0.35...1)) }
    }

    /// Continuous emission (trails and auras). `dt` in seconds.
    func emit(_ spec: EffectSpec, at p: CGPoint, dt: Double, radius: CGFloat = 0, speedScale: Double = 0.35) {
        emitDebt += Double(spec.rate) * dt
        while emitDebt >= 1 {
            emitDebt -= 1
            let a = Double.random(in: 0..<(2 * .pi))
            let q = CGPoint(x: p.x + CGFloat(Foundation.cos(a)) * radius, y: p.y + CGFloat(Foundation.sin(a)) * radius)
            spawn(spec, at: q, direction: a, speedScale: speedScale)
        }
    }

    private func spawn(_ spec: EffectSpec, at p: CGPoint, direction: Double, speedScale: Double) {
        guard particles.count < Self.maxParticles else { return }
        let spread = Double(spec.spread) * .pi / 180
        let a = direction + Double.random(in: -spread / 2...spread / 2)
        let v = Double(spec.speed) * speedScale
        let glyph: String? = spec.shape == .glyph ? spec.glyphs.randomElement() : nil
        particles.append(Particle(
            pos: p,
            vel: CGVector(dx: cos(a) * v, dy: sin(a) * v),
            life: Double(spec.lifetime) * Double.random(in: 0.7...1.2),
            size: CGFloat(spec.size) * CGFloat.random(in: 0.6...1.3),
            color: Color(hex: spec.colors.randomElement() ?? "#FFFFFF"),
            glyph: glyph,
            rot: Double.random(in: 0..<360),
            spin: Double(spec.spin) * Double.random(in: -1...1)))
    }

    /// Advances the simulation to `now`; returns the elapsed seconds.
    @discardableResult
    func step(to now: Date, gravity: Double) -> Double {
        let dt = min(lastTime.map { now.timeIntervalSince($0) } ?? 0, 1.0 / 20)
        lastTime = now
        guard dt > 0 else { return 0 }
        for i in particles.indices {
            particles[i].age += dt
            particles[i].vel.dy += gravity * dt
            particles[i].vel.dx *= 1 - 1.2 * dt   // air drag
            particles[i].pos.x += particles[i].vel.dx * dt
            particles[i].pos.y += particles[i].vel.dy * dt
            particles[i].rot += particles[i].spin * dt
        }
        particles.removeAll { $0.age >= $0.life }
        return dt
    }

    func draw(_ ctx: inout GraphicsContext, spec: EffectSpec) {
        var glyphCache: [String: GraphicsContext.ResolvedText] = [:]
        if spec.glow { ctx.blendMode = .plusLighter }
        for p in particles {
            let t = p.age / p.life
            let alpha = t < 0.15 ? t / 0.15 : 1 - pow((t - 0.15) / 0.85, 1.6)
            switch spec.shape {
            case .glyph:
                guard let g = p.glyph else { continue }
                var r = glyphCache[g] ?? ctx.resolve(Text(g).font(.system(size: 28)))
                glyphCache[g] = r
                r.shading = .color(p.color)
                var c = ctx
                c.opacity = alpha
                c.translateBy(x: p.pos.x, y: p.pos.y)
                c.rotate(by: .degrees(p.rot))
                let s = p.size / 28
                c.scaleBy(x: s, y: s)
                c.draw(r, at: .zero)
            case .dot:
                let s = p.size * (1 - 0.5 * t)
                ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - s, y: p.pos.y - s, width: s * 2, height: s * 2)),
                         with: .color(p.color.opacity(alpha * 0.35)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - s / 2, y: p.pos.y - s / 2, width: s, height: s)),
                         with: .color(p.color.opacity(alpha)))
            case .streak, .bolt:
                var path = Path()
                path.move(to: p.pos)
                path.addLine(to: CGPoint(x: p.pos.x - p.vel.dx * 0.04, y: p.pos.y - p.vel.dy * 0.04))
                ctx.stroke(path, with: .color(p.color.opacity(alpha)), style: StrokeStyle(lineWidth: max(p.size * 0.6, 1.5), lineCap: .round))
            }
        }
        ctx.blendMode = .normal
    }
}

/// A hit: the attacker's projectile flies to the target leaving a trail, then bursts with
/// flash and shake. `from` / `to` are unit coordinates (0…1) inside this view.
struct HitEffectView: View {
    let effectId: String
    let trigger: Int
    var from: UnitPoint = .bottom
    var to: UnitPoint = .top
    var damage: Int? = nil
    /// Called at impact with the shake strength, so the screen can shake.
    var onImpact: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var system = ParticleSystem()
    @State private var start: Date?
    @State private var impactAt: Date?
    @State private var flash = 0.0
    @State private var damageShown = false
    @State private var boltSeed = 0

    private static let flight = 0.38
    private var spec: EffectSpec { effectSpec(id: effectId) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let a = CGPoint(x: from.x * size.width, y: from.y * size.height)
            let b = CGPoint(x: to.x * size.width, y: to.y * size.height)
            ZStack {
                TimelineView(.animation(paused: start == nil && system.isIdle)) { tl in
                    Canvas { ctx, _ in
                        let s = spec
                        let now = tl.date
                        let dt = system.step(to: now, gravity: Double(s.gravity))
                        if let start {
                            let t = now.timeIntervalSince(start) / Self.flight
                            if t < 1 {
                                let p = arc(a, b, t)
                                if s.rate > 0 { system.emit(s, at: p, dt: dt) }
                                if !s.projectile.isEmpty {
                                    var c = ctx
                                    c.translateBy(x: p.x, y: p.y)
                                    c.scaleBy(x: 1 + t * 0.6, y: 1 + t * 0.6)
                                    c.draw(ctx.resolve(Text(s.projectile).font(.system(size: 54))), at: .zero)
                                }
                            } else {
                                DispatchQueue.main.async { impact(at: b) }
                            }
                        }
                        if s.shape == .bolt, let hit = impactAt, now.timeIntervalSince(hit) < 0.32 {
                            drawBolt(&ctx, a, b, seed: boltSeed &+ Int(now.timeIntervalSince(hit) * 30), color: Color(hex: s.colors.first ?? "#FFFFFF"))
                        }
                        system.draw(&ctx, spec: s)
                    }
                }
                if let d = damage {
                    Text("-\(d)")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        .scaleEffect(damageShown ? 1 : 0.4)
                        .opacity(damageShown ? 1 : 0)
                        .position(x: b.x, y: b.y + (to.y < 0.5 ? 70 : -70))
                }
                Color(hex: spec.flash.isEmpty ? "#FFFFFF" : spec.flash)
                    .opacity(flash)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        if reduceMotion {
            // no flying particles: just show the damage
            withAnimation(.easeOut(duration: 0.2)) { damageShown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { damageShown = false } }
            return
        }
        damageShown = false
        start = .now
        impactAt = nil
    }

    private func impact(at b: CGPoint) {
        guard start != nil else { return }
        start = nil
        impactAt = .now
        boltSeed = Int.random(in: 0...10_000)
        let s = spec
        system.burst(s, at: b, direction: to.y < from.y ? -.pi / 2 : .pi / 2)
        onImpact(CGFloat(s.shake))
        if !s.flash.isEmpty {
            flash = 0.35
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
        }
        withAnimation(Theme.bouncy) { damageShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.25)) { damageShown = false }
        }
    }

    /// Quadratic arc from a to b, bulging sideways for a thrown feel.
    private func arc(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let e = t * t * (3 - 2 * t)   // smoothstep
        let mid = CGPoint(x: (a.x + b.x) / 2 + 90, y: (a.y + b.y) / 2)
        let x = (1 - e) * (1 - e) * a.x + 2 * (1 - e) * e * mid.x + e * e * b.x
        let y = (1 - e) * (1 - e) * a.y + 2 * (1 - e) * e * mid.y + e * e * b.y
        return CGPoint(x: x, y: y)
    }

    private func drawBolt(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, seed: Int, color: Color) {
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed))
        var path = Path()
        path.move(to: a)
        let steps = 12
        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let jitter = (CGFloat(rng.next() % 1000) / 1000 - 0.5) * 70
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t + jitter, y: a.y + (b.y - a.y) * t))
        }
        path.addLine(to: b)
        ctx.blendMode = .plusLighter
        ctx.stroke(path, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        ctx.blendMode = .normal
    }
}

/// Small deterministic RNG (for bolt shapes that flicker but don't jump randomly every frame).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}

/// An idle aura of particles around an avatar (au.* cosmetics). Draws nothing for "no aura".
struct AuraView: View {
    let auraId: String
    var radius: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var system = ParticleSystem()

    var body: some View {
        if let spec = auraSpec(id: auraId), !reduceMotion {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let dt = system.step(to: tl.date, gravity: Double(spec.gravity))
                    system.emit(spec, at: CGPoint(x: size.width / 2, y: size.height / 2), dt: dt, radius: radius, speedScale: 1)
                    system.draw(&ctx, spec: spec)
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
