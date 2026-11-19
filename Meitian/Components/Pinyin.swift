import SwiftUI

/// Settings shared through @AppStorage (kept out of the save file so old saves still load).
enum PinyinPrefs {
    static let show = "showPinyin"
    static let toneColors = "toneColors"
}

/// Pinyin helpers. The logic lives in the shared Rust core (meitian_core), so iOS and Android agree.
enum Pinyin {
    /// 1–4, or 5 for the neutral tone.
    static func tone(of syllable: String) -> Int { Int(pinyinTone(syllable: syllable)) }

    /// Splits one pinyin word ("Zhōngguó") into syllables, or nil if it can't.
    static func syllables(_ word: String) -> [String]? { pinyinSyllables(word: word) }

    /// All syllables of a phrase/sentence ("Nǐ hǎo, wǒ jiào Xiǎomíng.") or nil.
    static func allSyllables(_ text: String) -> [String]? { pinyinAllSyllables(text: text) }

    /// Cheap per-character check used when filtering text in views.
    static func isHanzi(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
    }

    static func toneColor(_ tone: Int) -> Color {
        switch tone {
        case 1: return Color(red: 0.92, green: 0.26, blue: 0.27)  // high & flat
        case 2: return Color(red: 0.96, green: 0.58, blue: 0.10)  // rising
        case 3: return Color(red: 0.13, green: 0.66, blue: 0.42)  // dip
        case 4: return Color(red: 0.25, green: 0.47, blue: 0.96)  // falling
        default: return .secondary                              // neutral
        }
    }
}

/// Pinyin with each syllable colored by tone (when tone colors are on).
struct PinyinText: View {
    let pinyin: String
    var font: Font = .rounded(.body, weight: .semibold)
    var color: Color? = nil
    @AppStorage(PinyinPrefs.toneColors) private var toneColors = true

    var body: some View {
        Text(attributed).font(font)
    }

    private var attributed: AttributedString {
        guard toneColors else {
            var a = AttributedString(pinyin)
            if let color { a.foregroundColor = color }
            return a
        }
        var result = AttributedString()
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            if let parts = Pinyin.syllables(word) {
                for p in parts {
                    var a = AttributedString(p)
                    a.foregroundColor = Pinyin.toneColor(Pinyin.tone(of: p))
                    result += a
                }
            } else {
                var a = AttributedString(word)
                a.foregroundColor = Pinyin.toneColor(Pinyin.tone(of: word))
                result += a
            }
            word = ""
        }
        for c in pinyin {
            if c.isLetter { word.append(c) } else {
                flush()
                var a = AttributedString(String(c))
                a.foregroundColor = Color.secondary
                result += a
            }
        }
        flush()
        return result
    }
}

/// Characters with their pinyin sitting right above each one (like ruby text in kids' books).
/// Falls back to a pinyin line underneath if the syllables don't line up with the characters.
struct RubyText: View {
    let hanzi: String
    let pinyin: String
    var size: CGFloat = 24
    var weight: Font.Weight = .medium
    /// Show pinyin regardless of the user's setting (e.g. on the answer side of a card).
    var alwaysShow = false
    var alignment: HorizontalAlignment = .leading

    @AppStorage(PinyinPrefs.show) private var showPinyin = true
    @AppStorage(PinyinPrefs.toneColors) private var toneColors = true

    private struct Unit: Identifiable {
        let id: Int
        let char: String
        let syllable: String?
    }

    private var units: [Unit]? {
        rubyUnits(hanzi: hanzi, pinyin: pinyin)?.enumerated().map { i, u in
            Unit(id: i, char: u.character, syllable: u.syllable)
        }
    }

    private func syllableColor(_ s: String?) -> Color {
        guard let s else { return .clear }
        return toneColors ? Pinyin.toneColor(Pinyin.tone(of: s)) : Color.secondary
    }

    var body: some View {
        if !(showPinyin || alwaysShow) {
            Text(hanzi).font(.hanzi(size, weight: weight))
        } else if let units {
            FlowLayout(spacing: size * 0.06, lineSpacing: size * 0.25, alignment: alignment) {
                ForEach(units) { u in
                    VStack(spacing: 0) {
                        Text(u.syllable ?? " ")
                            .font(.system(size: max(size * 0.36, 11), weight: .semibold, design: .rounded))
                            .foregroundStyle(syllableColor(u.syllable))
                            .lineLimit(1)
                            .fixedSize()
                        Text(u.char).font(.hanzi(size, weight: weight))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(hanzi), \(pinyin)")
        } else {
            VStack(alignment: alignment, spacing: 2) {
                Text(hanzi).font(.hanzi(size, weight: weight))
                PinyinText(pinyin: pinyin, font: .system(size: max(size * 0.5, 13), weight: .semibold, design: .rounded))
            }
        }
    }
}

/// Wrapping row layout for ruby units.
struct FlowLayout: Layout {
    var spacing: CGFloat = 2
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + row.height - s.height), proposal: .unspecified)
                x += s.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, sv) in subviews.enumerated() {
            let s = sv.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? s.width : row.width + spacing + s.width
            if needed > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? s.width : row.width + spacing + s.width
            row.height = max(row.height, s.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Little legend explaining the tone colors.
struct ToneLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { i in
                VStack(spacing: 2) {
                    PinyinText(pinyin: ["mā", "má", "mǎ", "mà", "ma"][i], font: .rounded(.headline, weight: .bold))
                    Text(["1 high", "2 rising", "3 dip", "4 falling", "neutral"][i])
                        .font(.rounded(.caption2)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
