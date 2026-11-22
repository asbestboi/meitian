package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.ContentSync
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.Speaker
import com.asbestboi.meitian.data.levelLabel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.Exercise
import uniffi.meitian_core.ExerciseKind
import uniffi.meitian_core.Sentence
import uniffi.meitian_core.Token
import uniffi.meitian_core.lookupToken
import uniffi.meitian_core.PathNode
import uniffi.meitian_core.lessonFailed
import uniffi.meitian_core.lessonHearts
import uniffi.meitian_core.loseHeart
import uniffi.meitian_core.sentenceLesson
import uniffi.meitian_core.sentenceNodeLesson
import uniffi.meitian_core.sentencesForWord
import uniffi.meitian_core.wordOrderCorrect
import kotlin.math.roundToInt
import kotlin.math.sin

/** A sentence word by word with pinyin above each word. Tap a word to see what it means. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TokenSentence(
    tokens: List<Token>,
    size: TextUnit = 24.sp,
    center: Boolean = false,
    gap: Int? = null,
    gapFill: String? = null,
    forcePinyin: Boolean = false,
) {
    val s = LocalApp.current.settings
    val showPinyin = s.showPinyin || forcePinyin
    var peek by remember { mutableStateOf<CoreWord?>(null) }
    FlowRow(
        horizontalArrangement = if (center) Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally) else Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        tokens.forEachIndexed { i, t ->
            val isGap = gap == i
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.clickable(enabled = !isGap && t.pinyin.isNotEmpty()) {
                    val w = lookupToken(t.text)
                    if (w != null) peek = w else Speaker.say(t.text)
                },
            ) {
                if (showPinyin) {
                    val pinyinSize = (size.value * 0.42f).coerceAtLeast(11f).sp
                    if (t.isNew && !isGap) PinyinText(t.pinyin, pinyinSize, FontWeight.SemiBold)
                    else Text(if (isGap || t.pinyin.isEmpty()) " " else t.pinyin, fontSize = pinyinSize,
                        fontWeight = FontWeight.SemiBold, color = Street.c.secondary, maxLines = 1)
                }
                if (isGap) {
                    Text(gapFill ?: "＿".repeat(t.text.length.coerceAtLeast(1)), fontSize = size, fontWeight = FontWeight.SemiBold,
                        color = if (gapFill == null) Street.c.secondary else Street.c.jade,
                        modifier = Modifier.background(Street.c.gold.copy(alpha = if (gapFill == null) 0.18f else 0f), RoundedCornerShape(6.dp)).padding(horizontal = 4.dp))
                } else {
                    Text(t.text, fontSize = size, color = Street.c.text,
                        textDecoration = if (t.wordId != null && !t.isNew) TextDecoration.Underline else null,
                        modifier = if (!t.isNew) Modifier else Modifier.newWordMark().semantics { contentDescription = "new word, ${t.text}" })
                }
            }
        }
    }
    peek?.let { w -> WordPeek(w) { peek = null } }
}

/** Tap-a-word popup: characters, pinyin, meaning, audio and "add to review". */
@Composable
fun WordPeek(w: CoreWord, close: () -> Unit) {
    val app = LocalApp.current
    LaunchedEffect(w.id) { Speaker.say(w.hanzi) }
    androidx.compose.ui.window.Dialog(onDismissRequest = close) {
        Column(Modifier.fillMaxWidth().card().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(w.hanzi, fontSize = 52.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text)
                HSpacer(14.dp)
                Column(Modifier.weight(1f)) {
                    PinyinText(w.pinyin, 20.sp)
                    Text(w.meaning, color = Street.c.secondary, maxLines = 3)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                SpeakButton(w.hanzi, 48.dp)
                Spacer(Modifier.weight(1f))
                if (app.cards[w.id] == null) {
                    Text("＋ Add to review", fontWeight = FontWeight.Bold, color = Street.c.jade,
                        modifier = Modifier.clickable { app.addToReview(listOf(w)) }.padding(8.dp))
                } else {
                    Text("✓ In your reviews", fontWeight = FontWeight.Bold, color = Street.c.jade)
                }
            }
            Text(w.levelLabel, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
        }
    }
}

/** More example sentences for a word (from the downloaded sentence packs). */
@Composable
fun ExampleSentences(word: CoreWord) {
    val sentences = remember(word.id, ContentSync.generation) {
        sentencesForWord(word.id, 4u).filter { it.zh != word.example }
    }
    if (sentences.isEmpty()) return
    Column(Modifier.fillMaxWidth().card().padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("more examples", style = street(16.sp), color = Street.c.text)
        sentences.forEach { s ->
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    TokenSentence(s.tokens, 20.sp)
                    Text(s.en, fontSize = 14.sp, color = Street.c.secondary)
                }
                SpeakButton(s.zh, 34.dp, Street.c.jade)
            }
        }
    }
}

// ---------- sentence lesson ----------

private fun ExerciseKind.title() = when (this) {
    ExerciseKind.WORD_ORDER -> "Build the sentence"
    ExerciseKind.FILL_GAP -> "Fill the gap"
    ExerciseKind.LISTEN_PICK -> "What did you hear?"
    ExerciseKind.TRANSLATE_PICK -> "What does it mean?"
    ExerciseKind.PINYIN_PICK -> "Which one is it?"
}

/** Sentence exercises: build the sentence, fill the gap, listen, translate, read pinyin. From a [node] on the
 *  learning path it's a lesson with hearts and only learned words; otherwise ten exercises of practice. */
@Composable
fun SentenceSession(node: PathNode? = null, close: () -> Unit) {
    var attempt by remember { mutableIntStateOf(0) }
    key(attempt) { SentenceAttempt(node, onRetry = { attempt++ }, close) }
}

@Composable
private fun SentenceAttempt(node: PathNode?, onRetry: () -> Unit, close: () -> Unit) {
    val app = LocalApp.current
    val exercises = remember {
        if (node != null) sentenceNodeLesson(node.unit, node.number, app.todayKey, app.knownList, app.unitWordIds(node.unit.toInt()), app.settings.canListen)
        else sentenceLesson(app.currentLevel.toUByte(), app.knownList, 10u, kotlin.random.Random.nextLong().toULong(), app.settings.canListen)
    }
    // indices into exercises; with hearts, wrong answers are asked again at the end
    val queue = remember { mutableStateListOf<Int>().apply { addAll(exercises.indices) } }
    var index by remember { mutableIntStateOf(0) }
    var correct by remember { mutableIntStateOf(0) }
    var solved by remember { mutableIntStateOf(0) }
    var hearts by remember { mutableIntStateOf(lessonHearts().toInt()) }
    var failed by remember { mutableStateOf(false) }
    var gained by remember { mutableIntStateOf(0) }
    var finished by remember { mutableStateOf(false) }
    var confetti by remember { mutableIntStateOf(0) }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); HSpacer(12.dp)
                LinearProgressIndicator(progress = { (if (node != null) solved else index).toFloat() / exercises.size.coerceAtLeast(1) }, Modifier.weight(1f), color = Street.c.jade)
                if (node != null) { HSpacer(10.dp); HeartsBar(hearts) }
            }
            when {
                exercises.isEmpty() -> Text("No sentences yet. Connect to the internet once to download lessons.", color = Street.c.secondary)
                failed -> OutOfHearts(onRetry, close)
                finished -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Spacer(Modifier.weight(1f))
                    Text("$correct/${exercises.size}", style = street(90.sp), color = Street.c.text)
                    Text(if (correct * 2 >= exercises.size) "you're reading real chinese! 厉害!" else "sentences are hard. 加油!",
                        style = street(24.sp), color = Street.c.red, textAlign = TextAlign.Center)
                    Text(if (node != null && gained == 0) "replay · no XP" else "+$gained XP", fontWeight = FontWeight.Bold, color = Street.c.gold)
                    Spacer(Modifier.weight(1f))
                    BigButton("Done", onClick = close)
                }
                else -> AnimatedContent(
                    targetState = index,
                    transitionSpec = { (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut()) },
                    label = "exercise",
                ) { i ->
                    val ex = queue[i]
                    ExerciseView(exercises[ex], onResult = { right ->
                        if (right) {
                            solved++
                            if (i < exercises.size) correct++   // first try
                        } else if (node != null) {
                            hearts = loseHeart(hearts.toUInt()).toInt()
                            queue.add(ex)
                        }
                    }) {
                        if (node != null && lessonFailed(hearts.toUInt())) failed = true
                        else if (i + 1 >= queue.size) {
                            if (node != null) gained = app.finishPathSentences(node.number.toInt())
                            else {
                                gained = correct * 4
                                app.addXP(gained)
                                app.count(com.asbestboi.meitian.data.AppState.Counter.Sentences)
                            }
                            finished = true
                            if (correct > 0) { confetti++; Sfx.play(SoundId.WIN) }
                        } else index = i + 1
                    }
                }
            }
        }
        Confetti(confetti, sound = false)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ExerciseView(ex: Exercise, onResult: (Boolean) -> Unit, onNext: () -> Unit) {
    val s = ex.sentence
    val app = LocalApp.current
    val newTexts = remember(ex) { s.tokens.filter { it.isNew }.map { it.text }.toSet() }
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Int?>(null) }
    var result by remember { mutableStateOf<Boolean?>(null) }
    val built = remember { mutableStateListOf<Int>() }
    val shake = remember { Animatable(0f) }

    fun finish(right: Boolean) {
        result = right
        onResult(right)
        if (right) {
            Sfx.play(SoundId.CORRECT)
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            if (ex.kind != ExerciseKind.LISTEN_PICK) Speaker.say(s.zh)
        } else {
            Sfx.play(SoundId.WRONG)
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            scope.launch { shake.snapTo(0f); shake.animateTo(1f, androidx.compose.animation.core.tween(400)) }
        }
    }

    LaunchedEffect(ex) {
        app.markSeen(s.tokens.newIds)
        if (ex.kind == ExerciseKind.LISTEN_PICK) { delay(400); Speaker.say(s.zh) }
    }

    val shakeX = (sin(shake.value * Math.PI * 4) * 10 * (1 - shake.value)).roundToInt()

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(ex.kind.title().lowercase(), style = street(26.sp), color = Street.c.text)
        Column(Modifier.fillMaxWidth().heightIn(min = 110.dp).card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when (ex.kind) {
                ExerciseKind.WORD_ORDER -> {
                    Text("“${s.en}”", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text)
                    SpeakButton(s.zh, 40.dp, Street.c.sky)
                }
                ExerciseKind.FILL_GAP -> {
                    TokenSentence(s.tokens, 26.sp, gap = ex.gap.toInt(), gapFill = if (result == null) null else ex.options[ex.answer.toInt()])
                    Text(s.en, color = Street.c.secondary)
                }
                ExerciseKind.LISTEN_PICK -> Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SpeakButton(s.zh, 84.dp, Street.c.sky)
                    Text("🐢 Slower", fontWeight = FontWeight.Bold, color = Street.c.sky, modifier = Modifier.clickable { Speaker.say(s.zh, true) })
                    if (result != null) TokenSentence(s.tokens, 20.sp, center = true)
                }
                ExerciseKind.TRANSLATE_PICK -> Row(verticalAlignment = Alignment.Top) {
                    Box(Modifier.weight(1f)) { TokenSentence(s.tokens, 28.sp) }
                    SpeakButton(s.zh, 38.dp, Street.c.sky)
                }
                ExerciseKind.PINYIN_PICK -> {
                    PinyinText(s.pinyin, 22.sp)
                    if (result != null) Text(s.en, color = Street.c.secondary)
                }
            }
        }

        if (ex.kind == ExerciseKind.WORD_ORDER) {
            // answer line
            FlowRow(
                Modifier.fillMaxWidth().heightIn(min = 56.dp).offset { IntOffset(shakeX, 0) },
                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                built.forEach { i -> Tile(ex.tiles[i], isNew = ex.tiles[i] in newTexts) { if (result == null) built.remove(i) } }
            }
            Box(Modifier.fillMaxWidth().padding(vertical = 2.dp).background(Street.c.secondary.copy(alpha = 0.3f)).heightIn(min = 1.dp, max = 1.dp))
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ex.tiles.forEachIndexed { i, t ->
                    Tile(t, used = i in built, isNew = t in newTexts) {
                        if (result == null && i !in built) { Speaker.say(t); built.add(i) }
                    }
                }
            }
        } else {
            val hanzi = ex.kind == ExerciseKind.FILL_GAP || ex.kind == ExerciseKind.PINYIN_PICK
            Column(Modifier.offset { IntOffset(shakeX, 0) }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ex.options.forEachIndexed { i, text ->
                    val bg = when {
                        result == null -> Street.c.card
                        i == ex.answer.toInt() -> Street.c.jade.copy(alpha = 0.25f)
                        i == picked -> Street.c.red.copy(alpha = 0.22f)
                        else -> Street.c.card
                    }
                    Text(text, fontSize = if (hanzi) 22.sp else 16.sp, fontWeight = if (hanzi) FontWeight.Medium else FontWeight.SemiBold, color = Street.c.text,
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(bg)
                            .border(if (picked == i) 2.dp else 1.dp, if (picked == i) Street.c.ink else Street.c.secondary.copy(alpha = 0.25f), RoundedCornerShape(14.dp))
                            .clickable(enabled = result == null) { picked = i; finish(i == ex.answer.toInt()) }
                            .padding(horizontal = 16.dp, vertical = 14.dp))
                }
            }
        }

        val r = result
        if (r != null) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (r) "✅ nice! 对了" else "❌ not quite", style = street(22.sp), color = if (r) Street.c.jade else Street.c.red)
                if (!r || ex.kind == ExerciseKind.WORD_ORDER) {
                    TokenSentence(s.tokens, 20.sp, forcePinyin = true)
                    Text(s.en, color = Street.c.secondary)
                }
                BigButton("Continue", brush = if (r) Street.jade() else Street.warm()) { onNext() }
            }
        } else if (ex.kind == ExerciseKind.WORD_ORDER) {
            BigButton("Check", brush = Street.jade(), enabled = built.size == ex.tiles.size) {
                finish(wordOrderCorrect(s, built.map { ex.tiles[it] }))
            }
        }
    }
}

@Composable
private fun Tile(text: String, used: Boolean = false, isNew: Boolean = false, onClick: () -> Unit) {
    Text(
        text, fontSize = 22.sp, color = if (used) Color.Transparent else Street.c.text,
        modifier = Modifier.clip(RoundedCornerShape(12.dp))
            .background(if (used) Street.c.secondary.copy(alpha = 0.12f) else Street.c.card)
            .border(1.dp, if (used) Color.Transparent else Street.c.secondary.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
            .clickable(enabled = !used, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp)
            .then(if (isNew && !used) Modifier.newWordMark().semantics { contentDescription = "new word, $text" } else Modifier),
    )
}

@Suppress("unused")
private fun Sentence.wordCount() = tokens.count { it.pinyin.isNotEmpty() }
