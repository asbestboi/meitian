import Foundation
import Observation

struct Word: Identifiable, Hashable, Codable {
    let id: String
    let level: Int
    let hanzi: String
    let pinyin: String
    let meaning: String
    let example: String
    let examplePinyin: String
    let exampleMeaning: String
    /// Street words only: 1 = mild, 2 = rude, 3 = very strong.
    var intensity: Int = 0

    /// First meaning only ("to want, to think" -> "to want").
    var shortMeaning: String {
        meaning.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? meaning
    }

    var isSwear: Bool { level == WordBank.streetLevel }
    var levelLabel: String { isSwear ? "STREET 🤬" : "HSK \(level)" }
    var intensityLabel: String { ["", "mild", "rude", "very strong"][min(max(intensity, 0), 3)] }
}

extension Word {
    init(_ c: CoreWord) {
        self.init(id: c.id, level: Int(c.level), hanzi: c.hanzi, pinyin: c.pinyin, meaning: c.meaning,
                  example: c.example, examplePinyin: c.examplePinyin, exampleMeaning: c.exampleMeaning,
                  intensity: Int(c.intensity))
    }

    var core: CoreWord {
        CoreWord(id: id, level: UInt8(level), hanzi: hanzi, pinyin: pinyin, meaning: meaning, example: example,
                 examplePinyin: examplePinyin, exampleMeaning: exampleMeaning, intensity: UInt8(intensity))
    }
}

/// App-wide settings stored with @AppStorage (kept out of the save files so old saves still load).
enum Prefs {
    static let swears = "swearWords"
    static let sounds = "soundEffects"
    static let listening = "listeningExercises"
    static let speaking = "speakingExercises"
    /// "Can't listen / speak right now": timestamps until which those exercises are paused.
    static let noListenUntil = "noListenUntil"
    static let noSpeakUntil = "noSpeakUntil"

    static var swearsOn: Bool { UserDefaults.standard.bool(forKey: swears) }

    static var canListen: Bool {
        let d = UserDefaults.standard
        let on = d.object(forKey: listening) as? Bool ?? true
        return on && Date.now.timeIntervalSince1970 > d.double(forKey: noListenUntil)
    }

    static var canSpeak: Bool {
        let d = UserDefaults.standard
        let on = d.object(forKey: speaking) as? Bool ?? true
        return on && Date.now.timeIntervalSince1970 > d.double(forKey: noSpeakUntil)
    }

    static func pauseListening(minutes: Double = 60) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 + minutes * 60, forKey: noListenUntil)
    }

    static func pauseSpeaking(minutes: Double = 60) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970 + minutes * 60, forKey: noSpeakUntil)
    }
}

/// Live word lists: the bundled words plus downloaded content packs. Observable, so views that read
/// `WordBank.all` refresh when a pack finishes loading.
@Observable
final class WordStore {
    private(set) var all: [Word] = []
    private(set) var swears: [Word] = []
    private(set) var byId: [String: Word] = [:]
    private(set) var levels: [Int] = [1, 2, 3, 4]

    init() { reload() }

    /// Re-reads the Rust word bank (call on the main thread after loading content).
    func reload() {
        all = allWords().map(Word.init)
        swears = swearWords().map(Word.init)
        byId = Dictionary((all + swears).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let l = wordLevels().map(Int.init)
        levels = l.isEmpty ? [1, 2, 3, 4] : l
    }
}

/// The vocabulary from the shared Rust core: bundled basics, downloaded HSK 1–6 packs and the opt-in street deck.
enum WordBank {
    static let store = WordStore()
    static let streetLevel = Int(Meitian.streetLevel())
    /// Regular vocabulary only. Street words live in `swears`.
    static var all: [Word] { store.all }
    static var swears: [Word] { store.swears }
    static var levels: [Int] { store.levels }
    static var maxLevel: Int { store.levels.last ?? 4 }

    static func words(level: Int) -> [Word] { level == streetLevel ? swears : all.filter { $0.level == level } }
    static func word(_ id: String) -> Word? { store.byId[id] }

    /// Words a learner with the given swear setting may see.
    static func visible(swears on: Bool) -> [Word] { on ? all + swears : all }

    static let levelNames: [Int: String] = [
        0: "New Explorer",
        1: "Seedling",
        2: "Sprout",
        3: "Bamboo",
        4: "Dragon",
        5: "Phoenix",
        6: "Master",
    ]

    static func levelTitle(_ level: Int) -> String { level == streetLevel ? "Street" : levelNames[min(level, 6)] ?? "Dragon" }
}
