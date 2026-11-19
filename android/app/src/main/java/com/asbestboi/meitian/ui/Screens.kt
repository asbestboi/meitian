package com.asbestboi.meitian.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
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
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.Words
import com.asbestboi.meitian.data.lvl
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.Friend
import uniffi.meitian_core.dailyChallenge
import uniffi.meitian_core.phraseOfTheDay
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

@Composable
fun ScreenTitle(text: String) {
    Text(text.uppercase(), style = street(40.sp), color = Street.c.text, modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
}

// ---------- Today ----------

@Composable
fun TodayScreen(goToChallenge: () -> Unit, goToPractice: () -> Unit) {
    val app = LocalApp.current
    val nav = LocalNav.current
    var words by remember { mutableStateOf(listOf<CoreWord>()) }
    LaunchedEffect(app.todayKey, app.settings.swears) { words = app.todaysWords() }
    val h = LocalTime.now().hour
    val greet = when { h < 11 -> Triple("早上好", "Zǎoshang hǎo", "Good morning"); h < 14 -> Triple("中午好", "Zhōngwǔ hǎo", "Good noon")
        h < 18 -> Triple("下午好", "Xiàwǔ hǎo", "Good afternoon"); else -> Triple("晚上好", "Wǎnshang hǎo", "Good evening") }
    val done = app.today.learnedDone

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("${greet.first}，${app.profile.name}", fontSize = 26.sp, fontWeight = FontWeight.Black, color = Street.c.text, maxLines = 1)
                Row { PinyinText(greet.second, 14.sp); Text(" · ${greet.third}", fontSize = 14.sp, color = Street.c.secondary) }
                Text(LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, MMM d")), fontSize = 13.sp, color = Street.c.secondary)
            }
            Badge("🔥 ${app.streak}"); HSpacer(6.dp); Badge("⭐ ${app.xp}")
        }
        // today's words
        Column(Modifier.fillMaxWidth().block(if (done) Street.jade() else Street.warm()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row {
                Text(if (done) "TODAY'S WORDS · DONE" else "TODAY'S WORDS", style = street(22.sp), color = Color.White, modifier = Modifier.weight(1f))
                Text("${words.size} words", color = Color.White.copy(alpha = 0.85f), fontWeight = FontWeight.Bold)
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                words.forEach { w ->
                    Column(Modifier.clip(RoundedCornerShape(12.dp)).background(Street.c.card).border(2.dp, Street.c.ink, RoundedCornerShape(12.dp)).padding(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(w.hanzi, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text)
                        if (done || app.settings.showPinyin) PinyinText(w.pinyin, 12.sp) else Text("?", color = Street.c.secondary)
                    }
                }
            }
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White).border(2.dp, Street.c.ink, RoundedCornerShape(12.dp))
                .clickable { nav.show { LearnSession(words) { nav.close() } } }.padding(16.dp)) {
                Text(if (done) "PRACTICE THEM AGAIN ↻" else "LEARN TODAY'S WORDS ▶", style = street(18.sp), color = Street.c.red)
            }
        }
        // challenge
        val challenge = dailyChallenge(app.todayKey, words, if (app.profile.friend == "chinese") Friend.CHINESE else Friend.NON_CHINESE)
        Row(Modifier.fillMaxWidth().card().clickable(onClick = goToChallenge).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (app.today.challenge != null) "🏆" else "🗣️", fontSize = 36.sp); HSpacer(14.dp)
            Column(Modifier.weight(1f)) {
                Text(if (app.today.challenge != null) "CHALLENGE COMPLETE!" else "TODAY'S FRIEND CHALLENGE", style = street(18.sp), color = Street.c.text)
                Text(if (app.today.challenge != null) "+50 XP earned. 你真棒！" else challenge?.mission ?: "Learn today's words first.",
                    fontSize = 14.sp, color = Street.c.secondary, maxLines = 2)
            }
        }
        // reviews
        val due = app.dueWords.size
        Row(Modifier.fillMaxWidth().card().clickable(onClick = goToPractice).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("🃏", fontSize = 36.sp); HSpacer(14.dp)
            Column {
                Text(if (due > 0) "$due WORDS TO REVIEW" else "REVIEWS ALL CAUGHT UP", style = street(18.sp), color = Street.c.text)
                Text(if (due > 0) "Keep them fresh before they fade." else "${app.learnedWords.size} words learned so far.", fontSize = 14.sp, color = Street.c.secondary)
            }
        }
        // phrase of the day
        val p = phraseOfTheDay(app.todayKey)
        Column(Modifier.fillMaxWidth().card().padding(16.dp)) {
            Text("PHRASE OF THE DAY", fontWeight = FontWeight.Black, fontSize = 13.sp, color = Street.c.secondary)
            Gap(6.dp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    RubyText(p.hanzi, p.pinyin, 28.sp, FontWeight.Bold, alwaysShow = true)
                    Text(p.meaning, color = Street.c.text)
                }
                SpeakButton(p.hanzi)
            }
        }
        Gap(20.dp)
    }
}

@Composable
fun Badge(text: String) {
    Box(Modifier.clip(RoundedCornerShape(50)).background(Street.c.card).border(2.dp, Street.c.ink, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 5.dp)) {
        Text(text, fontWeight = FontWeight.Black, color = Street.c.text)
    }
}

@Composable
fun LearnSession(words: List<CoreWord>, close: () -> Unit) {
    val app = LocalApp.current
    var phase by remember { mutableIntStateOf(0) }
    var questions by remember { mutableStateOf(listOf<Question>()) }
    var score by remember { mutableIntStateOf(0) }
    var confetti by remember { mutableIntStateOf(0) }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); Spacer(Modifier.weight(1f))
                Text(when (phase) { 0 -> "SWIPE RIGHT IF YOU'VE GOT IT"; 1 -> "QUICK CHECK"; else -> "" }, fontWeight = FontWeight.Black, color = Street.c.secondary)
                Spacer(Modifier.weight(1f))
            }
            when (phase) {
                0 -> SwipeDeck(words) {
                    val pool = app.learnedWords + words
                    val kinds = Question.mixedKinds(app.settings)
                    questions = words.shuffled().mapIndexed { i, w -> Question.make(w, kinds[i % kinds.size], pool) }
                    phase = 1
                }
                1 -> QuizRunner(questions, onDone = { c -> score = c; app.finishLearning(words, c); phase = 2; confetti++ })
                else -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Spacer(Modifier.weight(1f))
                    Text("🎉", fontSize = 90.sp)
                    Text("太棒了！", style = street(48.sp), color = Street.c.red)
                    Text("tài bàng le · awesome!", color = Street.c.secondary, fontWeight = FontWeight.Bold)
                    Text("You learned ${words.size} new words today", fontWeight = FontWeight.Bold, color = Street.c.text)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatBox("$score/${words.size}", "quiz", Street.c.jade, Modifier.weight(1f))
                        StatBox("+${words.size * 10 + score * 5}", "XP", Street.c.gold, Modifier.weight(1f))
                        StatBox("${app.streak}", "streak", Street.c.red, Modifier.weight(1f))
                    }
                    Spacer(Modifier.weight(1f))
                    Text("Now try today's challenge: use one of these words with a friend!", color = Street.c.secondary, textAlign = TextAlign.Center)
                    BigButton("Done", onClick = close)
                }
            }
        }
        Confetti(confetti)
    }
}

// ---------- Challenge ----------

@Composable
fun ChallengeScreen() {
    val app = LocalApp.current
    val friendIsChinese = app.profile.friend == "chinese"
    val pool = app.today.newWordIds.mapNotNull { Words[it] }.ifEmpty { app.learnedWords }
    val c = dailyChallenge(app.todayKey, pool, if (friendIsChinese) Friend.CHINESE else Friend.NON_CHINESE)
    val checked = remember(app.todayKey, friendIsChinese) { mutableStateListOf<Int>() }
    var mood by remember { mutableStateOf<Int?>(null) }
    var note by remember { mutableStateOf("") }
    var confetti by remember { mutableIntStateOf(0) }
    val log = app.today.challenge

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            ScreenTitle("Challenge")
            Row(Modifier.fillMaxWidth().card().padding(5.dp)) {
                listOf(true to "🐼 Chinese friend", false to "🌍 Non‑Chinese friend").forEach { (chinese, label) ->
                    val on = friendIsChinese == chinese
                    Box(Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) Street.c.red else Color.Transparent)
                        .clickable(enabled = log == null) { app.profile = app.profile.copy(friend = if (chinese) "chinese" else "nonChinese"); app.save() }
                        .padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                        Text(label, fontWeight = FontWeight.Black, fontSize = 14.sp, color = if (on) Color.White else Street.c.text)
                    }
                }
            }
            if (c == null) {
                Text("Learn today's words first, then come back for your challenge.", color = Street.c.secondary)
            } else if (log != null) {
                Column(Modifier.fillMaxWidth().padding(vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("🏆", fontSize = 80.sp)
                    Text("CHALLENGE COMPLETE!", style = street(30.sp), color = Street.c.text)
                    Text("You used ${Words[log.wordId]?.hanzi ?: c.word.hanzi} with a friend today. 你真棒！(nǐ zhēn bàng)", color = Street.c.secondary, textAlign = TextAlign.Center)
                    if (log.note.isNotBlank()) Text("“${log.note}”", modifier = Modifier.fillMaxWidth().card().padding(14.dp), color = Street.c.text)
                    Text("New challenge tomorrow. 明天见！(míngtiān jiàn)", fontWeight = FontWeight.Bold, color = Street.c.text)
                }
            } else {
                Row(Modifier.fillMaxWidth().block(Street.level(c.word.lvl)).padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("TODAY'S WORD", fontWeight = FontWeight.Black, fontSize = 12.sp, color = Color.White.copy(alpha = 0.8f))
                        Text(c.word.hanzi, fontSize = 50.sp, fontWeight = FontWeight.Bold, color = Color.White)
                        Text("${c.word.pinyin} · ${c.word.meaning}", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                    SpeakButton(c.word.hanzi, 54.dp, Color.White)
                }
                Pill(c.title, Street.c.red)
                Text(c.mission, fontSize = 20.sp, fontWeight = FontWeight.Black, color = Street.c.text)
                Column(Modifier.fillMaxWidth().card().padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("YOUR SENTENCE", fontWeight = FontWeight.Black, fontSize = 12.sp, color = Street.c.secondary, modifier = Modifier.weight(1f))
                        Text("🐢 Slow", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.clickable { com.asbestboi.meitian.data.Speaker.say(c.word.example, true) }.padding(6.dp))
                        SpeakButton(c.word.example, 36.dp, Street.c.jade)
                    }
                    RubyText(c.word.example, c.word.examplePinyin, 25.sp, FontWeight.SemiBold, alwaysShow = true)
                    Text(c.word.exampleMeaning, color = Street.c.secondary)
                }
                Column(Modifier.fillMaxWidth().card().padding(8.dp)) {
                    c.steps.forEachIndexed { i, s ->
                        Row(Modifier.fillMaxWidth().clickable { if (i in checked) checked.remove(i) else checked.add(i) }.padding(10.dp)) {
                            Text(if (i in checked) "✅" else "⬜", fontSize = 20.sp); HSpacer(10.dp)
                            Text(s, color = if (i in checked) Street.c.secondary else Street.c.text, fontWeight = FontWeight.Medium)
                        }
                    }
                }
                Text("⭐ ${c.bonus}", color = Street.c.gold, fontWeight = FontWeight.Bold)
                if (checked.size == c.steps.size) {
                    Text("HOW DID IT GO?", style = street(20.sp), color = Street.c.text)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        listOf("😅" to "Tough", "🙂" to "Good", "🤩" to "Amazing").forEachIndexed { i, (e, l) ->
                            Column(Modifier.weight(1f).streetCard(if (mood == i) Street.c.gold.copy(alpha = 0.3f) else Street.c.card, Street.c.ink, shadow = 3.dp)
                                .clickable { mood = i }.padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(e, fontSize = 30.sp); Text(l, fontWeight = FontWeight.Bold, fontSize = 12.sp, color = Street.c.text)
                            }
                        }
                    }
                    OutlinedTextField(note, { note = it }, Modifier.fillMaxWidth(), placeholder = { Text("What did they say? Anything new?") })
                    BigButton("I did it! +50 XP", brush = Street.gold()) {
                        app.completeChallenge(c.word, if (friendIsChinese) Friend.CHINESE else Friend.NON_CHINESE, mood, note); confetti++
                    }
                } else Text("Tick off the steps as you go. 你可以的！(nǐ kěyǐ de)", fontSize = 13.sp, color = Street.c.secondary)
            }
            Gap(24.dp)
        }
        Confetti(confetti)
    }
}

// ---------- Progress & settings ----------

@Composable
fun ProgressScreen() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val s = app.settings
    fun set(n: com.asbestboi.meitian.data.Settings) { app.settings = n; app.save() }
    var confirmReset by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenTitle("Progress")
        val lv = app.level
        Row(Modifier.fillMaxWidth().card().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(80.dp).clip(RoundedCornerShape(50)).border(6.dp, Street.c.gold, RoundedCornerShape(50)), contentAlignment = Alignment.Center) {
                Text("Lv ${lv.level}", style = street(22.sp), color = Street.c.text)
            }
            HSpacer(16.dp)
            Column {
                Text(app.profile.name.ifBlank { "Learner" }, style = street(26.sp), color = Street.c.text)
                Text("${app.xp} XP · ${lv.xpToNext} to level ${lv.level.toInt() + 1}", color = Street.c.secondary)
                Gap(4.dp)
                Pill("Learning HSK ${app.currentLevel}", Street.levelColor(app.currentLevel))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatBox("${app.streak}", "Day streak", Street.c.red, Modifier.weight(1f)); StatBox("${app.bestStreak}", "Best streak", Street.c.gold, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatBox("${app.cards.size}", "Words learned", Street.c.jade, Modifier.weight(1f)); StatBox("${app.days.values.count { it.challenge != null }}", "Challenges", Street.c.plum, Modifier.weight(1f))
        }
        // activity calendar (15 weeks)
        Column(Modifier.fillMaxWidth().card().padding(14.dp)) {
            Text("ACTIVITY", fontWeight = FontWeight.Black, color = Street.c.text)
            Gap(8.dp)
            val today = LocalDate.now()
            val start = today.minusDays((14 * 7 + today.dayOfWeek.value - 1).toLong())
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                (0 until 15).forEach { w ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        (0 until 7).forEach { d ->
                            val date = start.plusDays((w * 7 + d).toLong())
                            val log = app.days[date.toString()]
                            val score = log?.let { (if (it.learnedDone) 1 else 0) + (if (it.reviewed > 0) 1 else 0) + (if (it.challenge != null) 1 else 0) } ?: 0
                            val color = when { date.isAfter(today) -> Color.Transparent; score == 0 -> Street.c.ink.copy(alpha = 0.08f)
                                score == 1 -> Street.c.jade.copy(alpha = 0.4f); score == 2 -> Street.c.jade.copy(alpha = 0.7f); else -> Street.c.jade }
                            Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(3.dp)).background(color))
                        }
                    }
                }
            }
        }
        // levels
        Column(Modifier.fillMaxWidth().card().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("LEVELS", fontWeight = FontWeight.Black, color = Street.c.text)
            Words.levels.forEach { l ->
                val total = Words.level(l).size; val done = app.learnedCount(l)
                Row { Text("HSK $l", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f)); Text("$done/$total", color = Street.c.secondary) }
                Box(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(5.dp)).background(Street.c.ink.copy(alpha = 0.08f))) {
                    Box(Modifier.fillMaxWidth(done / total.toFloat().coerceAtLeast(1f)).height(10.dp).background(Street.level(l)))
                }
            }
        }
        SectionTitle("Pinyin")
        Column(Modifier.fillMaxWidth().card()) {
            ToggleRow("Show pinyin", "Pinyin above characters. Turn off to test your reading.", s.showPinyin) { set(s.copy(showPinyin = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            ToggleRow("Tone colors", "1 red · 2 orange · 3 green · 4 blue", s.toneColors) { set(s.copy(toneColors = it)) }
        }
        SectionTitle("Sound & exercises")
        Column(Modifier.fillMaxWidth().card()) {
            ToggleRow("Sound effects", null, s.sounds) { set(s.copy(sounds = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            ToggleRow("Listening exercises", if (s.listening && !s.canListen) "Paused for now" else null, s.listening) { set(s.copy(listening = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            ToggleRow("Speaking exercises", if (s.speaking && !s.canSpeak) "Paused for now" else "Say words out loud, checked with speech recognition.", s.speaking) { set(s.copy(speaking = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            Row(Modifier.fillMaxWidth().padding(16.dp)) {
                if (!s.canListen || !s.canSpeak) {
                    Text("▶ I can listen & speak again", color = Street.c.red, fontWeight = FontWeight.Black,
                        modifier = Modifier.clickable { set(s.copy(noListenUntil = 0, noSpeakUntil = 0)) })
                } else {
                    val hour = System.currentTimeMillis() + 3_600_000
                    Text("🔇 Can't listen 1h", color = Street.c.red, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f).clickable { set(s.copy(noListenUntil = hour)) })
                    Text("🎙️ Can't speak 1h", color = Street.c.red, fontWeight = FontWeight.Black, modifier = Modifier.clickable { set(s.copy(noSpeakUntil = hour)) })
                }
            }
        }
        SectionTitle("Content")
        Column(Modifier.fillMaxWidth().card()) {
            ToggleRow("Swear words 🤬", "Adds the street deck: one swear a day, Swear Sprint, rude cosmetics. Battles only match players with the same setting.", s.swears) {
                set(s.copy(swears = it))
            }
        }
        SectionTitle("Profile")
        Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("New words a day: ${app.profile.dailyGoal}", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f))
                Text("−", style = street(28.sp), color = Street.c.red, modifier = Modifier.clickable { app.profile = app.profile.copy(dailyGoal = (app.profile.dailyGoal - 1).coerceAtLeast(1)); app.save() }.padding(horizontal = 12.dp))
                Text("+", style = street(28.sp), color = Street.c.red, modifier = Modifier.clickable { app.profile = app.profile.copy(dailyGoal = (app.profile.dailyGoal + 1).coerceAtMost(15)); app.save() }.padding(horizontal = 12.dp))
            }
            Text("✅ Retake placement quiz", fontWeight = FontWeight.Black, color = Street.c.text,
                modifier = Modifier.clickable { nav.show { OnboardingScreen(retakeOnly = true) { nav.close() } } })
            Text(if (confirmReset) "⚠️ Tap again to delete everything (can't be undone)" else "🗑️ Reset all progress", fontWeight = FontWeight.Black, color = Street.c.red,
                modifier = Modifier.clickable { if (confirmReset) { app.resetAll(); confirmReset = false } else confirmReset = true })
        }
        Gap(30.dp)
    }
}

@Composable
fun ToggleRow(title: String, subtitle: String?, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, color = Street.c.text)
            subtitle?.let { Text(it, fontSize = 12.sp, color = Street.c.secondary) }
        }
        Switch(value, onChange)
    }
}

@Suppress("unused")
private val unusedHeight = Modifier.height(0.dp)
