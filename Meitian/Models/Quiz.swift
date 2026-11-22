import Foundation

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

    /// The same question asked again later (reshuffled).
    func again() -> QuizQuestion { QuizQuestion(word: word, kind: kind, options: options.shuffled()) }

    /// The same word as a silent question (for "can't speak here").
    func silent() -> QuizQuestion { QuizQuestion(word: word, kind: .hanziToMeaning, options: options) }

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
            // common words first, so the test checks the core of each level
            for (i, w) in pool.prefix(60).shuffled().prefix(3).enumerated() {
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
