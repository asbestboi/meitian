import SwiftUI

// MARK: - Confetti

/// Physics confetti burst. Change `trigger` to fire.
struct ConfettiView: View {
    var trigger: Int
    /// Celebration sound played with the burst (nil for silent).
    var sound: SFX.Sound? = .win

    private struct Piece {
        var x, y, vx, vy, spin, angle, size: Double
        var color: Color
        var shape: Int
    }

    @State private var pieces: [Piece] = []
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: pieces.isEmpty)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let x = p.x * size.width + p.vx * t
                    let y = p.y * size.height + p.vy * t + 900 * t * t / 2
                    guard y < size.height + 40 else { continue }
                    let fade = max(0, 1 - t / 2.6)
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.angle + p.spin * t))
                    let r = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / (p.shape == 0 ? 2 : 1))
                    let path = p.shape == 2 ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: 2)
                    c.fill(path, with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
        .ignoresSafeArea()
    }

    private func fire() {
        if let sound { SFX.shared.play(sound) }
        guard !reduceMotion else { return }
        let colors: [Color] = [Theme.red, Theme.gold, Theme.jade, Theme.sky, Theme.plum, .pink]
        start = .now
        pieces = (0..<90).map { _ in
            Piece(x: Double.random(in: 0.3...0.7), y: 0.35,
                  vx: Double.random(in: -380...380), vy: Double.random(in: -900 ... -350),
                  spin: Double.random(in: -8...8), angle: Double.random(in: 0...6),
                  size: Double.random(in: 7...13), color: colors.randomElement()!, shape: Int.random(in: 0...2))
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if Date.now.timeIntervalSince(start) >= 2.7 { pieces = [] }
        }
    }
}

// MARK: - Ring

struct ProgressRing<Label: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var gradient: [Color] = [Theme.gold, Theme.red]
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(AngularGradient(colors: gradient + [gradient[0]], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.spring, value: progress)
            label
        }
    }
}

// MARK: - Streak flame

struct StreakBadge: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.gold, Theme.red)
                .symbolEffect(.bounce, value: streak)
            Text("\(streak)").font(.rounded(.headline, weight: .heavy)).contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .accessibilityLabel("\(streak) day streak")
    }
}

struct XPBadge: View {
    let xp: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill").foregroundStyle(Theme.gold)
            Text("\(xp)").font(.rounded(.headline, weight: .heavy)).contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .accessibilityLabel("\(xp) XP")
    }
}

// MARK: - Speaker button

struct SpeakButton: View {
    let text: String
    var size: CGFloat = 44
    var tint: Color = Theme.red
    @State private var tick = 0

    var body: some View {
        Button {
            tick += 1
            Speaker.shared.say(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .symbolEffect(.variableColor.iterative, value: tick)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.13), in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .accessibilityLabel("Play pronunciation")
    }
}

// MARK: - Floating hanzi background

/// Slowly drifting characters behind onboarding. Static when Reduce Motion is on.
struct FloatingHanzi: View {
    let chars = ["你", "好", "学", "爱", "朋", "友", "天", "中", "文", "茶", "猫", "笑"]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ForEach(chars.indices, id: \.self) { i in
                    let fx = Double((i * 37) % 100) / 100
                    let fy = Double((i * 61) % 100) / 100
                    let drift = sin(t / 6 + Double(i)) * 14
                    Text(chars[i])
                        .font(.hanzi(CGFloat(34 + (i * 13) % 40), weight: .bold))
                        .foregroundStyle(Theme.red.opacity(0.07 + Double(i % 3) * 0.025))
                        .position(x: fx * geo.size.width, y: fy * geo.size.height + drift)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
