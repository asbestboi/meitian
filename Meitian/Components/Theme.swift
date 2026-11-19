import SwiftUI

/// "Quiet base, loud accents": off-white / near-black surfaces, soft cards without outlines,
/// big hanzi, bold lowercase-friendly type, and one hypercolor accent (acid lime, hot pink) per surface.
/// Colors live in the asset catalog so they adapt to dark mode.
enum Theme {
    static let red = Color("Vermilion")
    static let gold = Color("Gold")
    static let jade = Color("Jade")
    static let ink = Color("Ink")
    static let lime = Color("Lime")
    static let hot = Color("Hot")
    static let sky = Color(red: 0.24, green: 0.48, blue: 1.0)
    static let plum = Color(red: 0.58, green: 0.36, blue: 1.0)
    static let pink = hot

    static let background = Color("Paper")
    static let card = Color("Card")

    static let radius: CGFloat = 24

    private static func g(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Hypercolor gradients for hero surfaces and rewards.
    static let warmGradient = g(Color(red: 1.0, green: 0.42, blue: 0.30), Color(red: 1.0, green: 0.18, blue: 0.47))
    static let goldGradient = g(Color(red: 1.0, green: 0.80, blue: 0.20), Color(red: 1.0, green: 0.52, blue: 0.10))
    static let jadeGradient = g(Color(red: 0.30, green: 0.88, blue: 0.55), Color(red: 0.05, green: 0.66, blue: 0.48))
    static let skyGradient = g(Color(red: 0.33, green: 0.60, blue: 1.0), Color(red: 0.42, green: 0.32, blue: 1.0))
    static let pinkGradient = g(Color(red: 1.0, green: 0.42, blue: 0.75), Color(red: 0.70, green: 0.30, blue: 1.0))
    static let limeGradient = g(Color(red: 0.86, green: 1.0, blue: 0.36), Color(red: 0.55, green: 0.95, blue: 0.45))
    /// Adapts to dark mode: black in light, off-white in dark.
    static let inkGradient = LinearGradient(colors: [Color("Ink"), Color("Ink")], startPoint: .top, endPoint: .bottom)
    /// Fixed dark hero surface (stays dark in both modes) for the loud-accent cards.
    static let nightGradient = g(Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.04))
    /// Iridescent "chrome" for rewards (coins, level-ups, victory).
    static let chrome = LinearGradient(
        colors: [Color(red: 0.80, green: 0.95, blue: 1.0), Color(red: 0.98, green: 0.80, blue: 1.0),
                 Color(red: 0.85, green: 1.0, blue: 0.80), Color(red: 0.80, green: 0.86, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return jade
        case 2: return sky
        case 3: return plum
        case 4: return red
        case 5: return gold
        case 6: return hot
        default: return hot
        }
    }

    static func levelGradient(_ level: Int) -> LinearGradient {
        switch level {
        case 1: return jadeGradient
        case 2: return skyGradient
        case 3: return g(Color(red: 0.72, green: 0.48, blue: 1.0), Color(red: 0.45, green: 0.28, blue: 0.95))
        case 4: return warmGradient
        case 5: return goldGradient
        default: return pinkGradient
        }
    }

    /// Default UI spring: critically damped, no overshoot.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// Momentum spring: a little bounce, after a gesture carried energy or for playful reveals.
    static let bouncy = Animation.spring(response: 0.36, dampingFraction: 0.72)
}

extension Font {
    static func hanzi(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// App text style: SF Pro, bold weights go heavy for strong but clean headings.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let w: Font.Weight = weight == .bold ? .bold : weight == .heavy || weight == .black ? .heavy : weight
        return .system(style, design: .default, weight: w)
    }

    /// Big display headline.
    static func street(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy)
    }
}

/// Instant press feedback (on touch-down), springing back on release.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : Theme.bouncy, value: configuration.isPressed)
    }
}

/// Kept for call sites: now the same soft press as everything else.
struct HardPressStyle: ButtonStyle {
    var radius: CGFloat = Theme.radius
    var depth: CGFloat = 5
    func makeBody(configuration: Configuration) -> some View {
        PressableStyle(scale: 0.96).makeBody(configuration: configuration)
    }
}

/// Big call-to-action: a full-width capsule. Default is ink (black / off-white); pass a gradient for
/// a colorful one.
struct BigButton: View {
    let title: String
    var systemImage: String? = nil
    var gradient: LinearGradient? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title.lowercased())
                    .font(.system(.title3, weight: .bold))
                if let systemImage { Image(systemName: systemImage).font(.headline.weight(.bold)) }
            }
            .foregroundStyle(gradient == nil ? Theme.background : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(gradient ?? Theme.inkGradient, in: Capsule())
            .shadow(color: .black.opacity(enabled ? 0.12 : 0), radius: 12, y: 6)
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .disabled(!enabled)
    }
}

/// Card surface used everywhere: white / graphite, big corner radius, one soft shadow, no outline.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

extension View {
    func cardSurface(padding: CGFloat = 20) -> some View { modifier(CardSurface(padding: padding)) }

    /// Hero block: a big colored surface (gradient or ink) with soft depth.
    func streetBlock<S: ShapeStyle>(_ fill: S, padding: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous)
        return self
            .padding(padding)
            .background(fill, in: shape)
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
    }
}

/// Small tag ("HSK 2", "+10 XP"): tinted capsule, no outline.
struct Pill: View {
    let text: String
    var color: Color = Theme.ink
    var systemImage: String? = nil
    var tilt: Double = 0
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text.lowercased())
        }
        .font(.system(.caption, weight: .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// ✦ sparkle accent, gently twinkling. A nod to the internet-pop vibe; used sparingly.
struct Sparkle: View {
    var size: CGFloat = 14
    var color: Color = Theme.lime
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("✦")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(color)
            .scaleEffect(on ? 1 : 0.6)
            .opacity(on ? 1 : 0.5)
            .rotationEffect(.degrees(on ? 20 : 0))
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
            }
            .accessibilityHidden(true)
    }
}

/// Removed from the look; kept so old call sites compile.
struct TapeStrip: View {
    var width: CGFloat = 70
    var angle: Double = -6
    var body: some View { EmptyView() }
}

/// Removed from the look; kept so old call sites compile.
struct GrainOverlay: View {
    var opacity: Double = 0.06
    var body: some View { Color.clear.allowsHitTesting(false).accessibilityHidden(true) }
}
