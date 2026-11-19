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
    static func seed(_ key: String) -> Int { Int(daySeed(dayKey: key)) }

    /// Built by the shared Rust core, so both platforms give the same challenge on the same day.
    static func make(dayKey: String, words: [Word], friend: FriendKind) -> Challenge? {
        guard let c = dailyChallenge(dayKey: dayKey, words: words.map(\.core),
                                     friend: friend == .chinese ? .chinese : .nonChinese) else { return nil }
        return Challenge(word: Word(c.word), friend: friend, title: c.title, mission: c.mission,
                         steps: c.steps, bonus: c.bonus)
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

    /// Options (answer + 3 distractors) come from the shared Rust core.
    static func make(for word: Word, kind: Kind, pool: [Word]) -> QuizQuestion {
        let ids = quizOptions(answerId: word.id, poolIds: pool.map(\.id))
        let options = ids.compactMap(WordBank.word)
        return QuizQuestion(word: word, kind: kind, options: options.isEmpty ? [word] : options)
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
        Int(placementLevel(answers: answers(results)))
    }

    /// The adaptive test stops after a block of 3 if that level wasn't passed.
    static func shouldContinue(results: [(level: Int, right: Bool)]) -> Bool {
        placementShouldContinue(answers: answers(results))
    }

    private static func answers(_ results: [(level: Int, right: Bool)]) -> [PlacementAnswer] {
        results.map { PlacementAnswer(level: UInt8(clamping: $0.level), right: $0.right) }
    }
}
