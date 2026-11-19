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

/// The built-in vocabulary, compiled into the shared Rust core: HSK 1–4 plus the opt-in street deck.
enum WordBank {
    static let streetLevel = 5
    /// Regular vocabulary only. Street words live in `swears`.
    static let all: [Word] = allWords().map(Word.init)
    static let swears: [Word] = swearWords().map(Word.init)
    static let byId: [String: Word] = Dictionary(uniqueKeysWithValues: (all + swears).map { ($0.id, $0) })
    static let levels = [1, 2, 3, 4]

    static func words(level: Int) -> [Word] { level == streetLevel ? swears : all.filter { $0.level == level } }
    static func word(_ id: String) -> Word? { byId[id] }

    /// Words a learner with the given swear setting may see.
    static func visible(swears on: Bool) -> [Word] { on ? all + swears : all }

    static let levelNames: [Int: String] = [
        0: "New Explorer",
        1: "Seedling",
        2: "Sprout",
        3: "Bamboo",
        4: "Dragon",
        5: "Street",
    ]

    static func levelTitle(_ level: Int) -> String { levelNames[level] ?? "Dragon" }
}
