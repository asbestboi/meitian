import SwiftUI

/// Colors and type for the whole app. Warm "lantern" palette: vermilion, gold, jade, ink.
enum Theme {
    static let red = Color("Vermilion")
    static let gold = Color("Gold")
    static let jade = Color("Jade")
    static let sky = Color(red: 0.36, green: 0.55, blue: 0.98)
    static let plum = Color(red: 0.62, green: 0.38, blue: 0.95)

    static let background = Color("Paper")
    static let card = Color("Card")

    static let warmGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.42, blue: 0.33), Color(red: 0.91, green: 0.24, blue: 0.27)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.80, blue: 0.35), Color(red: 0.98, green: 0.58, blue: 0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let jadeGradient = LinearGradient(
        colors: [Color(red: 0.25, green: 0.82, blue: 0.62), Color(red: 0.10, green: 0.60, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let skyGradient = LinearGradient(
        colors: [Color(red: 0.45, green: 0.68, blue: 1.0), Color(red: 0.42, green: 0.40, blue: 0.96)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return jade
        case 2: return sky
        case 3: return plum
        default: return red
        }
    }

    static func levelGradient(_ level: Int) -> LinearGradient {
        switch level {
        case 1: return jadeGradient
        case 2: return skyGradient
        case 3: return LinearGradient(colors: [Color(red: 0.75, green: 0.47, blue: 1.0), Color(red: 0.52, green: 0.30, blue: 0.90)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
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
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
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

/// Big, chunky call-to-action button.
struct BigButton: View {
    let title: String
    var systemImage: String? = nil
    var gradient: LinearGradient = Theme.warmGradient
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage).font(.headline) }
                Text(title).font(.rounded(.headline, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(gradient.opacity(enabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(enabled ? 0.15 : 0), radius: 12, y: 6)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Rounded card surface used everywhere.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }
}

extension View {
    func cardSurface(padding: CGFloat = 20) -> some View { modifier(CardSurface(padding: padding)) }
}

/// Small pill label ("HSK 2", "+10 XP").
struct Pill: View {
    let text: String
    var color: Color = Theme.red
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.rounded(.caption, weight: .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }
}
