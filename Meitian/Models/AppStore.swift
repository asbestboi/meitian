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
    /// Extra lessons finished after the day's words (optional so older saves still decode).
    var lessons: Int?
    /// Daily XP milestones already celebrated today.
    var milestones: Int?
    /// Quest counters (optional so older saves still decode).
    var stories: Int?
    var perfect: Int?
    var sentences: Int?
    var listenSpeak: Int?
    /// Quest ids already claimed today, and whether the all-done bonus was paid.
    var claimed: [String]?
    var allQuestsBonus: Bool?

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
    /// Set once levels started needing a level-up test (older saves get their finished levels confirmed).
    var levelTests: Bool? = true
    /// Streak freezes held, and the days they covered (day numbers).
    var freezes: Int?
    var frozenDays: [Int64]?
    /// Story checkpoints finished on the learning path, as "level-unit".
    var pathStories: [String]?
    /// Sentence nodes finished on the learning path, as "level-number".
    var pathSentences: [String]?
}

private struct SaveFile: Codable {
    var profile: Profile
    var cards: [String: CardState]
    var days: [String: DayLog]
    var xp: Int
    /// Optional so older saves still decode.
    var seen: [String]?
}

@Observable
final class AppStore {
    var profile = Profile()
    var cards: [String: CardState] = [:]
    var days: [String: DayLog] = [:]
    var xp = 0
    /// Words shown (tagged as new) but not learned yet.
    private(set) var seen: Set<String> = []
    /// Milestones reached by the last XP gain, waiting to be celebrated.
    var milestoneQueue: [Milestone] = []
    /// Set when freezes just saved the streak (shown once on Today).
    var freezeNotice: Int?

    /// Bumped whenever the day rolls over so views refresh.
    var todayKey = AppStore.key(for: .now)

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("meitian.json")
    }()

    init() {
        load()
        applyFreezes()
    }

    // MARK: persistence

    func load() {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SaveFile.self, from: data) else { return }
        profile = file.profile
        cards = file.cards
        days = file.days
        xp = file.xp
        seen = Set(file.seen ?? [])
        migrateToLevelTests()
    }

    /// Before level-up tests, finishing a level's words moved you up by itself. Confirm those levels once
    /// so nobody gets pushed back.
    private func migrateToLevelTests() {
        guard profile.levelTests != true else { return }
        let levels = Array(1...max(WordBank.maxLevel, 1))
        profile.confirmedLevel = Int(knownLevel(confirmed: UInt8(clamping: profile.confirmedLevel),
                                                learnedPerLevel: levels.map { UInt32(learnedCount(level: $0)) },
                                                totalPerLevel: levels.map { UInt32(WordBank.words(level: $0).count) }))
        profile.levelTests = true
        save()
    }

    func save() {
        let file = SaveFile(profile: profile, cards: cards, days: days, xp: xp, seen: seen.sorted())
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func resetAll() {
        profile = Profile()
        cards = [:]
        days = [:]
        xp = 0
        seen = []
        milestoneQueue.removeAll()
        freezeNotice = nil
        // progress kept outside the save file
        StoryProgress.reset()
        UserDefaults.standard.removeObject(forKey: "sprintBest")
        UserDefaults.standard.set(false, forKey: Prefs.swears)
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
        applyFreezes()
    }

    // MARK: quests & streak freezes

    var dayStats: DayStats {
        let t = today
        return DayStats(xp: UInt32(clamping: max(t.xp, 0)), reviewed: UInt32(clamping: t.reviewed),
                        stories: UInt32(clamping: t.stories ?? 0), lessons: UInt32(clamping: (t.learnedDone ? 1 : 0) + (t.lessons ?? 0)),
                        perfect: UInt32(clamping: t.perfect ?? 0), sentences: UInt32(clamping: t.sentences ?? 0),
                        listenSpeak: UInt32(clamping: t.listenSpeak ?? 0))
    }

    var quests: [QuestStatus] {
        let stats = dayStats
        return dailyQuests(dayKey: todayKey).map { questStatus(quest: $0, stats: stats) }
    }

    func isClaimed(_ q: Quest) -> Bool { today.claimed?.contains(q.id) ?? false }

    /// Marks a finished quest as claimed and returns the coins it pays (plus the bonus for the last one).
    func claimQuest(_ q: QuestStatus) -> Int {
        guard q.done, !isClaimed(q.quest) else { return 0 }
        var t = today
        t.claimed = (t.claimed ?? []) + [q.quest.id]
        var coins = Int(q.quest.reward)
        let all = dailyQuests(dayKey: todayKey).allSatisfy { t.claimed?.contains($0.id) ?? false }
        if all && t.allQuestsBonus != true {
            t.allQuestsBonus = true
            coins += Int(questsAllDoneBonus())
        }
        today = t
        save()
        return coins
    }

    enum Counter { case story, perfect, sentences, listenSpeak }

    func count(_ c: Counter) {
        var t = today
        switch c {
        case .story: t.stories = (t.stories ?? 0) + 1
        case .perfect: t.perfect = (t.perfect ?? 0) + 1
        case .sentences: t.sentences = (t.sentences ?? 0) + 1
        case .listenSpeak: t.listenSpeak = (t.listenSpeak ?? 0) + 1
        }
        today = t
        save()
    }

    var freezes: Int { profile.freezes ?? 0 }
    var canHoldMoreFreezes: Bool { freezes < Int(streakFreezeMax()) }

    func addFreeze() {
        profile.freezes = min(freezes + 1, Int(streakFreezeMax()))
        save()
    }

    /// Spends freezes on days missed since the last activity, if that keeps the streak alive.
    private func applyFreezes() {
        guard freezes > 0, let today = dayNumber(dayKey: AppStore.key(for: .now)) else { return }
        let days = freezesToUse(activeDays: activeDayNumbers, frozenDays: profile.frozenDays ?? [], today: today,
                                owned: UInt32(freezes))
        guard !days.isEmpty else { return }
        profile.freezes = freezes - days.count
        profile.frozenDays = (profile.frozenDays ?? []) + days
        freezeNotice = streak
        save()
    }

    var today: DayLog {
        get { days[todayKey] ?? DayLog() }
        set { days[todayKey] = newValue }
    }

    // MARK: known and new words

    /// Learned words plus the words of confirmed levels.
    var known: [String] {
        Meitian.knownWordIds(cardIds: Array(cards.keys), confirmedLevel: UInt8(clamping: profile.confirmedLevel))
    }

    /// The words of a lesson that aren't learned yet (they get the NEW tag).
    func newIds(_ words: [Word]) -> Set<String> {
        let ids = words.map(\.id)
        let status = wordStatuses(wordIds: ids, knownWordIds: known, seenWordIds: Array(seen))
        return Set(zip(ids, status).filter { $0.1 != .learned }.map { $0.0 })
    }

    /// These words were just shown with their NEW tag. The first time ever, that's a soft ding.
    func markSeen(_ ids: [String], ding: Bool = true) {
        let fresh = ids.filter { !seen.contains($0) && cards[$0] == nil }
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh)
        if ding { SFX.shared.play(.newWord) }
        save()
    }

    /// What the next lesson will teach (stories like to preview it).
    var upcomingIds: [String] {
        WordBank.words(level: currentLevel).filter { cards[$0.id] == nil }.prefix(profile.dailyGoal).map(\.id)
    }

    // MARK: daily words

    /// Placement confirmed levels are already known, so new words start one above.
    var startLevel: Int { min(max(profile.confirmedLevel + 1, 1), WordBank.maxLevel) }

    /// The HSK level the learner is on: new words and stories come from here (and below for stories).
    /// Moving up takes passing the level-up test.
    var currentLevel: Int { startLevel }

    /// Every word of the current level learned: time for the level-up test.
    var levelComplete: Bool {
        let words = WordBank.words(level: currentLevel)
        return !words.isEmpty && words.allSatisfy { cards[$0.id] != nil }
    }

    /// Is there a level above to unlock?
    var canLevelUp: Bool { profile.confirmedLevel < WordBank.maxLevel }

    /// Passing the test for `level` confirms it, unlocking the next level's words and stories.
    func passLevelTest(_ level: Int) {
        profile.confirmedLevel = max(profile.confirmedLevel, level)
        addXP(100)
    }

    /// Today's new words, picked once per day and then fixed.
    func todaysWords() -> [Word] {
        if !today.newWordIds.isEmpty {
            return today.newWordIds.compactMap(WordBank.word)
        }
        // only from the current level: the next one opens with the level-up test
        var picked = Array(WordBank.words(level: currentLevel).filter { cards[$0.id] == nil }.prefix(profile.dailyGoal))
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

    /// The next lesson after today's words: more new words from the learner's level, as many as they like.
    /// Empty while today's words aren't learned yet, or when everything has been learned.
    func nextLessonWords() -> [Word] {
        guard today.learnedDone else { return [] }
        return Array(WordBank.words(level: currentLevel).filter { cards[$0.id] == nil }.prefix(profile.dailyGoal))
    }

    /// Where the learner is on their current HSK level's path of lessons.
    var lessonPath: LessonPath {
        let level = currentLevel
        return Meitian.lessonPath(learned: UInt32(learnedCount(level: level)),
                                  total: UInt32(WordBank.words(level: level).count),
                                  lessonSize: UInt32(max(profile.dailyGoal, 1)))
    }

    // MARK: learning path

    /// The current level's map: units of lessons, a story checkpoint after each unit, the test at the end.
    var learnPath: [PathUnit] {
        let level = currentLevel
        func done(_ keys: [String]?) -> [UInt32] {
            (keys ?? []).compactMap { key -> UInt32? in
                let p = key.split(separator: "-")
                guard p.count == 2, Int(p[0]) == level else { return nil }
                return UInt32(p[1])
            }
        }
        return Meitian.learnPath(learned: UInt32(learnedCount(level: level)),
                                 total: UInt32(WordBank.words(level: level).count),
                                 lessonSize: UInt32(max(profile.dailyGoal, 1)),
                                 storiesDone: done(profile.pathStories),
                                 sentencesDone: done(profile.pathSentences))
    }

    /// The node the big start button points at.
    var nextPathNode: PathNode? { learnPath.flatMap(\.nodes).first(where: \.next) }

    /// A story checkpoint is finished: +20 XP once (nothing when its lines were translated).
    func finishPathStory(unit: Int, translations: Int = 0) {
        let key = "\(currentLevel)-\(unit)"
        var done = profile.pathStories ?? []
        guard !done.contains(key) else { return }
        done.append(key)
        profile.pathStories = done
        addXP(Int(storyXp(base: 20, translationsRevealed: UInt32(clamping: translations))))
    }

    /// A sentence node is finished. Returns the XP it paid (only the first time).
    func finishPathSentences(number: Int) -> Int {
        let key = "\(currentLevel)-\(number)"
        let first = !(profile.pathSentences ?? []).contains(key)
        if first { profile.pathSentences = (profile.pathSentences ?? []) + [key] }
        let gained = first ? Int(pathSentencesXp()) : 0
        addXP(gained)
        count(.sentences)
        return gained
    }

    /// Word ids of one unit on the current level's path (default: the unit of the last finished lesson),
    /// so stories can be picked to fit what the learner just studied.
    func unitWordIds(_ unit: Int? = nil) -> [String] {
        let size = max(profile.dailyGoal, 1)
        let perUnit = Int(pathUnitSize())
        let all = WordBank.words(level: currentLevel)
        let doneLessons = learnedCount(level: currentLevel) / size
        let u = unit ?? max(1, (doneLessons + perUnit - 1) / perUnit)
        let start = (u - 1) * perUnit * size
        guard start >= 0, start < all.count else { return [] }
        return all[start..<min(start + perUnit * size, all.count)].map(\.id)
    }

    /// The words of one lesson on the current level's path (for replaying a finished lesson).
    func lessonWords(_ lesson: Int) -> [Word] {
        let size = max(profile.dailyGoal, 1)
        let all = WordBank.words(level: currentLevel)
        let start = (lesson - 1) * size
        guard start >= 0, start < all.count else { return [] }
        return Array(all[start..<min(start + size, all.count)])
    }

    /// What the next lesson teaches: today's words first, then more from the level.
    func nextUpWords() -> [Word] {
        if !today.learnedDone { return todaysWords() }
        let more = nextLessonWords()
        return more.isEmpty ? todaysWords() : more
    }

    var milestoneProgress: MilestoneProgress { Meitian.milestoneProgress(xpToday: UInt32(clamping: max(today.xp, 0))) }

    /// Hands out any milestones today's XP just reached (bonus XP goes to the total, not today's bar).
    private func checkMilestones() {
        var t = today
        let reached = Int(milestonesReached(xpToday: UInt32(clamping: max(t.xp, 0))))
        let done = t.milestones ?? 0
        guard reached > done else { return }
        let fresh = (done + 1...reached).map { milestoneAt(index: UInt32($0)) }
        t.milestones = reached
        today = t
        xp += fresh.reduce(0) { $0 + Int($1.bonus) }
        milestoneQueue.append(contentsOf: fresh)
    }

    func finishLearning(_ words: [Word], quizCorrect: Int) {
        let extraLesson = today.learnedDone && words.contains { cards[$0.id] == nil }
        for w in words where cards[w.id] == nil {
            var s = CardState(learnedOn: todayKey)
            s.due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
            cards[w.id] = s
        }
        var t = today
        let gained = words.count * 10 + quizCorrect * 5
        if !t.learnedDone { t.learnedDone = true }
        if extraLesson { t.lessons = (t.lessons ?? 0) + 1 }
        t.xp += gained
        today = t
        xp += gained
        checkMilestones()
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

    /// The words the learner gets wrong most (weakest first).
    func weakWords(limit: Int = 15) -> [Word] {
        let stats = cards.map { CardStat(id: $0.key, boxLevel: UInt8(clamping: $0.value.box),
                                         correct: UInt32(clamping: $0.value.correct), wrong: UInt32(clamping: $0.value.wrong)) }
        return weakWordIds(stats: stats, limit: UInt32(limit)).compactMap(WordBank.word).filter { !$0.isSwear || Prefs.swearsOn }
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
        checkMilestones()
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
        checkMilestones()
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
        checkMilestones()
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
        return Int(streakWithFreezes(activeDays: activeDayNumbers, frozenDays: profile.frozenDays ?? [], today: today))
    }

    var bestStreak: Int { max(Int(Meitian.bestStreak(activeDays: activeDayNumbers)), streak) }

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
