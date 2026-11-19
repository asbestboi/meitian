import Foundation
import Observation

/// Spaced-repetition state of one word (Leitner boxes).
struct CardState: Codable, Hashable {
    var box: Int = 1
    var due: Date = .now
    var correct: Int = 0
    var wrong: Int = 0
    var learnedOn: String

    static let intervals = [0, 1, 2, 4, 8, 16, 32] // days, indexed by box

    mutating func grade(_ right: Bool, now: Date = .now) {
        if right { correct += 1; box = min(box + 1, CardState.intervals.count - 1) }
        else { wrong += 1; box = 1 }
        due = Calendar.current.date(byAdding: .day, value: CardState.intervals[box], to: Calendar.current.startOfDay(for: now)) ?? now
    }

    var mastered: Bool { box >= 4 }
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
    var startLevel: Int { min(max(profile.confirmedLevel + 1, 1), 4) }

    /// The level the learner is currently pulling new words from.
    var currentLevel: Int {
        for level in WordBank.levels where level >= startLevel {
            if WordBank.words(level: level).contains(where: { cards[$0.id] == nil }) { return level }
        }
        return 4
    }

    /// Today's new words, picked once per day and then fixed.
    func todaysWords() -> [Word] {
        if !today.newWordIds.isEmpty {
            return today.newWordIds.compactMap(WordBank.word)
        }
        var picked: [Word] = []
        var level = startLevel
        while picked.count < profile.dailyGoal && level <= 4 {
            let fresh = WordBank.words(level: level).filter { cards[$0.id] == nil && !picked.contains($0) }
            picked.append(contentsOf: fresh.prefix(profile.dailyGoal - picked.count))
            level += 1
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
    }

    var learnedWords: [Word] {
        WordBank.all.filter { cards[$0.id] != nil }
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
        let first = t.challenge == nil
        t.challenge = ChallengeLog(wordId: word.id, friend: friend, mood: mood, note: note, completedAt: .now)
        if first { t.xp += 50; xp += 50 }
        today = t
        save()
    }

    struct DatedChallenge: Identifiable {
        let day: String
        let log: ChallengeLog
        var id: String { day }
    }

    var challengeHistory: [DatedChallenge] {
        days.compactMap { entry in entry.value.challenge.map { DatedChallenge(day: entry.key, log: $0) } }
            .sorted { $0.day > $1.day }
    }

    // MARK: stats

    var streak: Int {
        var count = 0
        var date = Date.now
        if !(days[AppStore.key(for: date)]?.active ?? false) {
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        while days[AppStore.key(for: date)]?.active ?? false {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }

    var bestStreak: Int {
        let active = Set(days.filter { $0.value.active }.map(\.key))
        var best = 0
        for k in active {
            guard let d = AppStore.date(from: k) else { continue }
            let prev = Calendar.current.date(byAdding: .day, value: -1, to: d)!
            if active.contains(AppStore.key(for: prev)) { continue } // not a run start
            var run = 0
            var cur = d
            while active.contains(AppStore.key(for: cur)) {
                run += 1
                cur = Calendar.current.date(byAdding: .day, value: 1, to: cur)!
            }
            best = max(best, run)
        }
        return best
    }

    static func date(from key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// XP needed per player level grows gently.
    var playerLevel: Int { Int((Double(xp) / 100).squareRoot()) + 1 }
    var levelProgress: Double {
        let lo = Double((playerLevel - 1) * (playerLevel - 1) * 100)
        let hi = Double(playerLevel * playerLevel * 100)
        return (Double(xp) - lo) / (hi - lo)
    }
    var xpToNextLevel: Int { playerLevel * playerLevel * 100 - xp }

    func learnedCount(level: Int) -> Int {
        WordBank.words(level: level).filter { cards[$0.id] != nil }.count
    }

    var masteredCount: Int { cards.values.filter(\.mastered).count }
}
