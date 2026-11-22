package com.asbestboi.meitian.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Kind
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.Words
import uniffi.meitian_core.PlacementAnswer
import uniffi.meitian_core.placementLevel
import uniffi.meitian_core.placementShouldContinue

private val claims = listOf(
    Triple("🌱", "Total beginner", "I'm starting from zero"),
    Triple("🐣", "I know a few words", "你好, 谢谢, 再见…"),
    Triple("🎋", "Basic conversations", "I can order food and chat a bit"),
    Triple("🐼", "Getting comfortable", "I can talk about my day and plans"),
    Triple("🐉", "Pretty confident", "I hold real conversations"),
    Triple("🦅", "Advanced", "I read articles and watch shows"),
    Triple("👑", "Near fluent", "I just want to keep sharp"),
)

private fun placementQuestions(): List<Question> = Words.levels.flatMap { level ->
    val pool = Words.level(level)
    // common words first, so the test checks the core of each level
    pool.take(60).shuffled().take(3).mapIndexed { i, w -> Question.make(w, if (i == 1) Kind.MeaningToHanzi else Kind.HanziToMeaning, pool) }
}

/** Welcome → name → claimed level → placement quiz → result → daily goal. Also used to retake the quiz. */
@Composable
fun OnboardingScreen(retakeOnly: Boolean = false, onDone: () -> Unit = {}) {
    val app = LocalApp.current
    var step by remember { mutableIntStateOf(if (retakeOnly) 2 else 0) }
    var name by remember { mutableStateOf(app.profile.name) }
    var claimed by remember { mutableIntStateOf(app.profile.claimedLevel) }
    var confirmed by remember { mutableIntStateOf(0) }
    var questions by remember { mutableStateOf(listOf<Question>()) }
    val results = remember { mutableStateListOf<PlacementAnswer>() }
    var goal by remember { mutableIntStateOf(5) }
    var confetti by remember { mutableIntStateOf(0) }

    fun startQuiz() { questions = placementQuestions(); results.clear(); step = 3 }
    fun finishPlacement() {
        if (retakeOnly) {
            app.profile = app.profile.copy(claimedLevel = claimed, confirmedLevel = confirmed); app.save(); onDone()
        } else step = 5
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(22.dp)) {
            when (step) {
                0 -> {
                    Spacer(Modifier.weight(1f))
                    Text("每天", style = street(110.sp), color = Street.c.red, modifier = Modifier.align(Alignment.CenterHorizontally))
                    Text("měitiān", style = street(44.sp), color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally))
                    Gap(8.dp)
                    Text("A little Chinese every day.\nNew words, real friends, real sentences.", color = Street.c.secondary,
                        fontSize = 18.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.weight(1f))
                    BigButton("开始 · Let's start") { step = 1 }
                }
                1 -> {
                    CloseButton { step = 0 }
                    Gap(20.dp)
                    RubyText("你叫什么名字？", "Nǐ jiào shénme míngzi?", 32.sp, FontWeight.Bold, alwaysShow = true)
                    Text("What's your name?", color = Street.c.secondary)
                    Gap(16.dp)
                    OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), placeholder = { Text("Your name") }, singleLine = true)
                    if (name.isNotBlank()) {
                        Gap(14.dp)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("我叫$name。", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Street.c.text)
                            HSpacer(10.dp); SpeakButton("我叫$name。", 36.dp)
                        }
                        PinyinText("Wǒ jiào $name.")
                        Text("That's how you say “My name is $name.”", fontSize = 13.sp, color = Street.c.secondary)
                    }
                    Spacer(Modifier.weight(1f))
                    BigButton("Next", enabled = name.isNotBlank()) { step = 2 }
                }
                2 -> {
                    CloseButton { if (retakeOnly) onDone() else step = 1 }
                    Gap(14.dp)
                    Text("how's your chinese?", style = street(34.sp), color = Street.c.text)
                    Text("Pick what feels right. Then a quick quiz confirms it.", color = Street.c.secondary)
                    Gap(12.dp)
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        claims.forEachIndexed { i, (emoji, title, sub) ->
                            Row(
                                Modifier.fillMaxWidth().streetCard(Street.c.card, if (claimed == i) Street.c.red else Street.c.ink, shadow = 4.dp)
                                    .clickable { claimed = i }.padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(emoji, fontSize = 32.sp); HSpacer(12.dp)
                                Column(Modifier.weight(1f)) {
                                    Text(title, fontWeight = FontWeight.Bold, color = Street.c.text)
                                    Text(sub, color = Street.c.secondary, fontSize = 14.sp)
                                }
                                Text(if (claimed == i) "✅" else "⚪", fontSize = 22.sp)
                            }
                        }
                    }
                    Gap(10.dp)
                    if (claimed == 0) {
                        BigButton("Start from the beginning", brush = Street.jade()) { confirmed = 0; finishPlacement() }
                        Text("Actually, test me anyway", color = Street.c.red, fontWeight = FontWeight.Bold,
                            modifier = Modifier.align(Alignment.CenterHorizontally).clickable { startQuiz() }.padding(8.dp))
                    } else BigButton("Confirm my level") { startQuiz() }
                }
                3 -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CloseButton { step = 2 }
                        Spacer(Modifier.weight(1f))
                        val level = questions.getOrNull(results.size.coerceAtMost(questions.size - 1))?.word?.level?.toInt() ?: 1
                        Pill("Level $level check", Street.levelColor(level))
                    }
                    Gap(10.dp)
                    QuizRunner(
                        questions, allowPinyin = false, tagNew = false,
                        onAnswer = { q, right -> results += PlacementAnswer(q.word.level, right) },
                        shouldContinue = { placementShouldContinue(results.toList()) },
                        onDone = {
                            confirmed = placementLevel(results.toList()).toInt()
                            step = 4
                            if (confirmed > 0) confetti++
                        },
                    )
                }
                4 -> {
                    Spacer(Modifier.weight(1f))
                    Text(listOf("🌱", "🐣", "🎋", "🐼", "🐉", "🦅", "👑")[confirmed.coerceIn(0, 6)], fontSize = 90.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
                    Text(if (confirmed == 0) "FRESH START" else "HSK $confirmed", style = street(48.sp), color = Street.c.text,
                        modifier = Modifier.align(Alignment.CenterHorizontally))
                    Text(
                        when {
                            confirmed > claimed -> "You're better than you think! 🎉"
                            confirmed == claimed -> if (confirmed == 0) "Let's begin together" else "Confirmed! 太棒了 (tài bàng le)"
                            else -> "Let's build a solid base"
                        },
                        fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Street.c.text, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                    )
                    val top = Words.maxLevel
                    val start = minOf(confirmed + 1, top)
                    Text(
                        if (confirmed >= top) "You know every level we have. We'll keep you sharp with HSK $top words and reviews."
                        else "You'll get new words from level $start and climb from there.",
                        color = Street.c.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                    )
                    if (results.isNotEmpty()) Text("${results.count { it.right }} of ${results.size} correct", fontWeight = FontWeight.Bold,
                        color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp))
                    Spacer(Modifier.weight(1f))
                    BigButton(if (retakeOnly) "Save level" else "Sounds good") { finishPlacement() }
                    Text("Retake the quiz", color = Street.c.red, fontWeight = FontWeight.Bold,
                        modifier = Modifier.align(Alignment.CenterHorizontally).clickable { startQuiz() }.padding(8.dp))
                }
                else -> {
                    CloseButton { step = 4 }
                    Gap(14.dp)
                    Text("your daily goal", style = street(34.sp), color = Street.c.text)
                    Text("How many new words a day?", color = Street.c.secondary)
                    Gap(14.dp)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        listOf(Triple(3, "Chill", "☕"), Triple(5, "Steady", "🚶"), Triple(8, "Intense", "🚀")).forEach { (n, label, emoji) ->
                            Column(
                                Modifier.weight(1f).streetCard(Street.c.card, if (goal == n) Street.c.red else Street.c.ink, shadow = 4.dp)
                                    .clickable { goal = n }.padding(vertical = 16.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Text(emoji, fontSize = 30.sp)
                                Text("$n", style = street(30.sp), color = Street.c.text)
                                Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
                            }
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    BigButton("Let's go, $name!") {
                        app.profile = app.profile.copy(name = name.trim(), claimedLevel = claimed, confirmedLevel = confirmed,
                            dailyGoal = goal, onboarded = true)
                        app.save()
                    }
                }
            }
        }
        Confetti(confetti)
    }
}

@Suppress("unused")
private fun Modifier.outline() = this.border(1.dp, androidx.compose.ui.graphics.Color.Gray, RoundedCornerShape(4.dp))
