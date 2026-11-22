package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.blur
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
import kotlinx.coroutines.launch
import uniffi.meitian_core.Story
import uniffi.meitian_core.StoryImage
import uniffi.meitian_core.StoryLine
import uniffi.meitian_core.StoryQuestion
import uniffi.meitian_core.nextStory
import uniffi.meitian_core.rereadStory
import uniffi.meitian_core.shuffleStoryReplies
import com.asbestboi.meitian.data.AppState
import uniffi.meitian_core.shelfStories
import uniffi.meitian_core.storyAvailability
import uniffi.meitian_core.storyById
import uniffi.meitian_core.TranslationCost
import uniffi.meitian_core.lessonFailed
import uniffi.meitian_core.lessonHearts
import uniffi.meitian_core.loseHeart
import uniffi.meitian_core.storyUnlocked
import uniffi.meitian_core.storyXp
import uniffi.meitian_core.translationCost
import uniffi.meitian_core.storyImageUrls
import uniffi.meitian_core.storyOfTheDay

/** Reading history (ordered, oldest first) and the current "next story" surprise for each kind. */
object StoryProgress {
    private fun prefs(c: Context) = c.getSharedPreferences("stories", Context.MODE_PRIVATE)

    fun read(c: Context): List<String> {
        val p = prefs(c)
        if (!p.contains("read")) {
            // migrate the old unordered set
            val old = p.getStringSet("done", emptySet()) ?: emptySet()
            p.edit().putString("read", old.joinToString(",")).apply()
        }
        return p.getString("read", "")!!.split(",").filter { it.isNotEmpty() }
    }

    fun isRead(c: Context, id: String) = id in read(c)

    fun markRead(c: Context, id: String) {
        val r = read(c)
        if (id !in r) prefs(c).edit().putString("read", (r + id).joinToString(",")).apply()
    }

    fun done(c: Context): Set<String> = read(c).toSet()

    /** Forget everything read and the waiting surprises (reset all progress). */
    fun reset(c: Context) = prefs(c).edit().clear().apply()

    /**
     * The surprise waiting for this learner, picked to fit the lesson they're on. It stays the same until it's read
     * or another lesson is finished, then a new unread one is picked. Only unlocked stories.
     */
    fun next(c: Context, chat: Boolean, app: AppState, unit: Int? = null): Story? {
        val key = if (chat) "nextChat" else "nextStory"
        val readIds = read(c)
        val known = app.knownList
        val p = prefs(c)
        p.getString(key, null)?.let { id ->
            val s = storyById(id, known)
            if (s != null && id !in readIds && p.getInt(key + "At", -1) == known.size && (s.style == "chat") == chat &&
                (s.date.isEmpty() || s.date <= app.todayKey) && storyUnlocked(s, known)) return s
        }
        val s = nextStory(chat, app.todayKey, readIds, known, app.unitWordIds(unit), app.upcomingIds, kotlin.random.Random.nextLong().toULong())
        p.edit().apply { if (s == null) remove(key) else putString(key, s.id).putInt(key + "At", known.size) }.apply()
        return s
    }
}

/** What the story stop of a unit plays: something unread that fits the unit (odd units a picture story, even units a
 *  chat, the other kind if there's none), else the story read longest ago. Null when nothing is unlocked. */
fun pathStory(c: Context, app: AppState, unit: Int): Story? {
    val chat = unit % 2 == 0
    return StoryProgress.next(c, chat, app, unit) ?: StoryProgress.next(c, !chat, app, unit)
        ?: rereadStory(app.todayKey, StoryProgress.read(c), app.knownList)
}

/** Story picture. Panels show the whole image (fit) over a blurred filled copy; cards fill and crop. */
@Composable
fun StoryImageView(image: StoryImage?, height: Dp, modifier: Modifier = Modifier, fill: Boolean = false, onClick: (() -> Unit)? = null) {
    Box(
        modifier.fillMaxWidth().height(height).background(Street.chrome()).clipToBounds()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        if (image != null) {
            if (fill) {
                AsyncImage(model = image.url, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            } else {
                AsyncImage(model = image.url, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().blur(24.dp).alpha(0.7f))
                AsyncImage(model = image.url, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            }
        }
        if (onClick != null) Text("⤢", fontSize = 16.sp, color = Color.White,
            modifier = Modifier.align(Alignment.BottomEnd).padding(10.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 8.dp, vertical = 2.dp))
    }
}

/** Full-screen picture: pinch / double-tap to zoom, drag to pan, tap ✕ or back to close. */
@Composable
fun FullScreenImage(image: StoryImage, close: () -> Unit) {
    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    androidx.compose.ui.window.Dialog(onDismissRequest = close, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            AsyncImage(
                model = image.url, contentDescription = null, contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize()
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(1f, 5f)
                            offset = if (scale > 1f) offset + pan else androidx.compose.ui.geometry.Offset.Zero
                        }
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(onDoubleTap = { if (scale > 1f) { scale = 1f; offset = androidx.compose.ui.geometry.Offset.Zero } else scale = 2.5f })
                    }
                    .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y },
            )
            Text("✕", fontSize = 20.sp, color = Color.White, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(20.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.18f))
                    .clickable(onClick = close).padding(horizontal = 14.dp, vertical = 8.dp))
            Text("art: ${image.artist}", fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f), modifier = Modifier.align(Alignment.BottomCenter).padding(24.dp))
        }
    }
}

@Composable
private fun StoryCard(story: Story, done: Boolean, onClick: () -> Unit = {}) {
    Column(
        Modifier.width(200.dp).card().clickable(onClick = onClick),
    ) {
        Box {
            StoryImageView(story.cover, 130.dp, fill = true)
            Text(story.emoji, fontSize = 24.sp, modifier = Modifier.padding(8.dp))
            if (done) Text("✅", fontSize = 20.sp, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp))
            if (story.style == "chat" || story.date.isNotEmpty()) Text(if (story.style == "chat") "💬 chat" else "daily",
                fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.align(Alignment.BottomStart).padding(8.dp).clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(story.title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
            Text(story.titleEn.lowercase(), fontSize = 12.sp, color = Street.c.secondary, maxLines = 1)
            Pill("HSK ${story.level}", Street.levelColor(story.level.toInt()))
        }
    }
}

private fun learnMore(missing: Int) = "learn $missing more word${if (missing == 1) "" else "s"} to unlock"

/** Practice tab: a mystery "next story" (no cover, no title — a surprise) and the history of stories already read,
 *  which can be revisited (no XP the second time). Nothing of a locked story is shown. */
@Composable
fun StoryHub(chats: Boolean = false) {
    val app = LocalApp.current
    val nav = LocalNav.current
    val ctx = LocalContext.current
    // recomputed when content changes, the day changes, or a story screen closes
    val key = listOf(ContentSync.generation, app.todayKey, nav.content == null, app.known.size)
    val shelf = remember(key, chats) { shelfStories(app.todayKey, app.knownList).filter { (it.story.style == "chat") == chats } }
    if (shelf.isEmpty()) return
    val history = remember(key, chats) { val byId = shelf.associateBy { it.story.id }; StoryProgress.read(ctx).reversed().mapNotNull { byId[it]?.story } }
    val fits = remember(key, chats) { storyAvailability(chats, app.todayKey, app.knownList) }
    val readIds = history.map { it.id }.toSet()
    val locked = shelf.filter { !it.unlocked && it.story.id !in readIds }
    val next = remember(key, chats) { StoryProgress.next(ctx, chats, app) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (chats) "chats 💬" else "stories ✦", style = street(22.sp), color = Street.c.text, modifier = Modifier.weight(1f))
            Text("${shelf.count { it.unlocked && it.story.id in readIds }} / ${fits.unlocked} read", fontSize = 12.sp, color = Street.c.secondary, fontWeight = FontWeight.SemiBold)
        }
        if (next != null) {
            Row(Modifier.fillMaxWidth().block(Street.night()).clickable { prefetchStory(ctx, next); nav.show { StoryPlayer(next) { nav.close() } } }.padding(18.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(if (chats) "💬" else "📖", fontSize = 40.sp, modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(Color.White.copy(alpha = 0.1f)).padding(12.dp))
                HSpacer(14.dp)
                Column(Modifier.weight(1f)) {
                    Text(if (chats) "a new message" else "your next story", style = street(20.sp), color = Color.White)
                    Text("HSK ${next.level} · it's a surprise ✦", fontSize = 13.sp, color = Color.White.copy(alpha = 0.75f))
                }
                Text("→", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.Black,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Color(0xFFC6FF3D)).padding(horizontal = 14.dp, vertical = 8.dp))
            }
        } else {
            val soonest = locked.firstOrNull()?.missingWords?.toInt()
            Text(if (soonest != null) "${learnMore(soonest)} the next ${if (chats) "chat" else "story"} ✦"
                else if (chats) "You've read every chat ✦ new ones arrive soon." else "You've read every story ✦ new ones arrive soon.",
                color = Street.c.secondary, modifier = Modifier.fillMaxWidth().card().padding(16.dp))
        }
        if (history.isNotEmpty()) {
            Text("history", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(history, key = { it.id }) { s ->
                    StoryCard(s, done = true) { prefetchStory(ctx, s); nav.show { StoryPlayer(s) { nav.close() } } }
                }
            }
        }
    }
}

/** Today: the day's dated story as a surprise card (no cover until it's read). */
@Composable
fun StoryOfTheDayCard() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val ctx = LocalContext.current
    val s = remember(ContentSync.generation, app.todayKey, app.known.size) { storyOfTheDay(app.todayKey, app.knownList) } ?: return
    if (s.date != app.todayKey) return
    val read = remember(nav.content == null) { StoryProgress.isRead(ctx, s.id) }
    Row(Modifier.fillMaxWidth().block(Street.pink()).clickable { prefetchStory(ctx, s); nav.show { StoryPlayer(s) { nav.close() } } }.padding(18.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(if (read) "✅" else if (s.style == "chat") "💬" else "🎁", fontSize = 38.sp,
            modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(Color.White.copy(alpha = 0.12f)).padding(12.dp))
        HSpacer(14.dp)
        Column {
            Text("today's story ✦", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.85f))
            Text(if (read) s.title else "open it to find out", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
            Text(if (read) "read ✓ · tap to read again" else "a new one every day", fontSize = 12.sp, color = Color.White.copy(alpha = 0.8f))
        }
    }
}

/** Which lines of a story were translated. One peek is free; the next one costs the story's XP (the rule is in the core).
 *  [free]: a replay, which pays no XP anyway. */
private class Translations(private val free: Boolean) {
    /** The next tap on a line or reply shows its English. */
    var armed by mutableStateOf(false)
    val shown = mutableStateListOf<String>()
    val cost get() = if (free) TranslationCost.NOTHING else translationCost(shown.size.toUInt())
    fun reveal(key: String) { if (key !in shown) shown.add(key); armed = false }
}

/** Wraps a line: while the EN button is armed, a tap anywhere on it shows its English. */
@Composable
private fun Translatable(key: String, tr: Translations, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val armed = tr.armed && key !in tr.shown
    Box(if (armed) modifier.border(2.dp, Street.c.sky, RoundedCornerShape(18.dp)) else modifier) {
        content()
        if (armed) Box(Modifier.matchParentSize().clip(RoundedCornerShape(18.dp)).clickable(onClickLabel = "Show translation") {
            Sfx.play(SoundId.TICK); tr.reveal(key)
        })
    }
}

/** Plays a story: picture, lines one at a time as bubbles (read aloud, tap words), then a question. Wrong answers
 *  cost hearts; [onFinished] gets the number of lines that were translated. */
@Composable
fun StoryPlayer(original: Story, onFinished: (Int) -> Unit = {}, close: () -> Unit) {
    val ctx = LocalContext.current
    var attempt by remember { mutableIntStateOf(0) }
    val revisit = remember { StoryProgress.isRead(ctx, original.id) }   // read before: no XP this time
    // peeks stay used when the story starts over
    val tr = remember { Translations(free = revisit) }
    LaunchedEffect(original.id) { prefetchStory(ctx, original) }
    key(attempt) { StoryAttempt(original, revisit, tr, onFinished, onRetry = { attempt++ }, close) }
}

@Composable
private fun StoryAttempt(original: Story, revisit: Boolean, tr: Translations, onFinished: (Int) -> Unit, onRetry: () -> Unit, close: () -> Unit) {
    // reply choices are reshuffled every time a story opens (remembered, so recomposition doesn't reshuffle)
    val story = remember(original.id) { shuffleStoryReplies(original, kotlin.random.Random.nextLong().toULong()) }
    val app = LocalApp.current
    val ctx = LocalContext.current
    var panel by remember { mutableIntStateOf(0) }
    var shown by remember { mutableIntStateOf(1) }
    var picked by remember { mutableStateOf<Int?>(null) }
    var correct by remember { mutableIntStateOf(0) }
    var finished by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var hearts by remember { mutableIntStateOf(lessonHearts().toInt()) }
    // panels whose question was answered wrong: asked again after the last panel
    val again = remember { mutableStateListOf<Int>() }
    var retrying by remember { mutableStateOf(false) }
    var asks by remember { mutableIntStateOf(0) }
    var askCost by remember { mutableStateOf(false) }
    var confetti by remember { mutableIntStateOf(0) }
    var zoomed by remember { mutableStateOf<StoryImage?>(null) }
    var typing by remember { mutableStateOf(false) }
    // chat stories: messages added by your replies (+ reactions) per panel, and which pictures were revealed
    val sent = remember { androidx.compose.runtime.mutableStateMapOf<Int, List<StoryLine>>() }
    val triedWrong = remember { mutableStateListOf<Int>() }
    val replyDone = remember { mutableStateListOf<Int>() }
    val revealed = remember { mutableStateListOf<String>() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val isChat = story.style == "chat"
    val newWords = remember { story.panels.flatMap { p -> p.lines.flatMap { it.tokens.newIds } + p.reply.flatMap { o -> o.tokens.newIds + (o.reaction?.tokens?.newIds ?: emptyList()) } }.distinct() }
    val p = story.panels[panel]
    val linesDone = shown >= p.lines.size
    val dead = lessonFailed(hearts.toUInt())
    val replyPending = linesDone && p.reply.isNotEmpty() && panel !in replyDone
    val questionPending = replyPending || (linesDone && p.question != null && picked == null)

    LaunchedEffect(panel, shown) {
        val line = p.lines.getOrNull(shown - 1) ?: return@LaunchedEffect
        app.markSeen(line.tokens.newIds)
        delay(300); Speaker.say(line.zh)
    }
    LaunchedEffect(replyPending) { if (replyPending) app.markSeen(p.reply.flatMap { it.tokens.newIds }) }

    fun answer(q: StoryQuestion, i: Int) {
        if (picked != null) return
        picked = i
        if (i == q.answer.toInt()) {
            if (!retrying) correct++
            Sfx.play(SoundId.CORRECT)
        } else {
            Sfx.play(SoundId.WRONG)
            hearts = loseHeart(hearts.toUInt()).toInt()
            again.add(panel)
        }
    }

    fun sendReply(i: Int) {
        val option = p.reply[i]
        val pi = panel
        sent[pi] = (sent[pi] ?: emptyList()) + StoryLine(story.me, null, option.zh, option.pinyin, option.en, option.tokens)
        Sfx.play(SoundId.SWOOSH); Speaker.say(option.zh)
        if (option.correct) { if (triedWrong.isEmpty()) correct++ }
        else { triedWrong.add(i); hearts = loseHeart(hearts.toUInt()).toInt() }
        scope.launch {
            option.reaction?.let { r ->
                typing = true; delay(900); typing = false
                sent[pi] = (sent[pi] ?: emptyList()) + r
                app.markSeen(r.tokens.newIds)
                Sfx.play(if (option.correct) SoundId.CORRECT else SoundId.WRONG)
            }
            if (option.correct) { replyDone.add(pi); triedWrong.clear() }
        }
    }

    fun finish() {
        if (!revisit) {
            StoryProgress.markRead(ctx, story.id)
            app.addXP(storyXp((20 + correct * 5).toUInt(), tr.shown.size.toUInt()).toInt())
            app.count(AppState.Counter.Story)
        }
        app.markSeen(newWords, ding = false)
        onFinished(tr.shown.size)
        finished = true; confetti++
        Sfx.play(SoundId.WIN)
    }

    /** After the last panel: wrong questions come back until they're right. */
    fun nextRetry() {
        if (again.isEmpty()) return finish()
        panel = again.removeAt(0)
        shown = story.panels[panel].lines.size
        picked = null
        retrying = true
        asks++
    }

    Box(Modifier.fillMaxSize()) {
        if (failed) OutOfHearts(onRetry, close)
        else if (finished) {
            StoryResults(story, correct, revisit, tr.shown.size, newWords, close)
        } else Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); HSpacer(12.dp)
                val progress = if (retrying) story.panels.size.toFloat() else panel + if (linesDone) 1f else shown.toFloat() / p.lines.size.coerceAtLeast(1)
                LinearProgressIndicator(progress = { progress / story.panels.size }, Modifier.weight(1f), color = Street.c.pink)
                HSpacer(10.dp)
                HeartsBar(hearts)
                HSpacer(10.dp)
                val cost = tr.cost
                val spent = cost != TranslationCost.FREE && !revisit
                Text(when { tr.armed -> "EN ✓"; spent -> "EN used"; else -> "EN" }, fontWeight = FontWeight.Bold, fontSize = 13.sp,
                    color = if (tr.armed) Street.c.paper else if (spent) Street.c.secondary else Street.c.text,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(if (tr.armed) Street.c.ink else Street.c.card).alpha(if (spent && !tr.armed) 0.55f else 1f)
                        .clickable(onClickLabel = if (cost == TranslationCost.XP) "Show another translation, costs this story's XP" else "Translate one line") {
                            if (tr.armed) tr.armed = false
                            else if (cost == TranslationCost.XP) askCost = true
                            else tr.armed = true
                        }.padding(horizontal = 12.dp, vertical = 8.dp))
            }
            AnimatedVisibility(tr.armed) {
                Text("tap a line or a reply to see its English", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Street.c.sky,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
            val q = p.question
            if (retrying && q != null) Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("one more time 再来一次", style = street(22.sp), color = Street.c.text)
                p.lines.forEachIndexed { i, line -> Bubble("$panel-$i", line, tr) }
                key(asks) { Question(q, picked) { i -> answer(q, i) } }
            } else if (isChat) Box(Modifier.weight(1f)) {
                ChatThread(story, panel, shown, sent, typing, tr, revealed, onImage = { zoomed = it })
                if (q != null && linesDone && !replyPending) Box(Modifier.align(Alignment.BottomCenter)) {
                    Question(q, picked) { i -> answer(q, i) }
                }
            } else AnimatedContent(panel, Modifier.weight(1f),
                transitionSpec = { (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut()) }, label = "panel") { idx ->
                val cur = story.panels[idx]
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    StoryImageView(cur.image, 280.dp, Modifier.clip(RoundedCornerShape(24.dp)), onClick = cur.image?.let { img -> { zoomed = img } })
                    cur.image?.let { img ->
                        Text("art: ${img.artist}", fontSize = 11.sp, color = Street.c.secondary,
                            modifier = Modifier.clickable { runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(img.source))) } })
                    }
                    cur.lines.forEachIndexed { i, line ->
                        AnimatedVisibility(i < shown || idx != panel, enter = slideInVertically { it / 2 } + fadeIn()) { Bubble("$idx-$i", line, tr) }
                    }
                    val cq = cur.question
                    if (cq != null && (idx != panel || linesDone)) Question(cq, picked) { i -> answer(cq, i) }
                }
            }
            if (dead && (picked != null || !typing)) BigButton("continue") { failed = true }
            else if (replyPending) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // choose what you send; a reply that doesn't fit gets a reaction and you try again
                Text("your reply", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
                p.reply.forEachIndexed { i, option ->
                    val tried = i in triedWrong
                    val key = "$panel-r-${option.zh}"
                    Translatable(key, tr, Modifier.fillMaxWidth()) {
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                            .background(if (tried) Street.c.red.copy(alpha = 0.12f) else Street.c.sky.copy(alpha = 0.14f))
                            .clickable(enabled = !tried && !typing && !dead) { sendReply(i) }
                            .semantics { contentDescription = option.tokens.spoken() }
                            .alpha(if (tried) 0.5f else 1f).padding(horizontal = 14.dp, vertical = 10.dp)) {
                            Text(markedText(option.tokens), fontSize = 18.sp, color = Street.c.text, inlineContent = remember(option.zh) { WeChat.inline(option.zh, 18.sp) },
                                textDecoration = if (tried) androidx.compose.ui.text.style.TextDecoration.LineThrough else null)
                            Text(option.pinyin, fontSize = 12.sp, color = Street.c.secondary)
                            if (key in tr.shown) ChatText(option.en, 12.sp, Street.c.secondary)
                        }
                    }
                }
            } else BigButton(if (!linesDone) "continue" else if (!retrying && panel + 1 < story.panels.size) "next" else if (again.isNotEmpty()) "continue" else "finish", enabled = !questionPending) {
                when {
                    !linesDone && isChat -> if (!typing) scope.launch {
                        // "…" first, like a real chat
                        typing = true; delay(650); typing = false; shown++; Sfx.play(SoundId.TICK)
                    }
                    !linesDone -> shown++
                    !retrying && panel + 1 < story.panels.size -> { panel++; shown = 1; picked = null; Sfx.play(SoundId.SWOOSH) }
                    else -> nextRetry()
                }
            }
        }
        Confetti(confetti, sound = false)
        zoomed?.let { FullScreenImage(it) { zoomed = null } }
        if (askCost) ConfirmTranslation(onYes = { askCost = false; tr.armed = true }) { askCost = false }
    }
}

/** Before a second translation. */
@Composable
private fun ConfirmTranslation(onYes: () -> Unit, onNo: () -> Unit) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onNo) {
        Column(Modifier.fillMaxWidth().card().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Show translation?", style = street(22.sp), color = Street.c.text)
            Text("You'll get no XP for this story. Tapping a single word is always free.", color = Street.c.secondary)
            BigButton("Keep reading", onClick = onNo)
            Text("Show it, no XP", fontWeight = FontWeight.Bold, color = Street.c.red, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clickable(onClick = onYes).padding(10.dp))
        }
    }
}

@Composable
private fun Bubble(key: String, line: StoryLine, tr: Translations) = Translatable(key, tr) {
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
        if (key in tr.shown) ChatText(line.en, 14.sp, Street.c.secondary)
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
private fun StoryResults(story: Story, correct: Int, revisit: Boolean, translations: Int, newWords: List<String>, close: () -> Unit) {
    val app = LocalApp.current
    val recap = remember { newWords.mapNotNull { Words[it] } }
    val fresh = remember { recap.filter { app.cards[it.id] == null } }
    var added by remember { mutableStateOf(false) }
    val questions = story.panels.count { it.question != null } + story.panels.count { it.reply.isNotEmpty() }
    val gained = storyXp((20 + correct * 5).toUInt(), translations.toUInt())
    Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Spacer(Modifier.height(20.dp))
            StoryImageView(story.cover, 180.dp, Modifier.padding(horizontal = 20.dp).clip(RoundedCornerShape(24.dp)), fill = true)
            Text("故事读完了！", fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, color = Street.c.text)
            Text("story finished · $correct/$questions questions right", color = Street.c.secondary)
            Text(if (revisit) "replay · no XP" else if (gained == 0u) "translated · no XP" else "+$gained XP", style = street(26.sp),
                color = if (revisit || gained == 0u) Street.c.secondary else Street.c.gold)
            if (recap.isNotEmpty()) NewWordsRecap(recap)
            if (fresh.isNotEmpty()) {
                Text(if (added) "added ${fresh.size} words ✓" else "＋ add ${fresh.size} new words to review", fontWeight = FontWeight.Bold, color = Street.c.jade,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.c.jade.copy(alpha = 0.15f))
                        .clickable(enabled = !added) { app.addToReview(fresh); added = true }.padding(horizontal = 20.dp, vertical = 12.dp))
            }
        }
        BigButton("Done", onClick = close)
    }
}

/** Starts downloading a story's pictures (into Coil's cache) as soon as it's opened. */
fun prefetchStory(ctx: android.content.Context, story: Story) {
    val loader = coil.Coil.imageLoader(ctx)
    storyImageUrls(story).forEach { url -> loader.enqueue(coil.request.ImageRequest.Builder(ctx).data(url).build()) }
}

/** An SMS thread: earlier panels stay visible, my messages on the right, pictures inside bubbles. */
@Composable
private fun ChatThread(story: Story, panel: Int, shown: Int, sent: Map<Int, List<StoryLine>>, typing: Boolean, tr: Translations,
                       revealed: MutableList<String>, onImage: (StoryImage) -> Unit) {
    val items = buildList {
        for (pi in 0..panel) {
            val lines = story.panels[pi].lines
            val n = if (pi < panel) lines.size else minOf(shown, lines.size)
            for (i in 0 until n) add("$pi-$i" to lines[i])
            sent[pi]?.forEachIndexed { j, l -> add("$pi-s$j" to l) }
        }
    }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(items.size, typing) { listState.animateScrollToItem((items.size + if (typing) 1 else 0 + 1).coerceAtLeast(1) - 1) }
    androidx.compose.foundation.lazy.LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 200.dp)) {
        items(items.size, key = { items[it].first }) { idx ->
            ChatBubble(items[idx].first, items[idx].second, story.me, tr, revealed, onImage)
        }
        if (typing) item(key = "typing") {
            Text("•••", fontSize = 18.sp, color = Street.c.secondary,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.c.card).padding(horizontal = 14.dp, vertical = 8.dp))
        }
        // room so the question card doesn't cover the last message
        item(key = "pad") { Spacer(Modifier.height(1.dp)) }
    }
}

@Composable
private fun ChatBubble(key: String, line: StoryLine, me: String, tr: Translations, revealed: MutableList<String>, onImage: (StoryImage) -> Unit) {
    if (line.speaker.isEmpty()) {
        Translatable(key, tr, Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                TokenSentence(line.tokens, 13.sp, center = true)
                if (key in tr.shown) ChatText(line.en, 12.sp, Street.c.secondary, FontWeight.SemiBold)
            }
        }
        return
    }
    val mine = line.speaker == me
    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        Column(Modifier.fillMaxWidth(0.8f), horizontalAlignment = if (mine) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (!mine) Text(line.speaker, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.pink, modifier = Modifier.padding(start = 6.dp))
            line.image?.let { img ->
                // hidden until tapped: the surprise
                val visible = img.url in revealed
                Box(Modifier.width(230.dp).clip(RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                    StoryImageView(img, 170.dp, if (visible) Modifier else Modifier.blur(22.dp), fill = true,
                        onClick = { if (visible) onImage(img) else { revealed.add(img.url); Sfx.play(SoundId.COIN) } })
                    if (!visible) Text("👀 tap to see", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
            if (line.zh.isNotEmpty()) {
                val shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = if (mine) 18.dp else 4.dp, bottomEnd = if (mine) 4.dp else 18.dp)
                Translatable(key, tr) { Column(Modifier.clip(shape).background(if (mine) Street.c.sky.copy(alpha = 0.2f) else Street.c.card).padding(horizontal = 12.dp, vertical = 9.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Box(Modifier.weight(1f, fill = false)) { TokenSentence(line.tokens, 20.sp) }
                        HSpacer(6.dp)
                        SpeakButton(line.zh, 28.dp, Street.c.sky)
                    }
                    if (key in tr.shown) ChatText(line.en, 12.sp, Street.c.secondary)
                } }
            }
        }
    }
}
