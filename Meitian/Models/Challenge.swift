import Foundation

/// A daily speaking challenge built around one word and one friend.
struct Challenge {
    let word: Word
    let friend: FriendKind
    let title: String
    let mission: String
    let steps: [String]
    let bonus: String

    /// Stable number for a given day, so the challenge doesn't reshuffle on every launch.
    static func seed(_ key: String) -> Int {
        key.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
    }

    static func make(dayKey: String, words: [Word], friend: FriendKind) -> Challenge? {
        guard !words.isEmpty else { return nil }
        let s = seed(dayKey)
        let word = words[s % words.count]
        let w = "\(word.hanzi) (\(word.pinyin))"
        switch friend {
        case .chinese:
            let options: [(String, String, [String], String)] = [
                ("Ask, don't tell",
                 "Ask your Chinese friend a question that uses \(w).",
                 ["Say the example sentence out loud three times.",
                  "Turn it into a question: add 吗 (ma) or use 什么 (shénme, what) / 为什么 (wèishénme, why).",
                  "Ask your friend and listen to the full answer."],
                 "Bonus: ask them to correct your tones."),
                ("Sneak it in",
                 "Slip \(w) into a normal conversation with a Chinese speaker without announcing it.",
                 ["Practice the example sentence until it feels natural.",
                  "Wait for the right moment in your chat.",
                  "Use it! Did they react or reply naturally?"],
                 "Bonus: get them to use the word back to you."),
                ("Native remix",
                 "Ask a Chinese friend to make their own sentence with \(w), then repeat it back.",
                 ["Say: “你能用「\(word.hanzi)」造个句子吗？” (Nǐ néng yòng “\(word.pinyin)” zào ge jùzi ma? Can you make a sentence with it?)",
                  "Listen, then repeat their sentence exactly.",
                  "Ask what it means if you're unsure: “这是什么意思？” (Zhè shì shénme yìsi? What does it mean?)"],
                 "Bonus: write their sentence down in the notes."),
                ("Voice message",
                 "Send a Chinese friend a voice message that uses \(w).",
                 ["Listen to the pronunciation in the app (tap the speaker).",
                  "Record a short voice message using the word.",
                  "Ask them to reply in Chinese."],
                 "Bonus: understand their reply without a translator."),
            ]
            let o = options[(s / 7) % options.count]
            return Challenge(word: word, friend: friend, title: o.0, mission: o.1, steps: o.2, bonus: o.3)
        case .nonChinese:
            let options: [(String, String, [String], String)] = [
                ("Be the teacher",
                 "Teach a friend who doesn't speak Chinese how to say \(w).",
                 ["Say the word slowly and show the tone with your hand.",
                  "Have them repeat it until they get it.",
                  "Tell them what it means and use it in the example sentence."],
                 "Bonus: they still remember it tomorrow."),
                ("Charades",
                 "Say \(w) to a friend and act it out until they guess the meaning.",
                 ["Say the word out loud, no English allowed.",
                  "Mime, point, draw, whatever it takes.",
                  "Reveal the meaning and say the full example sentence."],
                 "Bonus: they guess in under 30 seconds."),
                ("Secret code",
                 "Agree with a friend to use \(w) as your secret word for today.",
                 ["Teach them the word and its meaning.",
                  "Use it at least twice during the day instead of the English word.",
                  "Say the example sentence to them once."],
                 "Bonus: they use it on you first."),
                ("Language swap",
                 "Use \(w) in a sentence with a friend, then learn a word from their language in return.",
                 ["Say the example sentence and translate it.",
                  "Ask them for the same word in their language.",
                  "Note down their word in the notes field."],
                 "Bonus: make a mixed-language sentence together."),
            ]
            let o = options[(s / 7) % options.count]
            return Challenge(word: word, friend: friend, title: o.0, mission: o.1, steps: o.2, bonus: o.3)
        }
    }
}

/// One multiple-choice question.
struct QuizQuestion: Identifiable {
    enum Kind { case hanziToMeaning, meaningToHanzi, listenToHanzi, speak }
    let id = UUID()
    let word: Word
    let kind: Kind
    let options: [Word]

    var prompt: String {
        switch kind {
        case .hanziToMeaning: return "What does this mean?"
        case .meaningToHanzi: return "Which one means…"
        case .listenToHanzi: return "Tap what you hear"
        case .speak: return "Say it out loud"
        }
    }

    /// Question types to mix into a quiz, respecting "can't listen / speak now".
    static func mixedKinds() -> [Kind] {
        var k: [Kind] = [.hanziToMeaning, .meaningToHanzi]
        if Prefs.canListen { k.append(.listenToHanzi) }
        if Prefs.canSpeak { k.append(.speak) }
        return k
    }

    /// The same question, swapped to a silent type if listening/speaking got paused meanwhile.
    func adjusted() -> QuizQuestion {
        if kind == .listenToHanzi && !Prefs.canListen {
            return QuizQuestion(word: word, kind: .meaningToHanzi, options: options)
        }
        if kind == .speak && !Prefs.canSpeak {
            return QuizQuestion(word: word, kind: .hanziToMeaning, options: options)
        }
        return self
    }

    func label(for option: Word) -> String {
        kind == .hanziToMeaning ? option.shortMeaning : option.hanzi
    }

    static func make(for word: Word, kind: Kind, pool: [Word]) -> QuizQuestion {
        var distractors = pool.filter { $0.id != word.id && $0.shortMeaning != word.shortMeaning && $0.hanzi != word.hanzi }.shuffled()
        if distractors.count < 3 {
            distractors += WordBank.all.filter { $0.id != word.id && !distractors.contains($0) }.shuffled()
        }
        let options = ([word] + distractors.prefix(3)).shuffled()
        return QuizQuestion(word: word, kind: kind, options: options)
    }
}

/// Placement test: three questions per level, easiest first.
enum Placement {
    static func questions() -> [QuizQuestion] {
        var qs: [QuizQuestion] = []
        for level in WordBank.levels {
            let pool = WordBank.words(level: level)
            let kinds: [QuizQuestion.Kind] = [.hanziToMeaning, .meaningToHanzi, .hanziToMeaning]
            for (i, w) in pool.shuffled().prefix(3).enumerated() {
                qs.append(QuizQuestion.make(for: w, kind: kinds[i], pool: pool))
            }
        }
        return qs
    }

    /// Highest level whose questions (and all below) were mostly right.
    static func confirmedLevel(results: [(level: Int, right: Bool)]) -> Int {
        var confirmed = 0
        for level in WordBank.levels {
            let r = results.filter { $0.level == level }
            let score = r.filter(\.right).count
            if score >= 2 { confirmed = level } else { break }
        }
        return confirmed
    }
}
