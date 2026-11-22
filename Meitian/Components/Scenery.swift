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

/// An arena's scenery, drawn by the core: still layers that move a little with `scroll` (parallax) and a moving part
/// on top. `strength` fades it into the paper colour so text on top stays readable.
struct ArenaBackground: View {
    let theme: ArenaTheme
    var strength: Double = 0.55
    var live = true
    var scroll: ScrollOffset? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            ZStack {
                SceneLayers(theme: theme, size: geo.size, dark: dark, offset: reduceMotion ? 0 : (scroll?.y ?? 0))
                if live && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in moving(tl.date, dark: dark) }
                } else {
                    moving(.init(timeIntervalSinceReferenceDate: 0), dark: dark)
                }
                Theme.background.opacity(1 - strength)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func moving(_ now: Date, dark: Bool) -> some View {
        Canvas { ctx, size in
            let ms = UInt64(max(0, now.timeIntervalSinceReferenceDate * 1000))
            OpsRenderer.draw(arenaFrame(theme: theme, tMs: ms, w: Float(size.width), h: Float(size.height), dark: dark), in: ctx, size: size)
        }
    }
}

/// The still layers: computed once per arena and size, drawn once each and only moved while scrolling.
private struct SceneLayers: View {
    let theme: ArenaTheme
    let size: CGSize
    let dark: Bool
    let offset: CGFloat
    @State private var layers: [SceneLayer] = []

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                let limit = size.height * 0.12
                // taller than the view, so moving it up never uncovers its bottom
                Canvas { ctx, _ in OpsRenderer.draw(layer.ops, in: ctx, size: size) }
                    .frame(width: size.width, height: size.height * 1.3)
                    .drawingGroup()
                    .offset(y: size.height * 0.15 + min(max(-offset * CGFloat(layer.parallax), -limit), limit))
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear(perform: load)
        .onChange(of: "\(theme.id)-\(dark)-\(Int(size.width))x\(Int(size.height))") { _, _ in load() }
    }

    private func load() {
        guard size.width > 1, size.height > 1 else { return }
        layers = arenaScene(theme: theme, w: Float(size.width), h: Float(size.height), dark: dark)
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

/// One arena on the road: its scenery, name and what it takes to get there.
struct ArenaPanel: View {
    let stop: ArenaStop
    var height: CGFloat = 400

    var body: some View {
        let locked = stop.state == .locked
        let here = stop.state == .current
        let theme = stop.theme
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            ArenaBackground(theme: theme, strength: 1)
            // locked arenas stay visible, just a little dimmed
            if locked { Color.black.opacity(0.28) }
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom).frame(height: 150)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(theme.emoji) \(theme.nameZh)").font(.hanzi(30, weight: .black))
                Text("\(theme.pinyin) · \(theme.nameEn)").font(.rounded(.subheadline, weight: .bold)).opacity(0.9)
                Text(locked ? "HSK \(stop.level) · pass the HSK \(Int(stop.level) - 1) test" : "HSK \(stop.level)")
                    .font(.rounded(.footnote, weight: .bold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .topLeading) { tag("arena \(theme.tier)", .black.opacity(0.45), .white).padding(14) }
        .overlay(alignment: .topTrailing) {
            Group {
                if locked {
                    Image(systemName: "lock.fill").font(.title3).foregroundStyle(.white)
                        .padding(10).background(.black.opacity(0.45), in: Circle())
                } else {
                    tag(here ? "you are here" : "✓ conquered", here ? Theme.lime : .black.opacity(0.45), here ? .black : .white)
                }
            }
            .padding(14)
        }
        .clipShape(shape)
        .overlay { if here { shape.stroke(Theme.lime, lineWidth: 4) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arena \(theme.tier): \(theme.nameEn). \(locked ? "Locked, unlocks at HSK \(stop.level)" : here ? "You are here" : "Conquered")")
    }

    private func tag(_ text: String, _ fill: Color, _ ink: Color) -> some View {
        Text(text).font(.rounded(.footnote, weight: .heavy)).foregroundStyle(ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(fill, in: Capsule())
    }
}

/// Every arena, the last one at the top: climb from the meadow to the gates of hell.
struct ArenaRoad: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let stops = Array(arenaRoad(level: UInt8(clamping: store.currentLevel), unit: 1).reversed())
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(stops.enumerated()), id: \.element.theme.id) { i, stop in
                        ArenaPanel(stop: stop).id(stop.theme.id)
                        if i < stops.count - 1 {
                            Image(systemName: "chevron.up").font(.title3.weight(.heavy))
                                .foregroundStyle(stop.state == .locked ? Color.secondary : Theme.lime)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .onAppear { if let here = stops.first(where: { $0.state == .current }) { proxy.scrollTo(here.theme.id, anchor: .center) } }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(Theme.card, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .foregroundStyle(.primary)
                .accessibilityLabel("Close")
                Text("arena road").font(.rounded(.title2, weight: .heavy))
                Spacer()
            }
            .padding(16)
            .background(Theme.background.opacity(0.94))
        }
    }
}
