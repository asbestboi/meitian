package com.asbestboi.meitian.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.Words
import uniffi.meitian_core.levelTestPassed
import uniffi.meitian_core.levelTestWordIds
import kotlin.math.ceil

/** HSK level-up test: 20 mixed questions on the level's words; 80% unlocks the next level's words and
 *  stories. Also used to test out of a level early ("skip ahead"). */
@Composable
fun LevelTest(level: Int, onPracticeWeak: (() -> Unit)? = null, close: () -> Unit) {
    val app = LocalApp.current
    val questions = remember(level) {
        val levelWords = Words.level(level)
        val ids = levelTestWordIds(levelWords.map { it.id }, levelWords.filter { app.cards[it.id] != null }.map { it.id },
            kotlin.random.Random.nextLong().toULong())
        val kinds = Question.mixedKinds(app.settings)
        ids.mapNotNull { Words[it] }.mapIndexed { i, w -> Question.make(w, kinds[i % kinds.size], levelWords) }
    }
    var phase by remember { mutableIntStateOf(0) } // 0 intro, 1 quiz, 2 results
    var score by remember { mutableIntStateOf(0) }
    var confetti by remember { mutableIntStateOf(0) }
    val passed = levelTestPassed(score.toUInt(), questions.size.toUInt())
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); Spacer(Modifier.weight(1f))
                Text("HSK $level test", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                Spacer(Modifier.weight(1f))
            }
            when (phase) {
                0 -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    val learned = app.learnedCount(level)
                    val total = Words.level(level).size
                    Spacer(Modifier.weight(1f))
                    Text("🎓", fontSize = 80.sp)
                    Text("hsk $level level-up", style = street(34.sp), color = Street.c.text)
                    Text("${questions.size} questions on HSK $level words. Get 80% right to unlock HSK ${level + 1} words and stories.",
                        color = Street.c.secondary, textAlign = TextAlign.Center)
                    if (learned < total) Text("You've learned $learned of $total words, so some of these will be new. Skipping ahead is allowed ✦",
                        color = Street.c.gold, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.weight(1f))
                    BigButton("start the test →", enabled = questions.isNotEmpty()) { phase = 1 }
                }
                1 -> QuizRunner(questions, onDone = { c ->
                    score = c
                    if (levelTestPassed(c.toUInt(), questions.size.toUInt())) { app.passLevelTest(level); confetti++ }
                    phase = 2
                })
                else -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Spacer(Modifier.weight(1f))
                    Text(if (passed) "🏅" else "💪", fontSize = 90.sp)
                    Text(if (passed) "升级了！" else "差一点！", style = street(44.sp), color = Street.c.text)
                    Text(if (passed) "shēngjí le · level up!" else "chà yìdiǎn · so close!", color = Street.c.secondary, fontWeight = FontWeight.Bold)
                    Text("$score / ${questions.size} right", style = street(26.sp), color = if (passed) Street.c.jade else Street.c.red)
                    Text(if (passed) "+100 XP · HSK ${level + 1} words and stories are unlocked."
                        else "You need ${ceil(questions.size * 0.8).toInt()} right. Practice your weak words and try again any time.",
                        color = Street.c.secondary, textAlign = TextAlign.Center)
                    Spacer(Modifier.weight(1f))
                    if (!passed && onPracticeWeak != null) BigButton("practice weak words ⚡", brush = Street.gold()) { close(); onPracticeWeak() }
                    BigButton("Done", onClick = close)
                }
            }
        }
        Confetti(confetti)
    }
}

/** Today: shown once every word of the current level is learned. */
@Composable
fun LevelTestCard(onPracticeWeak: () -> Unit) {
    val app = LocalApp.current
    val nav = com.asbestboi.meitian.LocalNav.current
    if (!app.levelComplete) return
    if (app.canLevelUp) {
        val level = app.currentLevel
        Row(Modifier.fillMaxWidth().block(Street.night()).clickable { nav.show { LevelTest(level, onPracticeWeak) { nav.close() } } }.padding(18.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text("🎓", fontSize = 40.sp); HSpacer(14.dp)
            Column(Modifier.weight(1f)) {
                Text("HSK $level test", style = street(20.sp), color = Color.White)
                Text("all HSK $level words learned ✦ pass to unlock HSK ${level + 1}", fontSize = 13.sp, color = Color.White.copy(alpha = 0.8f))
            }
            Text("→", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
    } else {
        Text("You've learned every word up to HSK ${app.currentLevel} 🐉 more levels arrive with new lesson packs.",
            color = Street.c.secondary, modifier = Modifier.fillMaxWidth().card().padding(16.dp))
    }
}
