package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.LocalNav
import com.asbestboi.meitian.data.ContentSync
import com.asbestboi.meitian.data.Kind
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.STREET_LEVEL
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.Speaker
import com.asbestboi.meitian.data.Words
import com.asbestboi.meitian.data.levelLabel
import com.asbestboi.meitian.data.lvl
import kotlinx.coroutines.delay
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.sprintMultiplier

enum class PracticeMode(val title: String) { Review("Review"), Listening("Listening"), Speaking("Speaking"), Mixed("Speed mix"), Weak("Weak words") }

/** Word library filter by how the learner is doing with each word. */
enum class WordFilter(val label: String) { All("all"), Learned("learned"), Weak("⚡ weak"), Due("due"), Mastered("👑 mastered"), New("not yet") }

@Composable
fun PracticeScreen() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val learned = app.learnedWords
    val due = app.dueWords.size
    val weak = app.weakWords(12)
    val sentenceCount = ContentSync.stats.sentences.toInt()

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { ScreenTitle("Practice") }
        item {
            Column(Modifier.fillMaxWidth().block(Street.sky()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(if (due > 0) "$due DUE FOR REVIEW" else "ALL CAUGHT UP ✨", style = street(26.sp), color = Color.White)
                Text(if (due > 0) "Spaced repetition: review right before you'd forget." else "Come back tomorrow, or pick a mode below. ${app.masteredCount} mastered.",
                    color = Color.White.copy(alpha = 0.9f))
                if (due > 0) BigButton("Start review") { nav.show { PracticeSession(PracticeMode.Review) { nav.close() } } }
            }
        }
        item { Text("practice", style = street(22.sp), color = Street.c.text, modifier = Modifier.padding(top = 8.dp)) }
        item {
            // every mode as the same kind of tile, two per row
            val tiles = buildList {
                add(ModeTile("⚡", "weak words", if (weak.size >= 4) "${weak.size} to fix" else "none yet", weak.size >= 4) {
                    nav.show { PracticeSession(PracticeMode.Weak) { nav.close() } } })
                add(ModeTile("💬", "sentences", if (sentenceCount > 0) "build & translate" else "downloading…", sentenceCount > 0) {
                    nav.show { SentenceSession { nav.close() } } })
                add(ModeTile("🎧", "listening", "10 questions", learned.isNotEmpty() && app.settings.listening) {
                    nav.show { PracticeSession(PracticeMode.Listening) { nav.close() } } })
                add(ModeTile("🎙️", "speaking", "10 questions", learned.isNotEmpty() && app.settings.speaking) {
                    nav.show { PracticeSession(PracticeMode.Speaking) { nav.close() } } })
                add(ModeTile("🔀", "speed mix", "everything, fast", learned.isNotEmpty()) {
                    nav.show { PracticeSession(PracticeMode.Mixed) { nav.close() } } })
                if (app.settings.swears) add(ModeTile("🤬", "swear sprint", "60 s rapid fire · 18+", true) {
                    nav.show { SwearSprint { nav.close() } } })
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                tiles.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        pair.forEach { t -> ModeTileView(t, learned.isEmpty(), Modifier.weight(1f)) }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
        item { Text("read", style = street(22.sp), color = Street.c.text, modifier = Modifier.padding(top = 8.dp)) }
        item { StoryHub() }
        item { StoryHub(chats = true) }
        item {
            Row(Modifier.fillMaxWidth().card().clickable { nav.show { WordLibrary { nav.close() } } }.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("📚", fontSize = 32.sp); HSpacer(16.dp)
                Column(Modifier.weight(1f)) {
                    Text("my words", style = street(18.sp), color = Street.c.text)
                    Text("${app.cards.size} learned · search the whole HSK list", fontSize = 13.sp, color = Street.c.secondary)
                }
                Text("›", style = street(28.sp), color = Street.c.secondary)
            }
        }
        item { Gap(32.dp) }
    }
}

private class ModeTile(val emoji: String, val title: String, val subtitle: String, val enabled: Boolean, val open: () -> Unit)

@Composable
private fun ModeTileView(t: ModeTile, noWords: Boolean, modifier: Modifier) {
    Column(modifier.card().clickable(enabled = t.enabled, onClick = t.open).padding(16.dp)
        .graphicsLayer { alpha = if (t.enabled) 1f else 0.45f }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(t.emoji, fontSize = 30.sp)
        Text(t.title, style = street(16.sp), color = Street.c.text)
        Text(if (!t.enabled && noWords) "learn words first" else t.subtitle, fontSize = 12.sp, color = Street.c.secondary, maxLines = 1)
    }
}

/** Search and browse every word, with how the learner is doing on each. */
@Composable
fun WordLibrary(close: () -> Unit) {
    val app = LocalApp.current
    var search by remember { mutableStateOf("") }
    var filter by remember { mutableIntStateOf(0) }
    var status by remember { mutableStateOf(WordFilter.All) }
    var detail by remember { mutableStateOf<CoreWord?>(null) }
    val shown = remember(search, filter, status, app.settings.swears, Words.all.size, app.cards.toMap()) {
        val q = search.trim().lowercase()
        val weakIds = if (status == WordFilter.Weak) app.weakWords(200).map { it.id }.toSet() else emptySet()
        Words.visible(app.settings.swears).filter { w ->
            val c = app.cards[w.id]
            val statusOk = when (status) {
                WordFilter.All -> true
                WordFilter.Learned -> c != null
                WordFilter.Weak -> w.id in weakIds
                WordFilter.Due -> c != null && c.dueDay <= app.todayNumber
                WordFilter.Mastered -> c?.mastered == true
                WordFilter.New -> c == null
            }
            statusOk && (filter == 0 || w.lvl == filter) &&
                (q.isEmpty() || w.hanzi.contains(q) || w.meaning.lowercase().contains(q) || uniffi.meitian_core.toneless(w.pinyin).contains(uniffi.meitian_core.toneless(q)))
        }
    }

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); HSpacer(12.dp)
                Text("my words", style = street(24.sp), color = Street.c.text)
            }
        }
        item {
            OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search hanzi, pinyin or English") }, singleLine = true)
            Gap(8.dp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (listOf(0 to "All") + Words.levels.map { it to "HSK $it" } + if (app.settings.swears) listOf(STREET_LEVEL to "🤬") else emptyList()).forEach { (l, label) ->
                    Box(Modifier.clip(RoundedCornerShape(8.dp)).background(if (filter == l) Street.c.red else Street.c.card).clickable { filter = l }
                        .padding(horizontal = 10.dp, vertical = 6.dp)) {
                        Text(label, fontWeight = FontWeight.Bold, fontSize = 12.sp, color = if (filter == l) Color.White else Street.c.text)
                    }
                }
            }
            Gap(6.dp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WordFilter.entries.forEach { s ->
                    Box(Modifier.clip(RoundedCornerShape(50)).background(if (status == s) Street.c.ink else Street.c.card).clickable { status = s }
                        .padding(horizontal = 12.dp, vertical = 6.dp)) {
                        Text(s.label, fontWeight = FontWeight.Bold, fontSize = 12.sp, color = if (status == s) Street.c.paper else Street.c.text)
                    }
                }
            }
            Gap(4.dp)
            Text("${shown.size} words", fontSize = 12.sp, color = Street.c.secondary, fontWeight = FontWeight.SemiBold)
        }
        items(shown, key = { it.id }) { w ->
            Row(Modifier.fillMaxWidth().streetCard(Street.c.card, Street.c.ink, shadow = 3.dp).clickable { detail = w }.padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(w.hanzi, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text, modifier = Modifier.padding(end = 12.dp))
                Column(Modifier.weight(1f)) {
                    PinyinText(w.pinyin, 14.sp)
                    Text(w.meaning, fontSize = 13.sp, color = Street.c.secondary, maxLines = 1)
                }
                val c = app.cards[w.id]
                if (c != null) Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(end = 8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        (1..6).forEach { b ->
                            Box(Modifier.size(width = 5.dp, height = 10.dp).clip(RoundedCornerShape(50))
                                .background(if (b <= c.box) Street.c.jade else Street.c.secondary.copy(alpha = 0.2f)))
                        }
                    }
                    Text("✓${c.correct} ✗${c.wrong}", fontSize = 11.sp, color = Street.c.secondary, fontWeight = FontWeight.SemiBold)
                }
                Text(if (c == null) "·" else if (c.mastered) "👑" else "✅")
            }
        }
        item { Gap(32.dp) }
    }
    detail?.let { w -> WordDetail(w) { detail = null } }
}

@Composable
fun WordDetail(w: CoreWord, close: () -> Unit) {
    val app = LocalApp.current
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)).clickable(onClick = close), contentAlignment = Alignment.BottomCenter) {
        Column(Modifier.fillMaxWidth().background(Street.c.paper, RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)).clickable(enabled = false) {}
            .verticalScroll(rememberScrollState()).padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Pill(w.levelLabel, Street.levelColor(w.lvl))
            RubyText(w.hanzi, w.pinyin, 70.sp, FontWeight.SemiBold, center = true)
            PinyinText(w.pinyin, 24.sp, FontWeight.Black)
            Text(w.meaning, fontSize = 19.sp, color = Street.c.text)
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                SpeakButton(w.hanzi, 56.dp)
                Box(Modifier.clickable { Speaker.say(w.hanzi, true) }.padding(14.dp)) { Text("🐢", fontSize = 26.sp) }
            }
            if (w.example.isNotEmpty()) Column(Modifier.fillMaxWidth().card().padding(14.dp)) {
                RubyText(w.example, w.examplePinyin, 22.sp, alwaysShow = true)
                Text(w.exampleMeaning, color = Street.c.text)
            }
            ExampleSentences(w)
            app.cards[w.id]?.let { Text("Box ${it.box} of 6 · ✓ ${it.correct} ✗ ${it.wrong}", color = Street.c.secondary, fontWeight = FontWeight.Bold) }
            BigButton("Close", onClick = close)
        }
    }
}

@Composable
fun PracticeSession(mode: PracticeMode, close: () -> Unit) {
    val app = LocalApp.current
    val questions = remember {
        val learned = app.learnedWords
        val kinds = Question.mixedKinds(app.settings)
        when (mode) {
            PracticeMode.Review -> app.dueWords.take(15).mapIndexed { i, w -> Question.make(w, kinds[i % kinds.size], learned) }
            PracticeMode.Listening -> learned.shuffled().take(10).map { Question.make(it, Kind.Listen, learned) }
            PracticeMode.Speaking -> learned.shuffled().take(8).map { Question.make(it, Kind.Speak, learned) }
            PracticeMode.Mixed -> learned.shuffled().take(10).map { Question.make(it, kinds.random(), learned) }
            PracticeMode.Weak -> app.weakWords(12).mapIndexed { i, w -> Question.make(w, kinds[i % kinds.size], learned) }
        }
    }
    var score by remember { mutableStateOf<Int?>(null) }
    var confetti by remember { mutableIntStateOf(0) }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); Spacer(Modifier.weight(1f)); Text(mode.title.lowercase(), style = street(20.sp), color = Street.c.text); Spacer(Modifier.weight(1f))
            }
            val s = score
            if (questions.isEmpty()) Text("Nothing to practice yet. Learn some words first!", color = Street.c.secondary)
            else if (s == null) QuizRunner(questions, onAnswer = { q, right ->
                if (mode == PracticeMode.Review || mode == PracticeMode.Weak) app.grade(q.word, right) else if (right) app.addXP(2)
            }, onDone = {
                score = it; confetti++
                if (mode == PracticeMode.Listening || mode == PracticeMode.Speaking) app.count(com.asbestboi.meitian.data.AppState.Counter.ListenSpeak)
            })
            else Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Spacer(Modifier.weight(1f))
                Text("$s/${questions.size}", style = street(90.sp), color = Street.c.text)
                Text(if (s == questions.size) "PERFECT! 完美 wánměi!" else if (s * 2 >= questions.size) "NICE WORK! 不错 búcuò!" else "KEEP GOING! 加油 jiāyóu!",
                    style = street(26.sp), color = Street.c.red, textAlign = TextAlign.Center)
                Text(if (mode == PracticeMode.Review) "Words you missed will come back sooner." else "Every round makes them stick.", color = Street.c.secondary)
                Spacer(Modifier.weight(1f))
                BigButton("Done", onClick = close)
            }
        }
        Confetti(confetti)
    }
}

/** 🤬 Swear Sprint: learn a few street words, then 60 s of rapid fire with combo multipliers. */
@Composable
fun SwearSprint(close: () -> Unit) {
    val app = LocalApp.current
    var phase by remember { mutableIntStateOf(0) } // 0 intro, 1 learn, 2 countdown, 3 sprint, 4 results
    var newWords by remember { mutableStateOf(listOf<CoreWord>()) }
    var count by remember { mutableIntStateOf(3) }
    var q by remember { mutableStateOf<Question?>(null) }
    var picked by remember { mutableStateOf<CoreWord?>(null) }
    var reveal by remember { mutableStateOf(false) }
    var score by remember { mutableIntStateOf(0) }
    var combo by remember { mutableIntStateOf(0) }
    var bestCombo by remember { mutableIntStateOf(0) }
    var correct by remember { mutableIntStateOf(0) }
    var answered by remember { mutableIntStateOf(0) }
    var endsAt by remember { mutableLongStateOf(0L) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var confetti by remember { mutableIntStateOf(0) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences("meitian", 0) }
    var best by remember { mutableIntStateOf(prefs.getInt("sprintBest", 0)) }
    var newBest by remember { mutableStateOf(false) }

    fun pool() = Words.swears.filter { app.cards[it.id] != null } + newWords
    fun next() {
        val words = pool().ifEmpty { Words.swears }
        val w = words.random()
        q = Question.make(w, if (kotlin.random.Random.nextBoolean()) Kind.HanziToMeaning else Kind.MeaningToHanzi, Words.swears)
        picked = null; reveal = false
    }

    LaunchedEffect(phase) {
        when (phase) {
            2 -> { for (n in 3 downTo 1) { count = n; Sfx.play(SoundId.TICK); delay(700) }; phase = 3 }
            3 -> {
                score = 0; combo = 0; bestCombo = 0; correct = 0; answered = 0; newBest = false
                endsAt = System.currentTimeMillis() + 60_000; next(); Sfx.play(SoundId.GO)
                while (System.currentTimeMillis() < endsAt) { now = System.currentTimeMillis(); delay(100) }
                if (score > best) { best = score; prefs.edit().putInt("sprintBest", score).apply(); newBest = true }
                app.addXP(correct * 3)
                phase = 4; confetti++
            }
        }
    }
    LaunchedEffect(picked) {
        val p = picked ?: return@LaunchedEffect
        val right = p.id == q?.word?.id
        delay(if (right) 250 else 800)
        if (phase == 3) next()
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton { phase = 99; close() }; Spacer(Modifier.weight(1f)); Text("🤬 swear sprint", style = street(24.sp), color = Street.c.text); Spacer(Modifier.weight(1f))
            }
            when (phase) {
                0 -> {
                    val fresh = Words.swears.filter { app.cards[it.id] == null }
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text("🤬", fontSize = 90.sp)
                        Text("learn to swear fast", style = street(44.sp), color = Street.c.text, textAlign = TextAlign.Center)
                        Text("${if (fresh.isEmpty()) "You've unlocked every street word." else "${minOf(5, fresh.size)} new words first, then"} 60 seconds of rapid fire. 3 right in a row = ×2, 6 = ×3… up to ×5.",
                            color = Street.c.secondary, textAlign = TextAlign.Center)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Pill("Best $best", Street.c.gold); Pill("${Words.swears.size - fresh.size}/${Words.swears.size} learned", Street.c.pink, 3f)
                        }
                        Text("Real insults: great for understanding, use with care. 😉", color = Street.c.red, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    }
                    BigButton(if (fresh.isEmpty()) "Sprint!" else "Learn & sprint", brush = Street.pink()) {
                        newWords = fresh.take(5); phase = if (newWords.isEmpty()) 2 else 1
                    }
                }
                1 -> SwipeDeck(newWords) { app.addToReview(newWords); phase = 2 }
                2 -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("$count", style = street(160.sp), color = Street.c.pink) }
                3 -> {
                    val left = ((endsAt - now) / 1000.0).coerceAtLeast(0.0)
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("${kotlin.math.ceil(left).toInt()}", style = street(56.sp), color = if (left < 10) Street.c.red else Street.c.text, modifier = Modifier.weight(1f))
                        Column(horizontalAlignment = Alignment.End) { Text("$score", style = street(46.sp), color = Street.c.text); Text("points", fontWeight = FontWeight.Bold, fontSize = 12.sp, color = Street.c.secondary) }
                    }
                    LinearProgressIndicator(progress = { (left / 60).toFloat() }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)), color = Street.c.pink)
                    val mult = sprintMultiplier(combo.toUInt()).toInt()
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Pill("×$mult combo 🔥", if (mult > 1) Street.c.pink else Street.c.secondary, -4f); Spacer(Modifier.weight(1f))
                        Text("$combo in a row", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                    }
                    Spacer(Modifier.weight(1f))
                    q?.let { question ->
                        FastQuestion(question, picked, picked != null, reveal) { o ->
                            picked = o; answered++
                            if (o.id == question.word.id) {
                                correct++; combo++; bestCombo = maxOf(bestCombo, combo)
                                score += 10 * sprintMultiplier(combo.toUInt()).toInt()
                                Sfx.play(if (combo % 3 == 0) SoundId.COIN else SoundId.CORRECT)
                            } else { combo = 0; reveal = true; Sfx.play(SoundId.WRONG) }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                }
                4 -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Spacer(Modifier.weight(1f))
                    Text(if (newBest) "new best!" else "time!", style = street(60.sp), color = if (newBest) Street.c.gold else Street.c.pink)
                    Text("$score", style = street(110.sp), color = Street.c.text)
                    Text("points", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatBox("$correct/$answered", "right", modifier = Modifier.weight(1f))
                        StatBox("×${sprintMultiplier(bestCombo.toUInt())}", "top combo", modifier = Modifier.weight(1f))
                        StatBox("+${correct * 3}", "XP", modifier = Modifier.weight(1f))
                    }
                    Spacer(Modifier.weight(1f))
                    BigButton("Again", brush = Street.pink()) { newWords = emptyList(); phase = 2 }
                    Text("Done", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.clickable(onClick = close).padding(8.dp))
                }
            }
        }
        Confetti(confetti)
    }
}
