import Foundation
import Observation

/// Spaced-repetition state of one word (Leitner boxes).
struct CardState: Codable, Hashable {
    var box: Int = 1
    var due: Date = .now
    var correct: Int = 0
    var wrong: Int = 0
    var learnedOn: String

    /// Leitner grading from the shared Rust core.
    mutating func grade(_ right: Bool, now: Date = .now) {
        if right { correct += 1 } else { wrong += 1 }
        let step = srsGrade(boxLevel: UInt8(clamping: box), right: right)
        box = Int(step.boxLevel)
        due = Calendar.current.date(byAdding: .day, value: Int(step.daysUntilDue),
                                    to: Calendar.current.startOfDay(for: now)) ?? now
    }

    var mastered: Bool { srsIsMastered(boxLevel: UInt8(clamping: box)) }
}

enum FriendKind: String, Codable, CaseIterable, Identifiable {
    case chinese, nonChinese
    var id: String { rawValue }
    var label: String { self == .chinese ? "Chinese friend" : "Non‑Chinese friend" }
    var emoji: String { self == .chinese ? "🐼" : "🌍" }
}

struct ChallengeLog: Codable, Hashable {
    var wordId: String
    var friend: FriendKind
    var mood: Int? // 0 = tough, 1 = good, 2 = amazing
    var note: String = ""
    var completedAt: Date
}

struct DayLog: Codable, Hashable {
    var newWordIds: [String] = []
    var learnedDone = false
    var reviewed = 0
    var xp = 0
    var challenge: ChallengeLog?
    /// The other friend type's challenge on the same day (bonus).
    var bonusChallenge: ChallengeLog?

    /// The day's challenge log for one friend type.
    func challenge(for friend: FriendKind) -> ChallengeLog? {
        if challenge?.friend == friend { return challenge }
        if bonusChallenge?.friend == friend { return bonusChallenge }
        return nil
    }

    var active: Bool { learnedDone || reviewed > 0 || challenge != nil }
}

struct Profile: Codable, Hashable {
    var name = ""
    var claimedLevel = 0
    var confirmedLevel = 0
    var dailyGoal = 5
    var onboarded = false
    var reminderOn = false
    var reminderHour = 19
    var reminderMinute = 0
    var preferredFriend: FriendKind = .chinese
}

private struct SaveFile: Codable {
    var profile: Profile
    var cards: [String: CardState]
    var days: [String: DayLog]
    var xp: Int
}

@Observable
final class AppStore {
    var profile = Profile()
    var cards: [String: CardState] = [:]
    var days: [String: DayLog] = [:]
    var xp = 0

    /// Bumped whenever the day rolls over so views refresh.
    var todayKey = AppStore.key(for: .now)

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("meitian.json")
    }()

    init() { load() }

    // MARK: persistence

    func load() {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SaveFile.self, from: data) else { return }
        profile = file.profile
        cards = file.cards
        days = file.days
        xp = file.xp
    }

    func save() {
        let file = SaveFile(profile: profile, cards: cards, days: days, xp: xp)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func resetAll() {
        profile = Profile()
        cards = [:]
        days = [:]
        xp = 0
        save()
    }

    // MARK: dates

    static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func refreshDay() {
        let k = AppStore.key(for: .now)
        if k != todayKey { todayKey = k }
    }

    var today: DayLog {
        get { days[todayKey] ?? DayLog() }
        set { days[todayKey] = newValue }
    }

    // MARK: daily words

    /// Placement confirmed levels are already known, so new words start one above.
    var startLevel: Int { min(max(profile.confirmedLevel + 1, 1), WordBank.maxLevel) }

    /// The level the learner is currently pulling new words from.
    var currentLevel: Int {
        for level in WordBank.levels where level >= startLevel {
            if WordBank.words(level: level).contains(where: { cards[$0.id] == nil }) { return level }
        }
        return WordBank.maxLevel
    }

    /// Today's new words, picked once per day and then fixed.
    func todaysWords() -> [Word] {
        if !today.newWordIds.isEmpty {
            return today.newWordIds.compactMap(WordBank.word)
        }
        var picked: [Word] = []
        var level = startLevel
        while picked.count < profile.dailyGoal && level <= WordBank.maxLevel {
            let fresh = WordBank.words(level: level).filter { cards[$0.id] == nil && !picked.contains($0) }
            picked.append(contentsOf: fresh.prefix(profile.dailyGoal - picked.count))
            level += 1
        }
        // street mode: one swear word a day on top of the regular ones
        if Prefs.swearsOn, let street = WordBank.swears.first(where: { cards[$0.id] == nil }) {
            picked.append(street)
        }
        if picked.isEmpty { // everything learned — recycle weakest words
            picked = cards.sorted { $0.value.box < $1.value.box }.prefix(profile.dailyGoal).compactMap { WordBank.word($0.key) }
        }
        var t = today
        t.newWordIds = picked.map(\.id)
        today = t
        save()
        return picked
    }

    func finishLearning(_ words: [Word], quizCorrect: Int) {
        for w in words where cards[w.id] == nil {
            var s = CardState(learnedOn: todayKey)
            s.due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
            cards[w.id] = s
        }
        var t = today
        let gained = words.count * 10 + quizCorrect * 5
        if !t.learnedDone { t.learnedDone = true }
        t.xp += gained
        today = t
        xp += gained
        save()
    }

    // MARK: review

    var dueWords: [Word] {
        let now = Date.now
        return cards.filter { $0.value.due <= now }
            .sorted { $0.value.due < $1.value.due }
            .compactMap { WordBank.word($0.key) }
            .filter { !$0.isSwear || Prefs.swearsOn }
    }

    var learnedWords: [Word] {
        WordBank.visible(swears: Prefs.swearsOn).filter { cards[$0.id] != nil }
    }

    /// Adds words to spaced repetition without the daily-words XP (used by Swear Sprint).
    func addToReview(_ words: [Word]) {
        for w in words where cards[w.id] == nil {
            var s = CardState(learnedOn: todayKey)
            s.due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
            cards[w.id] = s
        }
        save()
    }

    func addXP(_ amount: Int) {
        var t = today
        t.xp += amount
        t.reviewed += 1 // counts as activity for the streak
        today = t
        xp += amount
        save()
    }

    func grade(_ word: Word, right: Bool) {
        guard var s = cards[word.id] else { return }
        s.grade(right)
        cards[word.id] = s
        var t = today
        t.reviewed += 1
        let gained = right ? 5 : 1
        t.xp += gained
        today = t
        xp += gained
        save()
    }

    // MARK: challenge

    func completeChallenge(word: Word, friend: FriendKind, mood: Int?, note: String) {
        var t = today
        let log = ChallengeLog(wordId: word.id, friend: friend, mood: mood, note: note, completedAt: .now)
        if t.challenge == nil || t.challenge?.friend == friend {
            if t.challenge == nil { t.xp += 50; xp += 50 }
            t.challenge = log
        } else {
            // second challenge of the day, with the other kind of friend
            if t.bonusChallenge == nil { t.xp += 30; xp += 30 }
            t.bonusChallenge = log
        }
        today = t
        save()
    }

    struct DatedChallenge: Identifiable {
        let day: String
        let log: ChallengeLog
        var id: String { "\(day)-\(log.friend.rawValue)" }
    }

    var challengeHistory: [DatedChallenge] {
        days.flatMap { entry in
            [entry.value.challenge, entry.value.bonusChallenge].compactMap { $0 }.map { DatedChallenge(day: entry.key, log: $0) }
        }
        .sorted { ($0.day, $0.log.completedAt) > ($1.day, $1.log.completedAt) }
    }

    // MARK: stats

    /// Active days as day numbers for the Rust streak logic.
    private var activeDayNumbers: [Int64] {
        days.filter { $0.value.active }.compactMap { dayNumber(dayKey: $0.key) }
    }

    var streak: Int {
        let today = dayNumber(dayKey: AppStore.key(for: .now)) ?? 0
        return Int(currentStreak(activeDays: activeDayNumbers, today: today))
    }

    var bestStreak: Int { Int(Meitian.bestStreak(activeDays: activeDayNumbers)) }

    static func date(from key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// XP needed per player level grows gently (formula in the Rust core).
    private var level: PlayerLevel { Meitian.playerLevel(xp: UInt32(clamping: max(xp, 0))) }
    var playerLevel: Int { Int(level.level) }
    var levelProgress: Double { level.progress }
    var xpToNextLevel: Int { Int(level.xpToNext) }

    func learnedCount(level: Int) -> Int {
        WordBank.words(level: level).filter { cards[$0.id] != nil }.count
    }

    var masteredCount: Int { cards.values.filter(\.mastered).count }
}
