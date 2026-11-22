package com.asbestboi.meitian.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.offset
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
import androidx.compose.foundation.layout.width
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
import uniffi.meitian_core.SoundId
import com.asbestboi.meitian.data.Sfx
import kotlinx.coroutines.launch
import com.asbestboi.meitian.data.ContentSync
import com.asbestboi.meitian.LocalNav
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.Words
import com.asbestboi.meitian.data.lvl
import uniffi.meitian_core.CoreWord
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

@Composable
fun ScreenTitle(text: String) {
    Text(text.lowercase(), style = street(40.sp), color = Street.c.text, modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
}

@Composable
fun Badge(text: String) {
    Box(Modifier.clip(RoundedCornerShape(50)).background(Street.c.card).border(2.dp, Street.c.ink, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 5.dp)) {
        Text(text, fontWeight = FontWeight.Bold, color = Street.c.text)
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
                Text(when (phase) { 0 -> "SWIPE RIGHT IF YOU'VE GOT IT"; 1 -> "QUICK CHECK"; else -> "" }, fontWeight = FontWeight.Bold, color = Street.c.secondary)
                Spacer(Modifier.weight(1f))
            }
            when (phase) {
                0 -> SwipeDeck(words) {
                    val pool = app.learnedWords + words
                    val kinds = Question.mixedKinds(app.settings)
                    questions = words.shuffled().mapIndexed { i, w -> Question.make(w, kinds[i % kinds.size], pool) }
                    phase = 1
                }
                1 -> QuizRunner(questions, useHearts = true, onFailed = { phase = 3 }, onDone = { c ->
                    score = c; app.finishLearning(words, c); phase = 2; confetti++
                    if (c == questions.size) app.count(com.asbestboi.meitian.data.AppState.Counter.Perfect)
                })
                // from the top: cards and a fresh quiz; nothing was saved from this try
                3 -> OutOfHearts(onRetry = { questions = emptyList(); score = 0; phase = 0 }, onQuit = close)
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
                    Text("Nice! The next lesson is waiting on your path.", color = Street.c.secondary, textAlign = TextAlign.Center)
                    BigButton("Done", onClick = close)
                }
            }
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
    var settingsOpen by remember { mutableStateOf(false) }
    if (settingsOpen) androidx.activity.compose.BackHandler { settingsOpen = false }
    val context = androidx.compose.ui.platform.LocalContext.current
    // Android 13+: ask before the first reminder can show
    val notifyPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted -> app.setReminder(granted) }
    val invitePermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) {}

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (!settingsOpen) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { ScreenTitle("Profile") }
            Text("⚙️", fontSize = 24.sp, modifier = Modifier.clip(RoundedCornerShape(50)).clickable { settingsOpen = true }.padding(10.dp))
        }
        val lv = app.level
        Row(Modifier.fillMaxWidth().card().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            val picker = rememberPicturePicker()
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.clickable(enabled = !picker.busy) { picker.pick() }) {
                MyPicture(84.dp)
                Text(if (picker.busy) "…" else if (com.asbestboi.meitian.data.Online.profile?.avatar.isNullOrEmpty()) "＋ add picture" else "change", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.red)
                picker.note?.let { Text(it, fontSize = 11.sp, color = Street.c.secondary, textAlign = TextAlign.Center, modifier = Modifier.width(96.dp)) }
            }
            HSpacer(16.dp)
            Column {
                Text(app.profile.name.ifBlank { "Learner" }, style = street(26.sp), color = Street.c.text)
                Text("Lv ${lv.level} · ${app.xp} XP · ${lv.xpToNext} to level ${lv.level.toInt() + 1}", color = Street.c.secondary)
                Gap(4.dp)
                Pill("Learning HSK ${app.currentLevel}", Street.levelColor(app.currentLevel))
                Gap(6.dp)
                ArenaBadge(app.arenaTheme, background = Street.c.paper)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatBox("${app.streak}", "Day streak", Street.c.red, Modifier.weight(1f)); StatBox("${app.bestStreak}", "Best streak", Street.c.gold, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatBox("${app.cards.size}", "Words learned", Street.c.jade, Modifier.weight(1f)); StatBox("${app.slots.spins}", "Spins", Street.c.plum, Modifier.weight(1f))
        }
        // activity calendar (15 weeks)
        Column(Modifier.fillMaxWidth().card().padding(14.dp)) {
            Text("activity", fontWeight = FontWeight.Bold, color = Street.c.text)
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
            Text("levels", fontWeight = FontWeight.Bold, color = Street.c.text)
            Words.levels.forEach { l ->
                val total = Words.level(l).size; val done = app.learnedCount(l)
                Row { Text("HSK $l", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f)); Text("$done/$total", color = Street.c.secondary) }
                Box(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(5.dp)).background(Street.c.ink.copy(alpha = 0.08f))) {
                    Box(Modifier.fillMaxWidth(done / total.toFloat().coerceAtLeast(1f)).height(10.dp).background(Street.level(l)))
                }
            }
        }
        } else {
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            CloseButton { settingsOpen = false }; HSpacer(12.dp)
            Text("settings", style = street(28.sp), color = Street.c.text)
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
            if (s.sounds) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🔈", fontSize = 16.sp)
                var volume by remember { androidx.compose.runtime.mutableFloatStateOf(s.volume) }
                androidx.compose.material3.Slider(volume, { volume = it }, Modifier.weight(1f).padding(horizontal = 10.dp),
                    onValueChangeFinished = { set(app.settings.copy(volume = volume)); Sfx.volume = volume; Sfx.play(SoundId.COIN) })
                Text("🔊", fontSize = 16.sp)
            }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            ToggleRow("Haptics", "Little vibrations when you tap and answer.", s.haptics) { set(s.copy(haptics = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            ToggleRow("Listening exercises", if (s.listening && !s.canListen) "Paused for now" else null, s.listening) { set(s.copy(listening = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            ToggleRow("Speaking exercises", if (s.speaking && !s.canSpeak) "Paused for now" else "Say words out loud, checked with speech recognition.", s.speaking) { set(s.copy(speaking = it)) }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            Row(Modifier.fillMaxWidth().padding(16.dp)) {
                if (!s.canListen || !s.canSpeak) {
                    Text("▶ I can listen & speak again", color = Street.c.red, fontWeight = FontWeight.Bold,
                        modifier = Modifier.clickable { set(s.copy(noListenUntil = 0, noSpeakUntil = 0)) })
                } else {
                    val hour = System.currentTimeMillis() + 3_600_000
                    Text("🔇 Can't listen 1h", color = Street.c.red, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).clickable { set(s.copy(noListenUntil = hour)) })
                    Text("🎙️ Can't speak 1h", color = Street.c.red, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { set(s.copy(noSpeakUntil = hour)) })
                }
            }
        }
        SectionTitle("Content")
        Column(Modifier.fillMaxWidth().card()) {
            ToggleRow("Swear words 🤬", "Adds the street deck: one swear a day, Swear Sprint, rude cosmetics. Battles only match players with the same setting.", s.swears) {
                set(s.copy(swears = it))
            }
            HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
            LessonDownloads()
        }
        SectionTitle("Profile")
        Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("New words a day: ${app.profile.dailyGoal}", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f))
                Text("−", style = street(28.sp), color = Street.c.red, modifier = Modifier.clickable { app.profile = app.profile.copy(dailyGoal = (app.profile.dailyGoal - 1).coerceAtLeast(1)); app.save() }.padding(horizontal = 12.dp))
                Text("+", style = street(28.sp), color = Street.c.red, modifier = Modifier.clickable { app.profile = app.profile.copy(dailyGoal = (app.profile.dailyGoal + 1).coerceAtMost(15)); app.save() }.padding(horizontal = 12.dp))
            }
            ToggleRow("Daily reminder", "A nudge if you haven't practiced yet", app.profile.reminderOn) { on ->
                if (on && !com.asbestboi.meitian.data.Reminders.canNotify(context) && android.os.Build.VERSION.SDK_INT >= 33)
                    notifyPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                else app.setReminder(on)
            }
            if (app.profile.reminderOn) {
                Text("⏰ Remind me at %02d:%02d".format(app.profile.reminderHour, app.profile.reminderMinute),
                    fontWeight = FontWeight.Bold, color = Street.c.text,
                    modifier = Modifier.clickable {
                        android.app.TimePickerDialog(context, { _, h, m -> app.setReminder(true, h, m) },
                            app.profile.reminderHour, app.profile.reminderMinute, true).show()
                    })
            }
            ToggleRow("Battle invitations", "A notification when a friend invites you to a battle", app.profile.inviteNotify) { on ->
                app.profile = app.profile.copy(inviteNotify = on); app.save()
                if (on && !com.asbestboi.meitian.data.Reminders.canNotify(context) && android.os.Build.VERSION.SDK_INT >= 33) invitePermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            }
            Text("✅ Retake placement quiz", fontWeight = FontWeight.Bold, color = Street.c.text,
                modifier = Modifier.clickable { nav.show { OnboardingScreen(retakeOnly = true) { nav.close() } } })
            if (app.canLevelUp) {
                val level = app.currentLevel
                Text("🎓 Skip ahead: take the HSK $level test", fontWeight = FontWeight.Bold, color = Street.c.text,
                    modifier = Modifier.clickable { nav.show { LevelTest(level) { nav.close() } } })
            }
            Text(if (confirmReset) "⚠️ Tap again to delete everything (can't be undone)" else "🗑️ Reset all progress", fontWeight = FontWeight.Bold, color = Street.c.red,
                modifier = Modifier.clickable { if (confirmReset) { app.resetAll(); confirmReset = false } else confirmReset = true })
        }
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
        Switch(value, { Sfx.play(if (it) SoundId.TOGGLE_ON else SoundId.TOGGLE_OFF); onChange(it) })
    }
}

@Suppress("unused")
private val unusedHeight = Modifier.height(0.dp)

@Composable
private fun LessonDownloads() {
    val app = LocalApp.current
    val context = androidx.compose.ui.platform.LocalContext.current.applicationContext
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val st = ContentSync.stats
    var all by remember { mutableStateOf(ContentSync.allLevels(context)) }
    var confirmClear by remember { mutableStateOf(false) }
    val level = app.profile.confirmedLevel + 1
    val status = when (val x = ContentSync.status) {
        ContentSync.Status.Idle -> if (st.sentences > 0u) "Downloaded" else "Not downloaded yet"
        ContentSync.Status.Checking -> "Checking for new lessons…"
        is ContentSync.Status.Downloading -> "Downloading ${x.done + 1} of ${x.total}…"
        ContentSync.Status.Ready -> "Up to date"
        is ContentSync.Status.Failed -> x.message
    }
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("📥 Lessons", fontWeight = FontWeight.Bold, color = Street.c.text)
        Text("${st.words} words · ${st.sentences} sentences · ${st.stories} stories", fontWeight = FontWeight.SemiBold, color = Street.c.text, fontSize = 14.sp)
        Text(status, fontSize = 12.sp, color = Street.c.secondary)
    }
    HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
    ToggleRow("Download every level", "Otherwise only sentences for the HSK levels around yours (saves space).", all) {
        all = it
        ContentSync.setAllLevels(context, it)
        scope.launch { ContentSync.refresh(context, level) }
    }
    HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
    Row(Modifier.fillMaxWidth().padding(16.dp)) {
        Text("↻ Update now", fontWeight = FontWeight.Bold, color = Street.c.red,
            modifier = Modifier.weight(1f).clickable { scope.launch { ContentSync.refresh(context, level) } })
        val mb = "%.1f MB".format(ContentSync.cacheBytes(context) / 1_048_576.0)
        Text(if (confirmClear) "Tap again to delete" else "🗑️ Delete ($mb)", fontWeight = FontWeight.Bold, color = Street.c.red,
            modifier = Modifier.clickable { if (confirmClear) { ContentSync.clear(context); confirmClear = false } else confirmClear = true })
    }
    if (ContentSync.credits.isNotEmpty()) {
        HorizontalDivider(color = Street.c.ink.copy(alpha = 0.2f))
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            ContentSync.credits.forEach { Text(it, fontSize = 11.sp, color = Street.c.secondary) }
        }
    }
}
