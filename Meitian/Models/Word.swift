import Foundation

struct Word: Identifiable, Hashable, Codable {
    let id: String
    let level: Int
    let hanzi: String
    let pinyin: String
    let meaning: String
    let example: String
    let examplePinyin: String
    let exampleMeaning: String

    /// First meaning only ("to want, to think" -> "to want").
    var shortMeaning: String {
        meaning.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? meaning
    }
}

/// The built-in vocabulary, loaded from words.tsv (HSK 1–4 style levels).
enum WordBank {
    static let all: [Word] = load()
    static let byId: [String: Word] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let levels = [1, 2, 3, 4]

    static func words(level: Int) -> [Word] { all.filter { $0.level == level } }
    static func word(_ id: String) -> Word? { byId[id] }

    private static func load() -> [Word] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Word] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7, let level = Int(f[0]) else { continue }
            result.append(Word(id: "\(level)-\(f[1])", level: level, hanzi: f[1], pinyin: f[2], meaning: f[3],
                               example: f[4], examplePinyin: f[5], exampleMeaning: f[6]))
        }
        return result
    }

    static let levelNames: [Int: String] = [
        0: "New Explorer",
        1: "Seedling",
        2: "Sprout",
        3: "Bamboo",
        4: "Dragon",
    ]

    static func levelTitle(_ level: Int) -> String { levelNames[level] ?? "Dragon" }
}
