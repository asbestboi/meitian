package com.asbestboi.meitian.ui

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

enum class PracticeMode(val title: String) { Review("Review"), Listening("Listening"), Speaking("Speaking"), Mixed("Speed mix") }

@Composable
fun PracticeScreen() {
    val app = LocalApp.current
    val nav = LocalNav.current
    var search by remember { mutableStateOf("") }
    var filter by remember { mutableIntStateOf(0) }
    var detail by remember { mutableStateOf<CoreWord?>(null) }
    val learned = app.learnedWords
    val due = app.dueWords.size

    val shown = remember(search, filter, app.settings.swears, Words.all.size) {
        val q = search.trim().lowercase()
        Words.visible(app.settings.swears).filter { w ->
            (filter == 0 || w.lvl == filter) &&
                (q.isEmpty() || w.hanzi.contains(q) || w.meaning.lowercase().contains(q) || uniffi.meitian_core.toneless(w.pinyin).contains(uniffi.meitian_core.toneless(q)))
        }
    }

    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { ScreenTitle("Practice") }
        item {
            Column(Modifier.fillMaxWidth().block(Street.sky()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(if (due > 0) "$due DUE FOR REVIEW" else "ALL CAUGHT UP ✨", style = street(26.sp), color = Color.White)
                Text(if (due > 0) "Spaced repetition: review right before you'd forget." else "Come back tomorrow, or play a game below. ${app.masteredCount} mastered.",
                    color = Color.White.copy(alpha = 0.9f))
                if (due > 0) BigButton("Start review", brush = Street.ink()) { nav.show { PracticeSession(PracticeMode.Review) { nav.close() } } }
            }
        }
        item {
            val count = ContentSync.stats.sentences.toInt()
            Row(Modifier.fillMaxWidth().card().clickable(enabled = count > 0) { nav.show { SentenceSession { nav.close() } } }.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("💬", fontSize = 38.sp); HSpacer(12.dp)
                Column(Modifier.weight(1f)) {
                    Text("SENTENCES", style = street(24.sp), color = Street.c.text)
                    Text(if (count > 0) "Build, fill and translate real sentences at your level." else "Downloading sentence lessons… needs internet once.",
                        fontSize = 13.sp, color = Street.c.secondary)
                }
                Text("›", style = street(28.sp), color = Street.c.secondary)
            }
        }
        if (app.settings.swears) item {
            Row(Modifier.fillMaxWidth().block(Street.ink()).clickable { nav.show { SwearSprint { nav.close() } } }.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🤬", fontSize = 42.sp); HSpacer(12.dp)
                Column(Modifier.weight(1f)) {
                    Text("SWEAR SPRINT", style = street(30.sp), color = Color.White)
                    Text("Learn street Chinese fast: flip cards, then 60 s of rapid fire. Combos multiply.", color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
                }
                Pill("18+", Street.c.pink, 6f)
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                listOf(Triple("👂", PracticeMode.Listening, app.settings.listening), Triple("🎙️", PracticeMode.Speaking, app.settings.speaking),
                    Triple("⚡", PracticeMode.Mixed, true)).forEach { (icon, mode, on) ->
                    val enabled = on && learned.isNotEmpty()
                    Column(Modifier.weight(1f).card().clickable(enabled = enabled) { nav.show { PracticeSession(mode) { nav.close() } } }.padding(12.dp)) {
                        GradientIcon(icon, when (mode) { PracticeMode.Listening -> Street.sky(); PracticeMode.Speaking -> Street.pink(); else -> Street.gold() })
                        Gap(8.dp)
                        Text(mode.title.uppercase(), style = street(16.sp), color = Street.c.text)
                        Text(if (enabled) "10 questions" else "Learn words first", fontSize = 11.sp, color = Street.c.secondary)
                    }
                }
            }
        }
        item {
            Text("WORD LIBRARY", style = street(24.sp), color = Street.c.text, modifier = Modifier.padding(top = 8.dp))
            OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search hanzi, pinyin or English") }, singleLine = true)
            Gap(8.dp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (listOf(0 to "All") + Words.levels.map { it to "HSK $it" } + if (app.settings.swears) listOf(STREET_LEVEL to "🤬") else emptyList()).forEach { (l, label) ->
                    Box(Modifier.clip(RoundedCornerShape(8.dp)).background(if (filter == l) Street.c.red else Street.c.card).clickable { filter = l }
                        .padding(horizontal = 10.dp, vertical = 6.dp)) {
                        Text(label, fontWeight = FontWeight.Black, fontSize = 12.sp, color = if (filter == l) Color.White else Street.c.text)
                    }
                }
            }
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
                Text(if (c == null) "·" else if (c.mastered) "👑" else "✅")
            }
        }
        item { Gap(30.dp) }
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
            BigButton("Close", brush = Street.ink(), onClick = close)
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
        }
    }
    var score by remember { mutableStateOf<Int?>(null) }
    var confetti by remember { mutableIntStateOf(0) }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); Spacer(Modifier.weight(1f)); Text(mode.title.uppercase(), style = street(20.sp), color = Street.c.text); Spacer(Modifier.weight(1f))
            }
            val s = score
            if (questions.isEmpty()) Text("Nothing to practice yet. Learn some words first!", color = Street.c.secondary)
            else if (s == null) QuizRunner(questions, onAnswer = { q, right ->
                if (mode == PracticeMode.Review) app.grade(q.word, right) else if (right) app.addXP(2)
            }, onDone = { score = it; confetti++ })
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
            2 -> { for (n in 3 downTo 1) { count = n; Sfx.play(Sfx.Sound.Tick); delay(700) }; phase = 3 }
            3 -> {
                score = 0; combo = 0; bestCombo = 0; correct = 0; answered = 0; newBest = false
                endsAt = System.currentTimeMillis() + 60_000; next(); Sfx.play(Sfx.Sound.Go)
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
                CloseButton { phase = 99; close() }; Spacer(Modifier.weight(1f)); Text("🤬 SWEAR SPRINT", style = street(24.sp), color = Street.c.text); Spacer(Modifier.weight(1f))
            }
            when (phase) {
                0 -> {
                    val fresh = Words.swears.filter { app.cards[it.id] == null }
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text("🤬", fontSize = 90.sp)
                        Text("LEARN TO SWEAR FAST", style = street(44.sp), color = Street.c.text, textAlign = TextAlign.Center)
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
                        Column(horizontalAlignment = Alignment.End) { Text("$score", style = street(46.sp), color = Street.c.text); Text("POINTS", fontWeight = FontWeight.Black, fontSize = 12.sp, color = Street.c.secondary) }
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
                                Sfx.play(if (combo % 3 == 0) Sfx.Sound.Coin else Sfx.Sound.Correct)
                            } else { combo = 0; reveal = true; Sfx.play(Sfx.Sound.Wrong) }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                }
                4 -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Spacer(Modifier.weight(1f))
                    Text(if (newBest) "NEW BEST!" else "TIME!", style = street(60.sp), color = if (newBest) Street.c.gold else Street.c.pink)
                    Text("$score", style = street(110.sp), color = Street.c.text)
                    Text("points", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatBox("$correct/$answered", "right", modifier = Modifier.weight(1f))
                        StatBox("×${sprintMultiplier(bestCombo.toUInt())}", "top combo", modifier = Modifier.weight(1f))
                        StatBox("+${correct * 3}", "XP", modifier = Modifier.weight(1f))
                    }
                    Spacer(Modifier.weight(1f))
                    BigButton("Again", brush = Street.pink()) { newWords = emptyList(); phase = 2 }
                    Text("Done", fontWeight = FontWeight.Black, color = Street.c.text, modifier = Modifier.clickable(onClick = close).padding(8.dp))
                }
            }
        }
        Confetti(confetti)
    }
}
