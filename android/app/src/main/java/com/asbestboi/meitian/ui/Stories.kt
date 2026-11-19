package com.asbestboi.meitian.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.LocalNav
import com.asbestboi.meitian.data.ContentSync
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.Speaker
import com.asbestboi.meitian.data.Words
import com.asbestboi.meitian.data.isSwear
import kotlinx.coroutines.delay
import uniffi.meitian_core.Story
import uniffi.meitian_core.StoryImage
import uniffi.meitian_core.StoryLine
import uniffi.meitian_core.StoryQuestion
import uniffi.meitian_core.allStories
import uniffi.meitian_core.storyOfTheDay
import uniffi.meitian_core.storyWordIds

object StoryProgress {
    private fun prefs(c: Context) = c.getSharedPreferences("stories", Context.MODE_PRIVATE)
    fun done(c: Context): Set<String> = prefs(c).getStringSet("done", emptySet()) ?: emptySet()
    fun markDone(c: Context, id: String) = prefs(c).edit().putStringSet("done", done(c) + id).apply()
}

@Composable
fun StoryImageView(image: StoryImage?, height: Dp, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(height).background(Street.chrome()), contentAlignment = Alignment.Center) {
        if (image != null) {
            AsyncImage(model = image.url, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
    }
}

@Composable
private fun StoryCard(story: Story, locked: Boolean, done: Boolean, onClick: () -> Unit) {
    Column(
        Modifier.width(200.dp).card().clickable(onClick = onClick).alpha(if (locked) 0.55f else 1f),
    ) {
        Box {
            StoryImageView(story.cover, 130.dp)
            Text(story.emoji, fontSize = 24.sp, modifier = Modifier.padding(8.dp))
            if (done) Text("✅", fontSize = 20.sp, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp))
            if (locked) Text("🔒", fontSize = 30.sp, modifier = Modifier.align(Alignment.Center))
        }
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(story.title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
            Text(story.titleEn.lowercase(), fontSize = 12.sp, color = Street.c.secondary, maxLines = 1)
            Pill("HSK ${story.level}", Street.levelColor(story.level.toInt()))
        }
    }
}

/** Horizontal shelf of stories (Practice tab). */
@Composable
fun StoryShelf() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val ctx = LocalContext.current
    val stories = remember(ContentSync.generation) { allStories() }
    if (stories.isEmpty()) return
    val done = remember(ContentSync.generation, nav.content) { StoryProgress.done(ctx) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("stories ✦", style = street(22.sp), color = Street.c.text)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            stories.forEach { s ->
                StoryCard(s, locked = s.level.toInt() > app.currentLevel + 1, done = s.id in done) {
                    nav.show { StoryPlayer(s) { nav.close() } }
                }
            }
        }
    }
}

/** Story-of-the-day card for the Today screen. */
@Composable
fun StoryOfTheDayCard() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val s = remember(ContentSync.generation, app.todayKey) { storyOfTheDay(app.todayKey, app.currentLevel.toUByte()) } ?: return
    Box(Modifier.fillMaxWidth().block(Street.night()).clickable { nav.show { StoryPlayer(s) { nav.close() } } }) {
        StoryImageView(s.cover, 190.dp)
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)))))
        Column(Modifier.align(Alignment.BottomStart).padding(18.dp)) {
            Text("story of the day ✦", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.8f))
            Text("${s.emoji} ${s.title}", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
            Text(s.titleEn.lowercase(), fontSize = 14.sp, color = Color.White.copy(alpha = 0.85f))
        }
    }
}

/** Plays a story: picture, lines one at a time as bubbles (read aloud, tap words), then a question. */
@Composable
fun StoryPlayer(story: Story, close: () -> Unit) {
    val app = LocalApp.current
    val ctx = LocalContext.current
    var panel by remember { mutableIntStateOf(0) }
    var shown by remember { mutableIntStateOf(1) }
    var picked by remember { mutableStateOf<Int?>(null) }
    var correct by remember { mutableIntStateOf(0) }
    var finished by remember { mutableStateOf(false) }
    var english by remember { mutableStateOf(false) }
    var confetti by remember { mutableIntStateOf(0) }
    val p = story.panels[panel]
    val linesDone = shown >= p.lines.size
    val questionPending = linesDone && p.question != null && picked == null

    LaunchedEffect(panel, shown) {
        val line = p.lines.getOrNull(shown - 1) ?: return@LaunchedEffect
        delay(300); Speaker.say(line.zh)
    }

    Box(Modifier.fillMaxSize()) {
        if (finished) {
            StoryResults(story, correct, close)
        } else Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); HSpacer(12.dp)
                val progress = panel + if (linesDone) 1f else shown.toFloat() / p.lines.size.coerceAtLeast(1)
                LinearProgressIndicator(progress = { progress / story.panels.size }, Modifier.weight(1f), color = Street.c.pink)
                HSpacer(10.dp)
                Text(if (english) "EN ✓" else "EN", fontWeight = FontWeight.Bold, fontSize = 13.sp,
                    color = if (english) Street.c.paper else Street.c.text,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(if (english) Street.c.ink else Street.c.card)
                        .clickable { english = !english }.padding(horizontal = 12.dp, vertical = 8.dp))
            }
            AnimatedContent(panel, Modifier.weight(1f),
                transitionSpec = { (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut()) }, label = "panel") { idx ->
                val cur = story.panels[idx]
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    StoryImageView(cur.image, 240.dp, Modifier.clip(RoundedCornerShape(24.dp)))
                    cur.image?.let { img ->
                        Text("art: ${img.artist}", fontSize = 11.sp, color = Street.c.secondary,
                            modifier = Modifier.clickable { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(img.source))) } })
                    }
                    cur.lines.forEachIndexed { i, line ->
                        AnimatedVisibility(i < shown || idx != panel, enter = slideInVertically { it / 2 } + fadeIn()) { Bubble(line, english) }
                    }
                    val q = cur.question
                    if (q != null && (idx != panel || linesDone)) Question(q, picked) { i ->
                        if (picked == null) {
                            picked = i
                            if (i == q.answer.toInt()) { correct++; Sfx.play(Sfx.Sound.Correct) } else Sfx.play(Sfx.Sound.Wrong)
                        }
                    }
                }
            }
            BigButton(if (!linesDone) "continue" else if (panel + 1 < story.panels.size) "next" else "finish", enabled = !questionPending) {
                when {
                    !linesDone -> shown++
                    panel + 1 < story.panels.size -> { panel++; shown = 1; picked = null; Sfx.play(Sfx.Sound.Swoosh) }
                    else -> {
                        StoryProgress.markDone(ctx, story.id)
                        app.addXP(20 + correct * 5)
                        finished = true; confetti++
                        Sfx.play(Sfx.Sound.Win)
                    }
                }
            }
        }
        Confetti(confetti, sound = false)
    }
}

@Composable
private fun Bubble(line: StoryLine, english: Boolean) {
    val narration = line.speaker.isEmpty()
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(if (narration) Color.Transparent else Street.c.card)
            .border(1.dp, if (narration) Street.c.secondary.copy(alpha = 0.25f) else Color.Transparent, RoundedCornerShape(20.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (!narration) Text(line.speaker, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Street.c.pink)
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.weight(1f)) { TokenSentence(line.tokens, 22.sp) }
            SpeakButton(line.zh, 32.dp, Street.c.sky)
        }
        if (english) Text(line.en, fontSize = 14.sp, color = Street.c.secondary)
    }
}

@Composable
private fun Question(q: StoryQuestion, picked: Int?, onPick: (Int) -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Street.c.pink.copy(alpha = 0.08f)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(q.prompt, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = Street.c.text)
        q.options.forEachIndexed { i, text ->
            val bg = when {
                picked == null -> Street.c.card
                i == q.answer.toInt() -> Street.c.jade.copy(alpha = 0.22f)
                i == picked -> Street.c.red.copy(alpha = 0.2f)
                else -> Street.c.card
            }
            Text(text + when { picked != null && i == q.answer.toInt() -> "  ✓"; picked == i -> "  ✗"; else -> "" },
                fontWeight = FontWeight.SemiBold, color = Street.c.text,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(bg).clickable(enabled = picked == null) { onPick(i) }
                    .padding(horizontal = 16.dp, vertical = 14.dp))
        }
    }
}

@Composable
private fun StoryResults(story: Story, correct: Int, close: () -> Unit) {
    val app = LocalApp.current
    val fresh = remember { storyWordIds(story).mapNotNull { Words[it] }.filter { app.cards[it.id] == null && !it.isSwear } }
    var added by remember { mutableStateOf(false) }
    val questions = story.panels.count { it.question != null }
    Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Spacer(Modifier.weight(1f))
        StoryImageView(story.cover, 180.dp, Modifier.padding(horizontal = 20.dp).clip(RoundedCornerShape(24.dp)))
        Text("故事读完了！", fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, color = Street.c.text)
        Text("story finished · $correct/$questions questions right", color = Street.c.secondary)
        Text("+${20 + correct * 5} XP", style = street(26.sp), color = Street.c.gold)
        if (fresh.isNotEmpty()) {
            Text(if (added) "added ${fresh.size} words ✓" else "＋ add ${fresh.size} new words to review", fontWeight = FontWeight.Bold, color = Street.c.jade,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.c.jade.copy(alpha = 0.15f))
                    .clickable(enabled = !added) { app.addToReview(fresh); added = true }.padding(horizontal = 20.dp, vertical = 12.dp))
        }
        Spacer(Modifier.weight(1f))
        BigButton("Done", onClick = close)
    }
}
