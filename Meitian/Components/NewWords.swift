import SwiftUI

extension Array where Element == Token {
    /// Word ids of the tokens the learner hasn't learned yet (decided by the core).
    var newIds: [String] { filter(\.isNew).compactMap(\.wordId) }

    /// What VoiceOver reads for a line: "new word" before every new word.
    var spoken: String { map { $0.isNew ? " new word \($0.text) " : renderWechatText(text: $0.text) }.joined() }

    /// One line of text with the new words marked (reply choices).
    @MainActor
    func markedText(size: CGFloat) -> Text {
        reduce(Text(verbatim: "")) { line, t in
            if t.pinyin.isEmpty, let picture = WeChat.inline(t.text, size: size) { return line + picture }
            guard t.isNew else { return line + Text(verbatim: t.text) }
            var a = AttributedString(t.text)
            a.backgroundColor = Theme.lime.opacity(0.3)
            return line + Text(a).underline(true, pattern: .dot, color: Theme.gold)
        }
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
        return p
    }
}

/// Running text: lime behind the characters and a dotted gold underline mark a new word.
struct NewWordMark: ViewModifier {
    var on = true

    func body(content: Content) -> some View {
        content
            .background(Theme.lime.opacity(on ? 0.3 : 0), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .bottom) {
                if on {
                    HorizontalLine()
                        .stroke(Theme.gold, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 4]))
                        .frame(height: 2)
                }
            }
    }
}

/// "NEW" pill for a word's first appearance on a flashcard or quiz card (the sparkle stays still under Reduce Motion).
struct NewBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Sparkle(size: 12, color: .black)
            Text("NEW").font(.system(.caption, weight: .black)).foregroundStyle(.black)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(red: 0.78, green: 1.0, blue: 0.24), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("new word")
    }
}

/// After a story: its new words with pinyin, meaning and audio.
struct NewWordsRecap: View {
    let words: [Word]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("new words in this story").font(.rounded(.headline, weight: .bold))
                Spacer()
                NewBadge()
            }
            ForEach(words) { w in
                HStack(spacing: 12) {
                    Text(w.hanzi).font(.hanzi(28, weight: .semibold))
                        .padding(.horizontal, 4)
                        .modifier(NewWordMark())
                    VStack(alignment: .leading, spacing: 2) {
                        PinyinText(pinyin: w.pinyin, font: .rounded(.subheadline, weight: .bold))
                        Text(w.meaning).font(.rounded(.footnote)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    SpeakButton(text: w.hanzi, size: 38, tint: Theme.sky)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
    }
}
