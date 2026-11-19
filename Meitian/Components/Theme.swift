import SwiftUI

/// The "street" look: concrete paper, ink outlines, hard offset shadows, condensed heavy type,
/// sticker tags and loud flat colors. Colors live in the asset catalog so they adapt to dark mode.
enum Theme {
    static let red = Color("Vermilion")
    static let gold = Color("Gold")
    static let jade = Color("Jade")
    static let ink = Color("Ink")
    static let sky = Color(red: 0.20, green: 0.44, blue: 1.0)
    static let plum = Color(red: 0.62, green: 0.33, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.20, blue: 0.55)

    static let background = Color("Paper")
    static let card = Color("Card")

    /// Corner radius: tighter than iOS defaults, it reads rougher.
    static let radius: CGFloat = 14

    private static func g(_ a: Color, _ b: Color) -> LinearGradient {
        LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let warmGradient = g(Color(red: 1.0, green: 0.36, blue: 0.20), Color(red: 0.88, green: 0.11, blue: 0.16))
    static let goldGradient = g(Color(red: 1.0, green: 0.66, blue: 0.10), Color(red: 0.92, green: 0.42, blue: 0.0))
    static let jadeGradient = g(Color(red: 0.16, green: 0.76, blue: 0.40), Color(red: 0.05, green: 0.52, blue: 0.27))
    static let skyGradient = g(Color(red: 0.26, green: 0.52, blue: 1.0), Color(red: 0.17, green: 0.23, blue: 0.86))
    static let pinkGradient = g(Color(red: 1.0, green: 0.36, blue: 0.62), Color(red: 0.86, green: 0.07, blue: 0.43))
    static let inkGradient = g(Color(red: 0.22, green: 0.22, blue: 0.22), Color(red: 0.05, green: 0.05, blue: 0.05))

    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return jade
        case 2: return sky
        case 3: return plum
        case 5: return pink
        default: return red
        }
    }

    static func levelGradient(_ level: Int) -> LinearGradient {
        switch level {
        case 1: return jadeGradient
        case 2: return skyGradient
        case 3: return g(Color(red: 0.72, green: 0.45, blue: 1.0), Color(red: 0.48, green: 0.22, blue: 0.92))
        case 5: return pinkGradient
        default: return warmGradient
        }
    }

    /// Default UI spring: critically damped, no overshoot.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// Momentum spring: a little bounce, only after a gesture carried energy.
    static let bouncy = Animation.spring(response: 0.36, dampingFraction: 0.78)
}

extension Font {
    static func hanzi(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// App text style. Bold and heavier weights go condensed: the streetwear poster look.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let heavy = weight == .bold || weight == .heavy || weight == .black
        return heavy ? .system(style, design: .default, weight: weight == .bold ? .heavy : .black).width(.condensed)
                     : .system(style, design: .default, weight: weight)
    }

    /// Big poster headline.
    static func street(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }
}

/// Instant press feedback (on touch-down), springing back on release.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : Theme.bouncy, value: configuration.isPressed)
    }
}

/// Button that sits on a hard ink shadow and gets pushed down into it when pressed.
struct HardPressStyle: ButtonStyle {
    var radius: CGFloat = Theme.radius
    var depth: CGFloat = 5
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .offset(y: configuration.isPressed ? depth - 1 : 0)
            .background(shape.fill(Theme.ink).offset(y: depth))
            .animation(configuration.isPressed ? .easeOut(duration: 0.06) : Theme.bouncy, value: configuration.isPressed)
    }
}

/// Big, chunky call-to-action button.
struct BigButton: View {
    let title: String
    var systemImage: String? = nil
    var gradient: LinearGradient = Theme.warmGradient
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage).font(.headline.weight(.black)) }
                Text(title.uppercased())
                    .font(.system(.title3, weight: .black).width(.condensed))
                    .tracking(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gradient, in: shape)
            .overlay(shape.stroke(Theme.ink, lineWidth: 3))
            .overlay(GrainOverlay(opacity: 0.12).clipShape(shape))
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(HardPressStyle())
        .padding(.bottom, 5)
        .disabled(!enabled)
    }
}

/// Card surface used everywhere: ink outline + hard offset shadow.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        content
            .padding(padding)
            .background(Theme.card, in: shape)
            .overlay(shape.stroke(Theme.ink, lineWidth: 2.5))
            .background(shape.fill(Theme.ink).offset(x: 4, y: 5))
            .padding(.trailing, 4)
            .padding(.bottom, 5)
    }
}

extension View {
    func cardSurface(padding: CGFloat = 20) -> some View { modifier(CardSurface(padding: padding)) }

    /// Loud colored block with ink outline and hard shadow (hero cards).
    func streetBlock<S: ShapeStyle>(_ fill: S, padding: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous)
        return self
            .padding(padding)
            .background(fill, in: shape)
            .overlay(GrainOverlay(opacity: 0.14).clipShape(shape).allowsHitTesting(false))
            .overlay(shape.stroke(Theme.ink, lineWidth: 3))
            .background(shape.fill(Theme.ink).offset(x: 5, y: 6))
            .padding(.trailing, 5)
            .padding(.bottom, 6)
    }
}

/// Sticker tag ("HSK 2", "+10 XP"): solid color, ink outline, slightly crooked.
struct Pill: View {
    let text: String
    var color: Color = Theme.red
    var systemImage: String? = nil
    var tilt: Double = -2
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text.uppercased())
        }
        .font(.system(.caption, weight: .black).width(.condensed))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.ink, lineWidth: 1.5))
        .rotationEffect(.degrees(tilt))
    }
}

/// Strip of masking tape, for slapping onto cards.
struct TapeStrip: View {
    var width: CGFloat = 70
    var angle: Double = -6
    var body: some View {
        Rectangle()
            .fill(Color(red: 0.96, green: 0.92, blue: 0.70).opacity(0.85))
            .overlay(GrainOverlay(opacity: 0.25))
            .frame(width: width, height: 22)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Printed-paper grain. Drawn once from a fixed seed and rasterized, so it's cheap.
struct GrainOverlay: View {
    var opacity: Double = 0.06
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = rnd() * size.width
                let y = rnd() * size.height
                let s = 0.6 + rnd() * 1.4
                let dark = rnd() > 0.45
                ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                         with: .color(dark ? .black : .white))
            }
            // a few scuffs
            for _ in 0..<Int(size.width / 40) {
                let x = rnd() * size.width
                let y = rnd() * size.height
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + rnd() * 30 - 15, y: y + rnd() * 6 - 3))
                ctx.stroke(p, with: .color(.black), lineWidth: 0.6)
            }
        }
        .opacity(opacity)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
