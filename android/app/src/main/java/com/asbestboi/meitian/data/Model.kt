package com.asbestboi.meitian.data

import uniffi.meitian_core.SoundId
import android.content.Context
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.Sentence
import uniffi.meitian_core.SlotPrize
import uniffi.meitian_core.SpinResult
import uniffi.meitian_core.sentenceById
import uniffi.meitian_core.spinSentenceXp
import uniffi.meitian_core.spinSlots
import uniffi.meitian_core.spinWaitMs
import uniffi.meitian_core.LessonPath
import uniffi.meitian_core.PathUnit
import uniffi.meitian_core.Milestone
import uniffi.meitian_core.MilestoneProgress
import uniffi.meitian_core.milestoneAt
import uniffi.meitian_core.milestonesReached
import uniffi.meitian_core.ArenaTheme
import uniffi.meitian_core.BattleResult
import uniffi.meitian_core.Outcome
import uniffi.meitian_core.arenaFor
import uniffi.meitian_core.newArena
import uniffi.meitian_core.retiredAvatarRefund
import uniffi.meitian_core.withoutRetiredAvatars
import uniffi.meitian_core.allWords
import uniffi.meitian_core.CardStat
import uniffi.meitian_core.DayStats
import uniffi.meitian_core.weakWordIds
import uniffi.meitian_core.Quest
import uniffi.meitian_core.QuestStatus
import uniffi.meitian_core.dailyQuests
import uniffi.meitian_core.dayNumber
import uniffi.meitian_core.freezesToUse
import uniffi.meitian_core.questStatus
import uniffi.meitian_core.questsAllDoneBonus
import uniffi.meitian_core.streakFreezeMax
import uniffi.meitian_core.streakFreezePrice
import uniffi.meitian_core.streakWithFreezes
import uniffi.meitian_core.WordStatus
import uniffi.meitian_core.knownLevel
import uniffi.meitian_core.knownWordIds
import uniffi.meitian_core.matchCoins
import uniffi.meitian_core.playerLevel
import uniffi.meitian_core.quizOptions
import uniffi.meitian_core.srsGrade
import uniffi.meitian_core.pathSentencesXp
import uniffi.meitian_core.srsIsMastered
import uniffi.meitian_core.storyXp
import uniffi.meitian_core.streetLevel
import uniffi.meitian_core.swearWords
import uniffi.meitian_core.wordLevels
import uniffi.meitian_core.wordStatuses
import java.time.LocalDate
import java.util.UUID

// ---------- words (from the shared Rust core) ----------

/** Street words use their own level so they never collide with HSK 1–6. */
val STREET_LEVEL: Int = streetLevel().toInt()

val CoreWord.lvl: Int get() = level.toInt()
val CoreWord.isSwear: Boolean get() = lvl == STREET_LEVEL
val CoreWord.shortMeaning: String get() = meaning.split(",").first().trim()
val CoreWord.levelLabel: String get() = if (isSwear) "STREET 🤬" else "HSK $lvl"

/** Bundled words plus downloaded content packs. Compose-observable: reload() after a pack loads. */
object Words {
    private class Data(val all: List<CoreWord>, val swears: List<CoreWord>, val levels: List<Int>) {
        val byId: Map<String, CoreWord> = (all + swears).associateBy { it.id }
    }

    private fun read() = Data(allWords(), swearWords(), wordLevels().map { it.toInt() }.ifEmpty { listOf(1, 2, 3, 4) })

    private var data by mutableStateOf(read())

    val all: List<CoreWord> get() = data.all
    val swears: List<CoreWord> get() = data.swears
    val levels: List<Int> get() = data.levels
    val maxLevel: Int get() = data.levels.lastOrNull() ?: 4
    fun level(l: Int): List<CoreWord> = if (l == STREET_LEVEL) swears else all.filter { it.lvl == l }
    fun visible(swears: Boolean): List<CoreWord> = if (swears) all + this.swears else all
    operator fun get(id: String): CoreWord? = data.byId[id]

    /** Call on the main thread after content was loaded into the core. */
    fun reload() { data = read() }
}

enum class Kind { HanziToMeaning, MeaningToHanzi, Listen, Speak }

private var questionIds = 0L

data class Question(val word: CoreWord, val kind: Kind, val options: List<CoreWord>, val id: Long = ++questionIds) {
    val prompt: String
        get() = when (kind) {
            Kind.HanziToMeaning -> "What does this mean?"
            Kind.MeaningToHanzi -> "Which one means…"
            Kind.Listen -> "Tap what you hear"
            Kind.Speak -> "Say it out loud"
        }

    fun label(o: CoreWord) = if (kind == Kind.HanziToMeaning) o.shortMeaning else o.hanzi

    /** Swap to a silent type if listening/speaking is paused. */
    fun adjusted(s: Settings): Question = when {
        kind == Kind.Listen && !s.canListen -> copy(kind = Kind.MeaningToHanzi)
        kind == Kind.Speak && !s.canSpeak -> copy(kind = Kind.HanziToMeaning)
        else -> this
    }

    /** The same question asked again later (reshuffled). */
    fun again(): Question = Question(word, kind, options.shuffled())

    companion object {
        fun make(word: CoreWord, kind: Kind, pool: List<CoreWord>): Question {
            val opts = quizOptions(word.id, pool.map { it.id }).mapNotNull { Words[it] }
            return Question(word, kind, opts.ifEmpty { listOf(word) })
        }

        fun mixedKinds(s: Settings): List<Kind> = buildList {
            add(Kind.HanziToMeaning); add(Kind.MeaningToHanzi)
            if (s.canListen) add(Kind.Listen)
            if (s.canSpeak) add(Kind.Speak)
        }
    }
}

// ---------- saved state ----------

data class Card(val box: Int = 1, val dueDay: Long, val correct: Int = 0, val wrong: Int = 0) {
    val mastered get() = srsIsMastered(box.toUByte())
}

/** A friend challenge done before 1.13 (they were replaced by the slot machine). Kept so old days still count. */
data class ChallengeLog(val wordId: String, val friend: String, val mood: Int?, val note: String, val at: Long)

data class DayLog(
    val newWordIds: List<String> = emptyList(),
    val learnedDone: Boolean = false,
    val reviewed: Int = 0,
    val xp: Int = 0,
    val challenge: ChallengeLog? = null,
    val bonus: ChallengeLog? = null,
    /** Extra lessons finished after the day's words. */
    val lessons: Int = 0,
    /** Daily XP milestones already celebrated. */
    val milestones: Int = 0,
    /** Quest counters. */
    val stories: Int = 0,
    val perfect: Int = 0,
    val sentences: Int = 0,
    val listenSpeak: Int = 0,
    /** Quest ids claimed today, and whether the all-done bonus was paid. */
    val claimed: List<String> = emptyList(),
    val allQuestsBonus: Boolean = false,
) {
    val active get() = learnedDone || reviewed > 0 || challenge != null
}

data class Profile(
    val name: String = "",
    val claimedLevel: Int = 0,
    val confirmedLevel: Int = 0,
    val dailyGoal: Int = 5,
    val onboarded: Boolean = false,
    /** Set once levels started needing a level-up test (older saves get their finished levels confirmed). */
    val levelTests: Boolean = true,
    /** Streak freezes held, and the days they covered (day numbers). */
    val freezes: Int = 0,
    val frozenDays: List<Long> = emptyList(),
    /** Daily reminder notification. */
    val reminderOn: Boolean = false,
    val reminderHour: Int = 19,
    val reminderMinute: Int = 0,
    /** Story checkpoints finished on the learning path, as "level-unit". */
    val pathStories: List<String> = emptyList(),
    /** Sentence nodes finished on the learning path, as "level-number". */
    val pathSentences: List<String> = emptyList(),
    /** Highest arena tier already revealed (0 = a save from before arenas). */
    val arenaSeen: Int = 1,
    /** Notification when the next spin is ready. */
    val spinReminder: Boolean = false,
    /** Notification when somebody invites the learner to a battle. */
    val inviteNotify: Boolean = true,
)

/** The daily slot machine. */
data class Slots(
    val spins: Int = 0,
    val lastSpin: Long = 0,
    /** When the server allows the next spin (0 = it hasn't said). */
    val serverNext: Long = 0,
    /** The sentence of the day, until the next spin. */
    val sentenceId: Long? = null,
    val sentenceDone: Boolean = false,
)

data class Settings(
    val showPinyin: Boolean = true,
    val toneColors: Boolean = true,
    val swears: Boolean = false,
    val sounds: Boolean = true,
    val listening: Boolean = true,
    val speaking: Boolean = true,
    val noListenUntil: Long = 0,
    val noSpeakUntil: Long = 0,
    /** Sound effects, 0–1. */
    val volume: Float = 0.8f,
    val haptics: Boolean = true,
) {
    val canListen get() = listening && System.currentTimeMillis() > noListenUntil
    val canSpeak get() = speaking && System.currentTimeMillis() > noSpeakUntil
}

/** [picture]: path of their profile picture on the server, "" for initials. */
data class Rival(val id: String, val name: String, val picture: String = "", val wins: Int = 0, val losses: Int = 0, val draws: Int = 0, val last: Long = 0)

val FREE_COSMETICS = setOf("fr.lantern", "ti.newbie", "fx.boom", "st.none", "au.none")

data class Arena(
    val playerId: String = UUID.randomUUID().toString(),
    val coins: Int = 0,
    val owned: Set<String> = FREE_COSMETICS,
    val frame: String = "fr.lantern",
    val title: String = "ti.newbie",
    val effect: String = "fx.boom",
    val sticker: String = "st.none",
    val aura: String = "au.none",
    val wins: Int = 0,
    val losses: Int = 0,
    val draws: Int = 0,
    val streak: Int = 0,
    val bestStreak: Int = 0,
    val fastestMs: Int? = null,
    val rivals: Map<String, Rival> = emptyMap(),
)

/** All app state, observable by Compose and saved as JSON in SharedPreferences. */
class AppState(private val context: Context) {
    var profile by mutableStateOf(Profile())
    var settings by mutableStateOf(Settings())
    var arena by mutableStateOf(Arena())
    var xp by mutableStateOf(0)
    val cards = mutableStateMapOf<String, Card>()
    val days = mutableStateMapOf<String, DayLog>()
    /** Words shown (tagged as new) but not learned yet. */
    var seen by mutableStateOf(emptySet<String>())
        private set
    var todayKey by mutableStateOf(LocalDate.now().toString())
    /** Milestones reached by the last XP gain, waiting to be celebrated. */
    val milestoneQueue = mutableStateListOf<Milestone>()
    /** Set when freezes just saved the streak (shown once on Today). */
    var freezeNotice by mutableStateOf<Int?>(null)
    /** A short message shown over everything for a moment. */
    var toast by mutableStateOf<String?>(null)
    var slots by mutableStateOf(Slots())
        private set
    /** An arena the learner just reached, waiting for its reveal. */
    var arenaReveal by mutableStateOf<ArenaTheme?>(null)

    private val prefs = context.getSharedPreferences("meitian", Context.MODE_PRIVATE)

    init { load(); migrateToLevelTests(); applyFreezes(); retireAvatars(); checkArena() }

    /** Emoji avatars left the shop in 1.13: their price comes back once (they leave the collection with it). */
    private fun retireAvatars() {
        val owned = arena.owned.toList()
        if (owned.none { it.startsWith("av.") }) return
        val refund = retiredAvatarRefund(owned).toInt()
        arena = arena.copy(owned = withoutRetiredAvatars(owned).toSet(), coins = arena.coins + refund)
        if (refund > 0) toast = "Avatars were retired, +$refund 🪙 refunded"
        save()
    }

    /** The scenery for where the learner is. */
    val arenaTheme: ArenaTheme
        get() {
            val size = profile.dailyGoal.coerceAtLeast(1) * uniffi.meitian_core.pathUnitSize().toInt()
            return arenaFor(currentLevel.coerceIn(0, 255).toUByte(), (learnedCount(currentLevel) / size + 1).toUInt())
        }

    /** Reaching a new arena gets a reveal; a save from before arenas just starts in its own. */
    fun checkArena() {
        val tier = arenaTheme.tier.toInt()
        if (tier == profile.arenaSeen) return
        newArena(currentLevel.coerceIn(0, 255).toUByte(), profile.arenaSeen.toUInt())?.let { arenaReveal = it }
        profile = profile.copy(arenaSeen = maxOf(tier, profile.arenaSeen))
        save()
    }

    /** Runs something that earns XP and plays what it leads to: a new player level, the day's streak. */
    private fun celebrating(work: () -> Unit) {
        val before = level.level
        val active = today.active
        work()
        if (level.level > before) Sfx.play(SoundId.LEVEL_UP)
        else if (!active && today.active) Sfx.play(SoundId.STREAK)
    }

    fun refreshDay() { todayKey = LocalDate.now().toString(); applyFreezes() }

    // ----- quests & streak freezes -----

    val dayStats: DayStats
        get() = today.let { t ->
            DayStats(t.xp.coerceAtLeast(0).toUInt(), t.reviewed.toUInt(), t.stories.toUInt(),
                ((if (t.learnedDone) 1 else 0) + t.lessons).toUInt(), t.perfect.toUInt(), t.sentences.toUInt(), t.listenSpeak.toUInt())
        }

    val quests: List<QuestStatus> get() = dayStats.let { s -> dailyQuests(todayKey).map { questStatus(it, s) } }

    fun isClaimed(q: Quest) = q.id in today.claimed

    /** Marks a finished quest claimed and pays its coins into the Arena wallet (plus the bonus for the last one). */
    fun claimQuest(q: QuestStatus): Int {
        if (!q.done || isClaimed(q.quest)) return 0
        var t = today.copy(claimed = today.claimed + q.quest.id)
        var coins = q.quest.reward.toInt()
        if (dailyQuests(todayKey).all { it.id in t.claimed } && !t.allQuestsBonus) {
            t = t.copy(allQuestsBonus = true)
            coins += questsAllDoneBonus().toInt()
        }
        today = t
        arena = arena.copy(coins = arena.coins + coins)
        save()
        return coins
    }

    enum class Counter { Story, Perfect, Sentences, ListenSpeak }

    fun count(c: Counter) {
        val t = today
        today = when (c) {
            Counter.Story -> t.copy(stories = t.stories + 1)
            Counter.Perfect -> t.copy(perfect = t.perfect + 1)
            Counter.Sentences -> t.copy(sentences = t.sentences + 1)
            Counter.ListenSpeak -> t.copy(listenSpeak = t.listenSpeak + 1)
        }
        save()
    }

    val canHoldMoreFreezes get() = profile.freezes < streakFreezeMax().toInt()

    fun buyFreeze(): Boolean {
        val price = streakFreezePrice().toInt()
        if (!canHoldMoreFreezes || arena.coins < price) return false
        arena = arena.copy(coins = arena.coins - price)
        profile = profile.copy(freezes = profile.freezes + 1)
        save()
        return true
    }

    /** Spends freezes on days missed since the last activity, if that keeps the streak alive. */
    private fun applyFreezes() {
        if (profile.freezes <= 0) return
        val days = freezesToUse(activeDays, profile.frozenDays, todayNumber, profile.freezes.toUInt())
        if (days.isEmpty()) return
        profile = profile.copy(freezes = profile.freezes - days.size, frozenDays = profile.frozenDays + days)
        freezeNotice = streak
        save()
    }

    val todayNumber: Long get() = dayNumber(todayKey) ?: LocalDate.now().toEpochDay()

    var today: DayLog
        get() = days[todayKey] ?: DayLog()
        set(v) { days[todayKey] = v }

    // ----- daily slot machine -----

    /** Milliseconds until the next spin (0 = ready). */
    val spinWait: Long get() = spinWaitMs(slots.lastSpin, slots.serverNext, System.currentTimeMillis())

    /** The pinned sentence, if its pack is loaded. */
    val slotSentence: Sentence? get() = slots.sentenceId?.let { id -> ContentSync.generation; sentenceById(id.toULong(), knownList) }

    /** Spins: the prize is decided, paid and saved at once. Null when it isn't time yet (the server has the last word). */
    suspend fun spin(): SpinResult? {
        refreshDay()
        if (spinWait > 0) return null
        val server = Online.spin(slots.spins)
        val now = System.currentTimeMillis()
        if (server != null && !server.allowed) {
            slots = slots.copy(serverNext = now + server.waitMs, spins = maxOf(slots.spins, server.spins.toInt()))
            save()
            return null
        }
        val count = server?.spins?.toInt() ?: (slots.spins + 1)
        val free = Catalog.all.filter { it.price > 0 && it.id !in arena.owned && (settings.swears || !it.swear) }.map { it.id }
        val result = spinSlots(todayKey, arena.playerId, count.toUInt(), free, knownList)
        when (val prize = result.prize) {
            is SlotPrize.Coins -> arena = arena.copy(coins = arena.coins + prize.amount.toInt())
            is SlotPrize.Cosmetic -> arena = arena.copy(owned = arena.owned + prize.id)
            is SlotPrize.Sentence -> {}
        }
        slots = Slots(count, now, if (server != null) now + server.waitMs else 0, (result.prize as? SlotPrize.Sentence)?.sentence?.id?.toLong())
        save()
        if (profile.spinReminder) Reminders.scheduleSpin(context, now + spinWait)
        return result
    }

    /** The sentence of the day is done: XP once. Returns what it paid. */
    fun finishSlotSentence(): Int {
        if (slots.sentenceDone) return 0
        slots = slots.copy(sentenceDone = true)
        val gained = spinSentenceXp().toInt()
        addXP(gained)
        return gained
    }

    fun setSpinReminder(on: Boolean) {
        profile = profile.copy(spinReminder = on)
        if (on && spinWait > 0) Reminders.scheduleSpin(context, System.currentTimeMillis() + spinWait) else Reminders.cancelSpin(context)
        save()
    }

    // ----- known and new words -----

    /** Learned words plus the words of confirmed levels. */
    val known: Set<String> by derivedStateOf {
        Words.all.size // downloaded packs add words to confirmed levels
        knownWordIds(cards.keys.toList(), profile.confirmedLevel.coerceIn(0, 255).toUByte()).toHashSet()
    }
    val knownList: List<String> get() = known.toList()

    /** The words of a lesson that aren't learned yet (they get the NEW tag). */
    fun newIds(words: List<CoreWord>): Set<String> {
        val ids = words.map { it.id }
        return ids.zip(wordStatuses(ids, knownList, seen.toList())).filter { it.second != WordStatus.LEARNED }.map { it.first }.toSet()
    }

    /** These words were just shown with their NEW tag. The first time ever, that's a soft ding. */
    fun markSeen(ids: Collection<String>, ding: Boolean = true) {
        val fresh = ids.filter { it !in seen && it !in known }
        if (fresh.isEmpty()) return
        seen = seen + fresh
        if (ding) Sfx.play(SoundId.NEW_WORD)
        save()
    }

    /** The level's words in the order they're taught: learned ones first, then the order that opens a story per unit. */
    val pathWords: List<CoreWord> by derivedStateOf {
        ContentSync.generation
        uniffi.meitian_core.pathWords(currentLevel.coerceIn(0, 255).toUByte(), profile.dailyGoal.coerceAtLeast(1).toUInt(), cards.keys.toList()).mapNotNull { Words[it] }
    }

    /** What the next lesson will teach (stories like to preview it). */
    val upcomingIds: List<String>
        get() = pathWords.filter { cards[it.id] == null }.take(profile.dailyGoal).map { it.id }

    // ----- words of the day -----

    val startLevel get() = (profile.confirmedLevel + 1).coerceIn(1, Words.maxLevel)

    /** The HSK level the learner is on: new words and stories come from here. Moving up takes the level-up test. */
    val currentLevel: Int get() = startLevel

    /** Every word of the current level learned: time for the level-up test. */
    val levelComplete: Boolean get() = Words.level(currentLevel).let { w -> w.isNotEmpty() && w.all { cards[it.id] != null } }

    /** Is there a level above to unlock? */
    val canLevelUp: Boolean get() = profile.confirmedLevel < Words.maxLevel

    /** Passing the test for [level] confirms it, unlocking the next level's words and stories. */
    fun passLevelTest(level: Int) {
        profile = profile.copy(confirmedLevel = maxOf(profile.confirmedLevel, level))
        addXP(100)
        checkArena()
    }

    /** Before level-up tests, finishing a level's words moved you up by itself. Confirm those levels once. */
    private fun migrateToLevelTests() {
        if (profile.levelTests) return
        val levels = (1..Words.maxLevel.coerceAtLeast(1)).toList()
        val known = knownLevel(profile.confirmedLevel.coerceIn(0, 255).toUByte(),
            levels.map { learnedCount(it).toUInt() }, levels.map { Words.level(it).size.toUInt() })
        profile = profile.copy(confirmedLevel = known.toInt(), levelTests = true)
        save()
    }

    fun todaysWords(): List<CoreWord> {
        if (today.newWordIds.isNotEmpty()) return today.newWordIds.mapNotNull { Words[it] }
        // only from the current level: the next one opens with the level-up test
        val picked = pathWords.filter { cards[it.id] == null }.take(profile.dailyGoal).toMutableList()
        if (settings.swears) Words.swears.firstOrNull { cards[it.id] == null }?.let { picked += it }
        if (picked.isEmpty()) picked += cards.entries.sortedBy { it.value.box }.take(profile.dailyGoal).mapNotNull { Words[it.key] }
        today = today.copy(newWordIds = picked.map { it.id })
        save()
        return picked
    }

    /** The next lesson after today's words: more new words from the learner's level, as many as they like.
     *  Empty until today's words are learned, or when everything has been learned. */
    fun nextLessonWords(): List<CoreWord> {
        if (!today.learnedDone) return emptyList()
        return pathWords.filter { cards[it.id] == null }.take(profile.dailyGoal)
    }

    /** Where the learner is on their current HSK level's path of lessons. */
    val lessonPath: LessonPath
        get() = uniffi.meitian_core.lessonPath(learnedCount(currentLevel).toUInt(), Words.level(currentLevel).size.toUInt(), profile.dailyGoal.coerceAtLeast(1).toUInt())

    // ---- learning path ----

    /** The current level's map: units of lessons, a story checkpoint after each unit, the test at the end. */
    val learnPath: List<PathUnit>
        get() {
            val level = currentLevel
            fun done(keys: List<String>) = keys.mapNotNull { key ->
                val p = key.split("-")
                if (p.size == 2 && p[0].toIntOrNull() == level) p[1].toUIntOrNull() else null
            }
            return uniffi.meitian_core.learnPath(learnedCount(level).toUInt(), Words.level(level).size.toUInt(),
                profile.dailyGoal.coerceAtLeast(1).toUInt(), done(profile.pathStories), done(profile.pathSentences))
        }

    /** A story checkpoint is finished: +20 XP once (nothing when its lines were translated). */
    fun finishPathStory(unit: Int, translations: Int = 0) {
        val key = "$currentLevel-$unit"
        if (key in profile.pathStories) return
        profile = profile.copy(pathStories = profile.pathStories + key)
        addXP(storyXp(20u, translations.toUInt()).toInt())
    }

    /** A sentence node is finished. Returns the XP it paid (only the first time). */
    fun finishPathSentences(number: Int): Int {
        val key = "$currentLevel-$number"
        val first = key !in profile.pathSentences
        if (first) profile = profile.copy(pathSentences = profile.pathSentences + key)
        val gained = if (first) pathSentencesXp().toInt() else 0
        addXP(gained)
        count(Counter.Sentences)
        return gained
    }

    /** The words of one lesson on the current level's path (for replaying a finished lesson). */
    /** Word ids of one unit on the current path (default: the unit of the last finished lesson), to pick fitting stories. */
    fun unitWordIds(unit: Int? = null): List<String> {
        val size = profile.dailyGoal.coerceAtLeast(1)
        val perUnit = uniffi.meitian_core.pathUnitSize().toInt()
        val all = pathWords
        val doneLessons = learnedCount(currentLevel) / size
        val u = unit ?: maxOf(1, (doneLessons + perUnit - 1) / perUnit)
        val start = (u - 1) * perUnit * size
        if (start < 0 || start >= all.size) return emptyList()
        return all.subList(start, minOf(start + perUnit * size, all.size)).map { it.id }
    }

    fun lessonWords(lesson: Int): List<CoreWord> {
        val size = profile.dailyGoal.coerceAtLeast(1)
        val all = pathWords
        val start = (lesson - 1) * size
        if (start < 0 || start >= all.size) return emptyList()
        return all.subList(start, minOf(start + size, all.size))
    }

    /** What the next lesson teaches: today's words first, then more from the level. */
    fun nextUpWords(): List<CoreWord> {
        if (!today.learnedDone) return todaysWords()
        return nextLessonWords().ifEmpty { todaysWords() }
    }

    val milestoneProgress: MilestoneProgress get() = uniffi.meitian_core.milestoneProgress(today.xp.coerceAtLeast(0).toUInt())

    /** Hands out any milestones today's XP just reached (bonus XP goes to the total, not today's bar). */
    private fun checkMilestones() {
        val t = today
        val reached = milestonesReached(t.xp.coerceAtLeast(0).toUInt()).toInt()
        if (reached <= t.milestones) return
        val fresh = (t.milestones + 1..reached).map { milestoneAt(it.toUInt()) }
        today = t.copy(milestones = reached)
        xp += fresh.sumOf { it.bonus.toInt() }
        milestoneQueue += fresh
    }

    fun finishLearning(words: List<CoreWord>, quizCorrect: Int) = celebrating {
        val extraLesson = today.learnedDone && words.any { cards[it.id] == null }
        words.forEach { if (cards[it.id] == null) cards[it.id] = Card(dueDay = todayNumber + 1) }
        val gained = words.size * 10 + quizCorrect * 5
        today = today.copy(learnedDone = true, xp = today.xp + gained, lessons = today.lessons + if (extraLesson) 1 else 0)
        xp += gained
        checkMilestones()
        save()
    }

    fun addToReview(words: List<CoreWord>) {
        words.forEach { if (cards[it.id] == null) cards[it.id] = Card(dueDay = todayNumber + 1) }
        save()
    }

    fun addXP(amount: Int) = celebrating {
        today = today.copy(xp = today.xp + amount, reviewed = today.reviewed + 1)
        xp += amount
        checkMilestones()
        save()
    }

    val dueWords: List<CoreWord>
        get() = cards.entries.filter { it.value.dueDay <= todayNumber }.sortedBy { it.value.dueDay }
            .mapNotNull { Words[it.key] }.filter { !it.isSwear || settings.swears }

    /** The words the learner gets wrong most (weakest first). */
    fun weakWords(limit: Int = 15): List<CoreWord> =
        weakWordIds(cards.map { (id, c) -> CardStat(id, c.box.coerceIn(0, 255).toUByte(), c.correct.toUInt(), c.wrong.toUInt()) }, limit.toUInt())
            .mapNotNull { Words[it] }.filter { !it.isSwear || settings.swears }

    val learnedWords: List<CoreWord> get() = Words.visible(settings.swears).filter { cards[it.id] != null }

    fun grade(word: CoreWord, right: Boolean) = celebrating {
        val c = cards[word.id] ?: return@celebrating
        val step = srsGrade(c.box.toUByte(), right)
        cards[word.id] = c.copy(
            box = step.boxLevel.toInt(), dueDay = todayNumber + step.daysUntilDue.toLong(),
            correct = c.correct + if (right) 1 else 0, wrong = c.wrong + if (right) 0 else 1,
        )
        val gained = if (right) 5 else 1
        today = today.copy(reviewed = today.reviewed + 1, xp = today.xp + gained)
        xp += gained
        checkMilestones()
        save()
    }

    // ----- stats -----

    private val activeDays get() = days.filter { it.value.active }.keys.mapNotNull { dayNumber(it) }
    val streak: Int get() = streakWithFreezes(activeDays, profile.frozenDays, todayNumber).toInt()
    val bestStreak: Int get() = maxOf(uniffi.meitian_core.bestStreak(activeDays).toInt(), streak)
    val level get() = playerLevel(xp.coerceAtLeast(0).toUInt())
    fun learnedCount(level: Int) = Words.level(level).count { cards[it.id] != null }
    val masteredCount get() = cards.values.count { it.mastered }

    // ----- arena -----

    /** Records a finished battle and returns the coins it paid. Group games pay by place and don't count as wins. */
    fun recordBattle(result: BattleResult, rival: PlayerCard?, picture: String): Int {
        val fastest = result.fastestMs?.toInt()
        if (result.ranked && rival != null) return recordMatch(result.outcome, rival, picture, result.bonus.toInt(), fastest)
        val earned = result.groupCoins.toInt()
        arena = arena.copy(coins = arena.coins + earned, fastestMs = listOfNotNull(arena.fastestMs, fastest).minOrNull())
        save()
        return earned
    }

    private fun recordMatch(outcome: Outcome, rival: PlayerCard, picture: String, bonus: Int, fastest: Int?): Int {
        val a = arena
        val old = a.rivals[rival.id] ?: Rival(rival.id, rival.name)
        var r = old.copy(name = rival.name, picture = picture, last = System.currentTimeMillis())
        var next = a
        when (outcome) {
            Outcome.WIN -> {
                next = next.copy(wins = a.wins + 1, streak = a.streak + 1, bestStreak = maxOf(a.bestStreak, a.streak + 1))
                r = r.copy(wins = r.wins + 1)
            }
            Outcome.LOSS -> { next = next.copy(losses = a.losses + 1, streak = 0); r = r.copy(losses = r.losses + 1) }
            Outcome.DRAW -> { next = next.copy(draws = a.draws + 1); r = r.copy(draws = r.draws + 1) }
        }
        val earned = matchCoins(outcome, bonus.coerceAtLeast(0).toUInt(), next.streak.toUInt()).toInt()
        arena = next.copy(
            coins = next.coins + earned,
            rivals = next.rivals + (rival.id to r),
            fastestMs = listOfNotNull(next.fastestMs, fastest).minOrNull(),
        )
        save()
        return earned
    }

    fun buy(item: Cosmetic): Boolean {
        if (item.id in arena.owned || arena.coins < item.price) return false
        arena = arena.copy(coins = arena.coins - item.price, owned = arena.owned + item.id)
        equip(item)
        return true
    }

    fun equip(item: Cosmetic) {
        if (item.id !in arena.owned) return
        arena = when (item.kind) {
            CosmeticKind.Frame -> arena.copy(frame = item.id)
            CosmeticKind.Title -> arena.copy(title = item.id)
            CosmeticKind.Effect -> arena.copy(effect = item.id)
            CosmeticKind.Aura -> arena.copy(aura = item.id)
            CosmeticKind.Sticker -> arena.copy(sticker = item.id)
        }
        save()
    }

    fun equipped(kind: CosmeticKind) = when (kind) {
        CosmeticKind.Frame -> arena.frame; CosmeticKind.Title -> arena.title
        CosmeticKind.Effect -> arena.effect; CosmeticKind.Aura -> arena.aura; CosmeticKind.Sticker -> arena.sticker
    }

    fun myCard(): PlayerCard {
        val sw = settings.swears
        fun clean(id: String, fallback: String) = if ((Catalog[id]?.swear == true) && !sw) fallback else id
        val a = arena
        return PlayerCard(
            id = a.playerId, name = profile.name.ifBlank { "Player" }, level = currentLevel, wordsLearned = cards.size,
            wins = a.wins, losses = a.losses, frame = a.frame,
            title = clean(a.title, "ti.newbie"), effect = clean(a.effect, "fx.boom"),
            sticker = clean(a.sticker, "st.none"), swears = sw, aura = a.aura,
        )
    }

    fun resetAll() {
        val id = arena.playerId
        profile = Profile(); settings = settings.copy(swears = false); arena = Arena(playerId = id); xp = 0
        cards.clear(); days.clear(); seen = emptySet(); slots = slots.copy(sentenceId = null, sentenceDone = false); milestoneQueue.clear(); freezeNotice = null
        Reminders.cancel(context); Reminders.cancelSpin(context)
        // progress kept outside the save: story history (ui.StoryProgress) and the sprint best
        context.getSharedPreferences("stories", Context.MODE_PRIVATE).edit().clear().apply()
        prefs.edit().remove("sprintBest").apply()
        save()
    }

    // ----- persistence -----

    fun save() {
        val o = JSONObject()
        o.put("xp", xp)
        o.put("profile", JSONObject().apply {
            put("name", profile.name); put("claimed", profile.claimedLevel); put("confirmed", profile.confirmedLevel)
            put("goal", profile.dailyGoal); put("onboarded", profile.onboarded)
            put("levelTests", profile.levelTests); put("freezes", profile.freezes); put("frozen", JSONArray(profile.frozenDays))
            put("rem", profile.reminderOn); put("remH", profile.reminderHour); put("remM", profile.reminderMinute)
            put("pathSt", JSONArray(profile.pathStories)); put("pathSe", JSONArray(profile.pathSentences))
            put("arenaSeen", profile.arenaSeen); put("spinRem", profile.spinReminder); put("inv", profile.inviteNotify)
        })
        o.put("seen", JSONArray(seen.toList()))
        o.put("slots", JSONObject().apply {
            put("n", slots.spins); put("last", slots.lastSpin); put("next", slots.serverNext); put("sid", slots.sentenceId ?: -1L); put("sdone", slots.sentenceDone)
        })
        o.put("settings", JSONObject().apply {
            val s = settings
            put("pinyin", s.showPinyin); put("tones", s.toneColors); put("swears", s.swears); put("sounds", s.sounds)
            put("listening", s.listening); put("speaking", s.speaking); put("noListen", s.noListenUntil); put("noSpeak", s.noSpeakUntil)
            put("volume", s.volume.toDouble()); put("haptics", s.haptics)
        })
        o.put("cards", JSONObject().apply {
            cards.forEach { (k, c) -> put(k, JSONArray(listOf(c.box, c.dueDay, c.correct, c.wrong))) }
        })
        o.put("days", JSONObject().apply {
            days.forEach { (k, d) ->
                put(k, JSONObject().apply {
                    put("ids", JSONArray(d.newWordIds)); put("done", d.learnedDone); put("rev", d.reviewed); put("xp", d.xp)
                    put("les", d.lessons); put("ms", d.milestones)
                    put("st", d.stories); put("pf", d.perfect); put("se", d.sentences); put("ls", d.listenSpeak)
                    put("cl", JSONArray(d.claimed)); put("allq", d.allQuestsBonus)
                    d.challenge?.let { c ->
                        put("ch", JSONObject().apply {
                            put("w", c.wordId); put("f", c.friend); put("m", c.mood ?: -1); put("n", c.note); put("t", c.at)
                        })
                    }
                    d.bonus?.let { c ->
                        put("ch2", JSONObject().apply {
                            put("w", c.wordId); put("f", c.friend); put("m", c.mood ?: -1); put("n", c.note); put("t", c.at)
                        })
                    }
                })
            }
        })
        o.put("arena", JSONObject().apply {
            val a = arena
            put("id", a.playerId); put("coins", a.coins); put("owned", JSONArray(a.owned.toList()))
            put("frame", a.frame); put("title", a.title); put("effect", a.effect); put("sticker", a.sticker); put("aura", a.aura)
            put("wins", a.wins); put("losses", a.losses); put("draws", a.draws); put("streak", a.streak); put("best", a.bestStreak)
            put("fastest", a.fastestMs ?: -1)
            put("rivals", JSONArray(a.rivals.values.map { r ->
                JSONObject().apply {
                    put("id", r.id); put("name", r.name); put("pic", r.picture); put("w", r.wins); put("l", r.losses); put("d", r.draws); put("t", r.last)
                }
            }))
        })
        prefs.edit().putString("save", o.toString()).apply()
        writeSnapshot()
    }

    /** What the reminder and the home-screen widget show, refreshed on every save. */
    private fun writeSnapshot() {
        runCatching {
            val t = today
            val m = milestoneProgress.next
            val due = dueWords.size
            val todo = when {
                !profile.onboarded -> "set up Měitiān ✦"
                !t.learnedDone -> "🎯 learn today's words"
                levelComplete && canLevelUp -> "🎓 your HSK $currentLevel test is ready"
                due > 0 -> "🃏 $due words to review"
                nextLessonWords().isNotEmpty() -> "🎯 lesson ${lessonPath.lesson} of HSK $currentLevel is next"
                else -> "all done today ✦ see you tomorrow"
            }
            Snapshot.write(context, Snapshot.Data(todayKey, profile.name, streak, t.xp, t.active, m.emoji, m.title, m.xp.toInt(), todo,
                profile.reminderOn, profile.reminderHour, profile.reminderMinute))
            com.asbestboi.meitian.MeitianWidget.update(context)
        }
    }

    /** Turns the daily reminder on or off (permission is asked for by the screen). */
    fun setReminder(on: Boolean, hour: Int = profile.reminderHour, minute: Int = profile.reminderMinute) {
        profile = profile.copy(reminderOn = on, reminderHour = hour, reminderMinute = minute)
        if (on) Reminders.schedule(context, hour, minute) else Reminders.cancel(context)
        save()
    }

    private fun load() {
        val raw = prefs.getString("save", null) ?: return
        runCatching {
            val o = JSONObject(raw)
            xp = o.optInt("xp")
            o.optJSONObject("profile")?.let { p ->
                profile = Profile(p.optString("name"), p.optInt("claimed"), p.optInt("confirmed"), p.optInt("goal", 5),
                    p.optBoolean("onboarded"), p.optBoolean("levelTests"),
                    p.optInt("freezes"), p.optJSONArray("frozen")?.let { a -> (0 until a.length()).map { a.getLong(it) } } ?: emptyList(),
                    p.optBoolean("rem"), p.optInt("remH", 19), p.optInt("remM", 0),
                    p.optJSONArray("pathSt")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
                    p.optJSONArray("pathSe")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
                    p.optInt("arenaSeen", 0), p.optBoolean("spinRem"), p.optBoolean("inv", true))
            }
            o.optJSONObject("slots")?.let { x ->
                slots = Slots(x.optInt("n"), x.optLong("last"), x.optLong("next"), x.optLong("sid", -1).takeIf { it >= 0 }, x.optBoolean("sdone"))
            }
            o.optJSONArray("seen")?.let { a -> seen = (0 until a.length()).map { a.getString(it) }.toSet() }
            o.optJSONObject("settings")?.let { s ->
                settings = Settings(s.optBoolean("pinyin", true), s.optBoolean("tones", true), s.optBoolean("swears"),
                    s.optBoolean("sounds", true), s.optBoolean("listening", true), s.optBoolean("speaking", true),
                    s.optLong("noListen"), s.optLong("noSpeak"), s.optDouble("volume", 0.8).toFloat(), s.optBoolean("haptics", true))
            }
            o.optJSONObject("cards")?.let { c ->
                c.keys().forEach { k ->
                    val a = c.getJSONArray(k)
                    cards[k] = Card(a.getInt(0), a.getLong(1), a.getInt(2), a.getInt(3))
                }
            }
            o.optJSONObject("days")?.let { d ->
                d.keys().forEach { k ->
                    val x = d.getJSONObject(k)
                    val ids = x.optJSONArray("ids")?.let { arr -> (0 until arr.length()).map { arr.getString(it) } } ?: emptyList()
                    fun log(c: JSONObject) = ChallengeLog(c.getString("w"), c.getString("f"), c.optInt("m", -1).takeIf { it >= 0 }, c.optString("n"), c.optLong("t"))
                    val ch = x.optJSONObject("ch")?.let(::log)
                    val ch2 = x.optJSONObject("ch2")?.let(::log)
                    days[k] = DayLog(ids, x.optBoolean("done"), x.optInt("rev"), x.optInt("xp"), ch, ch2, x.optInt("les"), x.optInt("ms"),
                        x.optInt("st"), x.optInt("pf"), x.optInt("se"), x.optInt("ls"),
                        x.optJSONArray("cl")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(), x.optBoolean("allq"))
                }
            }
            o.optJSONObject("arena")?.let { a ->
                val owned = a.optJSONArray("owned")?.let { arr -> (0 until arr.length()).map { arr.getString(it) }.toSet() } ?: emptySet()
                val rivals = a.optJSONArray("rivals")?.let { arr ->
                    (0 until arr.length()).map { arr.getJSONObject(it) }.associate { r ->
                        r.getString("id") to Rival(r.getString("id"), r.optString("name"), r.optString("pic"),
                            r.optInt("w"), r.optInt("l"), r.optInt("d"), r.optLong("t"))
                    }
                } ?: emptyMap()
                arena = Arena(
                    playerId = a.optString("id", UUID.randomUUID().toString()), coins = a.optInt("coins"),
                    owned = owned + FREE_COSMETICS, frame = a.optString("frame", "fr.lantern"),
                    title = a.optString("title", "ti.newbie"), effect = a.optString("effect", "fx.boom"),
                    sticker = a.optString("sticker", "st.none"), aura = a.optString("aura", "au.none"), wins = a.optInt("wins"), losses = a.optInt("losses"),
                    draws = a.optInt("draws"), streak = a.optInt("streak"), bestStreak = a.optInt("best"),
                    fastestMs = a.optInt("fastest", -1).takeIf { it >= 0 }, rivals = rivals,
                )
            }
        }
    }
}
