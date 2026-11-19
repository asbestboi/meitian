package com.asbestboi.meitian.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Kind
import com.asbestboi.meitian.data.PlayerCard
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.Speaker
import com.asbestboi.meitian.data.SpeechListener
import com.asbestboi.meitian.data.levelLabel
import com.asbestboi.meitian.data.lvl
import com.asbestboi.meitian.data.shortMeaning
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.pinyinSyllables
import uniffi.meitian_core.pinyinTone
import uniffi.meitian_core.rubyUnits
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

// ---------- pinyin ----------

fun toneColor(tone: Int): Color = when (tone) {
    1 -> Color(0xFFEB4245); 2 -> Color(0xFFF5941A); 3 -> Color(0xFF21A86B); 4 -> Color(0xFF4078F5); else -> Color(0xFF8A867E)
}

/** Pinyin with each syllable colored by tone. */
@Composable
fun PinyinText(pinyin: String, size: TextUnit = 15.sp, weight: FontWeight = FontWeight.Bold) {
    val tones = LocalApp.current.settings.toneColors
    val secondary = Street.c.secondary
    val text = buildAnnotatedString {
        var word = StringBuilder()
        fun flush() {
            if (word.isEmpty()) return
            val parts = pinyinSyllables(word.toString()) ?: listOf(word.toString())
            parts.forEach { p ->
                withStyle(SpanStyle(color = if (tones) toneColor(pinyinTone(p).toInt()) else secondary)) { append(p) }
            }
            word = StringBuilder()
        }
        pinyin.forEach { c -> if (c.isLetter()) word.append(c) else { flush(); withStyle(SpanStyle(color = secondary)) { append(c) } } }
        flush()
    }
    Text(text, fontSize = size, fontWeight = weight)
}

/** Characters with their pinyin right above each one. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RubyText(hanzi: String, pinyin: String, size: TextUnit = 24.sp, weight: FontWeight = FontWeight.Medium, alwaysShow: Boolean = false, center: Boolean = false) {
    val s = LocalApp.current.settings
    val textColor = Street.c.text
    if (!(s.showPinyin || alwaysShow)) {
        Text(hanzi, fontSize = size, fontWeight = weight, color = textColor)
        return
    }
    val units = remember(hanzi, pinyin) { rubyUnits(hanzi, pinyin) }
    if (units == null) {
        Column(horizontalAlignment = if (center) Alignment.CenterHorizontally else Alignment.Start) {
            Text(hanzi, fontSize = size, fontWeight = weight, color = textColor)
            PinyinText(pinyin, (size.value * 0.5f).coerceAtLeast(13f).sp)
        }
        return
    }
    FlowRow(horizontalArrangement = if (center) Arrangement.Center else Arrangement.Start) {
        units.forEach { u ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 1.dp)) {
                Text(
                    u.syllable ?: " ",
                    fontSize = (size.value * 0.36f).coerceAtLeast(11f).sp,
                    fontWeight = FontWeight.Bold,
                    color = if (u.syllable == null) Color.Transparent else if (s.toneColors) toneColor(u.tone.toInt()) else Street.c.secondary,
                    maxLines = 1,
                )
                Text(u.character, fontSize = size, fontWeight = weight, color = textColor)
            }
        }
    }
}

// ---------- small widgets ----------

@Composable
fun SpeakButton(text: String, size: Dp = 44.dp, tint: Color = Street.c.red) {
    val haptic = LocalHapticFeedback.current
    Box(
        Modifier.size(size).clip(CircleShape).background(tint.copy(alpha = 0.15f))
            .border(2.dp, Street.c.ink, CircleShape)
            .clickable { haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove); Speaker.say(text) },
        contentAlignment = Alignment.Center,
    ) { Text("🔊", fontSize = (size.value * 0.4f).sp) }
}

@Composable
fun CloseButton(onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(Street.c.card).border(2.dp, Street.c.ink, CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text("✕", fontWeight = FontWeight.Bold, color = Street.c.text) }
}

/** Physics confetti. Changing [trigger] fires a burst. */
@Composable
fun Confetti(trigger: Int, sound: Boolean = true) {
    data class P(val x: Float, val vx: Float, val vy: Float, val spin: Float, val color: Color, val s: Float)
    val pieces = remember { mutableStateListOf<P>() }
    val time = remember { Animatable(0f) }
    val colors = listOf(Color(0xFFF53326), Color(0xFFFFC726), Color(0xFF29C266), Color(0xFF3370FF), Color(0xFFFF338C))
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        if (sound) Sfx.play(Sfx.Sound.Win)
        pieces.clear()
        repeat(90) {
            pieces += P(Random.nextFloat() * 0.4f + 0.3f, Random.nextFloat() * 760 - 380, -(Random.nextFloat() * 550 + 350),
                Random.nextFloat() * 16 - 8, colors.random(), Random.nextFloat() * 6 + 7)
        }
        time.snapTo(0f)
        time.animateTo(2.6f, tween(2600))
        pieces.clear()
    }
    if (pieces.isEmpty()) return
    Canvas(Modifier.fillMaxSize()) {
        val t = time.value
        pieces.forEach { p ->
            val x = p.x * size.width + p.vx * t * density / 2
            val y = size.height * 0.35f + (p.vy * t + 450 * t * t) * density / 2
            val a = (1 - t / 2.6f).coerceIn(0f, 1f)
            val ang = p.spin * t
            drawRect(p.color, Offset(x + cos(ang) * 2, y + sin(ang) * 2), Size(p.s * density / 2 * 1.6f, p.s * density / 2), alpha = a)
        }
    }
}

// ---------- player card ----------

@Composable
fun PlayerCardView(card: PlayerCard, compact: Boolean = false, coins: Int? = null) {
    Box {
        Row(
            Modifier.fillMaxWidth().block(com.asbestboi.meitian.data.Catalog.frame(card.frame)).padding(if (compact) 14.dp else 20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(if (compact) 54.dp else 74.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.22f))
                    .border(2.dp, Color.White.copy(alpha = 0.6f), CircleShape),
                contentAlignment = Alignment.Center,
            ) { Text(card.avatarSymbol, fontSize = if (compact) 30.sp else 44.sp) }
            HSpacer(14.dp)
            Column(Modifier.weight(1f)) {
                Text(card.name, color = Color.White, style = street(if (compact) 20.sp else 26.sp), maxLines = 1)
                card.titleItem?.let { Text("${it.symbol} · ${it.name}", color = Color.White.copy(alpha = 0.9f), fontWeight = FontWeight.Bold, fontSize = 13.sp) }
                Text("HSK ${card.level} · ${card.wins}W ${card.losses}L", color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
            coins?.let {
                Box(Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.22f)).padding(horizontal = 12.dp, vertical = 6.dp)) {
                    Text("🪙 $it", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }
        card.stickerSymbol?.let {
            Text(it, fontSize = if (compact) 30.sp else 40.sp, modifier = Modifier.align(Alignment.TopEnd).rotate(14f).padding(end = 2.dp))
        }
    }
}

// ---------- flashcards ----------

@Composable
fun WordCardFace(word: CoreWord, flipped: Boolean, modifier: Modifier = Modifier) {
    val rot by animateFloatAsState(if (flipped) 180f else 0f, spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow), label = "flip")
    Box(
        modifier.fillMaxSize().graphicsLayer { rotationY = rot; cameraDistance = 14 * density }.card(),
        contentAlignment = Alignment.Center,
    ) {
        if (rot <= 90f) {
            Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.SpaceBetween) {
                Pill(word.levelLabel, Street.levelColor(word.lvl))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    RubyText(word.hanzi, word.pinyin, size = if (word.hanzi.length > 3) 52.sp else if (word.hanzi.length > 2) 64.sp else 90.sp, weight = FontWeight.SemiBold, center = true)
                    Spacer(Modifier.height(14.dp))
                    SpeakButton(word.hanzi, 52.dp)
                }
                Text("👆 Tap to flip", color = Street.c.secondary, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
        } else {
            Column(Modifier.fillMaxSize().graphicsLayer { rotationY = 180f }.padding(22.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(word.hanzi, fontSize = 38.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text, modifier = Modifier.weight(1f))
                    SpeakButton(word.hanzi)
                }
                PinyinText(word.pinyin, 24.sp, FontWeight.Black)
                Text(word.meaning, fontSize = 19.sp, fontWeight = FontWeight.Medium, color = Street.c.text)
                Spacer(Modifier.weight(1f))
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Street.c.paper).padding(14.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        Box(Modifier.weight(1f)) { RubyText(word.example, word.examplePinyin, 21.sp, alwaysShow = true) }
                        SpeakButton(word.example, 36.dp, Street.c.jade)
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(word.exampleMeaning, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Street.c.text)
                }
            }
        }
    }
}

/** Swipe deck: 1:1 drag, flick projection, spring back. Right = got it, left = again. */
@Composable
fun SwipeDeck(words: List<CoreWord>, onFinish: () -> Unit) {
    val queue = remember(words) { mutableStateListOf<CoreWord>().apply { addAll(words) } }
    val dx = remember { Animatable(0f) }
    var flipped by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    var width by remember { mutableIntStateOf(1000) }

    fun commit(known: Boolean) {
        val w = queue.firstOrNull() ?: return
        Sfx.play(Sfx.Sound.Swoosh)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        scope.launch {
            dx.animateTo(if (known) width * 1.4f else -width * 1.4f, spring(stiffness = Spring.StiffnessMediumLow))
            queue.removeAt(0)
            if (!known) queue.add(w)
            flipped = false
            dx.snapTo(0f)
            if (queue.isEmpty()) onFinish()
        }
    }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        val done = words.size - queue.map { it.id }.toSet().size
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            words.indices.forEach { i ->
                Box(Modifier.weight(1f).height(6.dp).clip(RoundedCornerShape(3.dp)).background(if (i < done) Street.c.jade else Street.c.ink.copy(alpha = 0.12f)))
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth().pointerInput(Unit) { width = size.width }) {
            queue.take(3).reversed().forEachIndexed { revIndex, word ->
                val index = minOf(queue.size, 3) - 1 - revIndex
                val top = index == 0
                val progress = if (top) (abs(dx.value) / 300f).coerceAtMost(1f) else 0f
                Box(
                    Modifier.fillMaxSize()
                        .graphicsLayer {
                            translationX = if (top) dx.value else 0f
                            translationY = if (top) 0f else index * 16.dp.toPx()
                            rotationZ = if (top) dx.value / 40f else 0f
                            val sc = if (top) 1f else 1f - index * 0.05f
                            scaleX = sc; scaleY = sc
                        }
                        .then(
                            if (top) Modifier
                                .pointerInput(word.id) {
                                    var history = 0f
                                    detectDragGestures(
                                        onDragEnd = {
                                            val projected = dx.value + history * 6
                                            if (abs(projected) > 450 || abs(dx.value) > 300) commit(projected > 0)
                                            else scope.launch { dx.animateTo(0f, spring(dampingRatio = 0.7f)) }
                                        },
                                    ) { change, drag ->
                                        change.consume()
                                        history = drag.x
                                        scope.launch { dx.snapTo(dx.value + drag.x) }
                                    }
                                }
                                .clickable { flipped = !flipped }
                            else Modifier,
                        ),
                ) {
                    WordCardFace(word, top && flipped)
                    if (top && dx.value != 0f) {
                        Text(
                            if (dx.value > 0) "GOT IT" else "AGAIN",
                            color = if (dx.value > 0) Street.c.jade else Street.c.gold,
                            style = street(28.sp),
                            modifier = Modifier.align(if (dx.value > 0) Alignment.TopStart else Alignment.TopEnd).padding(28.dp)
                                .rotate(if (dx.value > 0) -14f else 14f).graphicsLayer { alpha = progress }
                                .border(4.dp, if (dx.value > 0) Street.c.jade else Street.c.gold, RoundedCornerShape(10.dp)).padding(horizontal = 12.dp, vertical = 4.dp),
                        )
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            BigButton("Again", Modifier.weight(1f), Street.gold()) { commit(false) }
            BigButton("Got it", Modifier.weight(1f), Street.jade()) { commit(true) }
        }
    }
}

// ---------- quiz ----------

/** Multiple choice, listening and speaking questions, one at a time. */
@Composable
fun QuizRunner(questions: List<Question>, allowPinyin: Boolean = true, onAnswer: (Question, Boolean) -> Unit = { _, _ -> },
               shouldContinue: (Int) -> Boolean = { true }, onDone: (Int) -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    val items = remember(questions) { mutableStateListOf<Question>().apply { addAll(questions.map { it.adjusted(app.settings) }) } }
    var index by remember { mutableIntStateOf(0) }
    var picked by remember { mutableStateOf<CoreWord?>(null) }
    var answered by remember { mutableStateOf<Boolean?>(null) }
    var correct by remember { mutableIntStateOf(0) }
    var tries by remember { mutableIntStateOf(0) }
    val listener = remember { SpeechListener(context) }
    var micDenied by remember { mutableStateOf(false) }
    var pendingWord by remember { mutableStateOf<CoreWord?>(null) }
    // the microphone is a runtime permission: ask the first time the mic is tapped
    val micPermission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { ok ->
        micDenied = !ok
        val w = pendingWord
        pendingWord = null
        if (ok && w != null) listener.start(w)
    }
    // fallback: Google's own voice-input popup (works on phones whose background service lacks Chinese)
    var dialogWord by remember { mutableStateOf<CoreWord?>(null) }
    val voiceDialog = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult(),
    ) { r ->
        val w = dialogWord ?: return@rememberLauncherForActivityResult
        listener.dialogResult(r.data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS) ?: emptyList(), w)
    }
    fun openVoiceDialog(w: CoreWord) {
        dialogWord = w
        val intent = android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "说：${w.hanzi}")
        }
        runCatching { voiceDialog.launch(intent) }
    }
    fun startListening(w: CoreWord) {
        val granted = androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) listener.start(w) else { pendingWord = w; micPermission.launch(android.Manifest.permission.RECORD_AUDIO) }
    }
    val haptic = LocalHapticFeedback.current
    val q = items.getOrNull(index) ?: return

    fun answer(right: Boolean) {
        if (answered != null) return
        listener.stop()
        answered = right
        if (right) { correct++; Sfx.play(Sfx.Sound.Correct) } else Sfx.play(Sfx.Sound.Wrong)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        onAnswer(q, right)
    }

    LaunchedEffect(q.id) {
        if (q.kind == Kind.Listen && app.settings.canListen) { delay(350); Speaker.say(q.word.hanzi) }
    }
    LaunchedEffect(listener.state) {
        if (q.kind == Kind.Speak && answered == null) {
            if (listener.state == SpeechListener.State.Matched) answer(true)
            if (listener.state == SpeechListener.State.Missed) tries++
        }
    }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LinearProgressIndicator(progress = { index.toFloat() / items.size.coerceAtLeast(1) }, modifier = Modifier.weight(1f).height(8.dp).clip(RoundedCornerShape(4.dp)), color = Street.c.red)
            if (answered == null && (q.kind == Kind.Listen || q.kind == Kind.Speak)) {
                HSpacer(10.dp)
                val listen = q.kind == Kind.Listen
                Box(Modifier.clip(RoundedCornerShape(50)).background(Street.c.card).border(1.5.dp, Street.c.ink, RoundedCornerShape(50)).clickable {
                    listener.reset()
                    val until = System.currentTimeMillis() + 3_600_000
                    app.settings = if (listen) app.settings.copy(noListenUntil = until) else app.settings.copy(noSpeakUntil = until)
                    app.save()
                    for (i in index until items.size) items[i] = items[i].adjusted(app.settings)
                }.padding(horizontal = 10.dp, vertical = 6.dp)) {
                    Text(if (listen) "🔇 Can't listen now" else "🎙️✕ Can't speak now", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.text)
                }
            }
        }
        Text(q.prompt.lowercase(), color = Street.c.secondary, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.CenterHorizontally))
        Box(Modifier.fillMaxWidth().heightIn(min = 160.dp).card().padding(18.dp), contentAlignment = Alignment.Center) {
            when (q.kind) {
                Kind.HanziToMeaning, Kind.Speak -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (allowPinyin) RubyText(q.word.hanzi, q.word.pinyin, if (q.word.hanzi.length > 3) 48.sp else 64.sp, FontWeight.SemiBold, alwaysShow = q.kind == Kind.Speak, center = true)
                    else Text(q.word.hanzi, fontSize = 66.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text)
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SpeakButton(q.word.hanzi, 40.dp)
                        if (q.kind == Kind.Speak) { HSpacer(10.dp); Text(q.word.shortMeaning, color = Street.c.secondary, fontWeight = FontWeight.Bold) }
                    }
                }
                Kind.MeaningToHanzi -> Text("“${q.word.shortMeaning}”", style = street(32.sp), color = Street.c.text, textAlign = TextAlign.Center)
                Kind.Listen -> SpeakButton(q.word.hanzi, 96.dp, Street.c.sky)
            }
        }
        if (q.kind == Kind.Speak) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val listening = listener.state == SpeechListener.State.Listening
                Box(
                    Modifier.size(104.dp).clip(CircleShape).background(if (listening) Street.c.red else Street.c.card).border(3.dp, Street.c.ink, CircleShape)
                        .clickable(enabled = answered == null) { if (listening) listener.stop() else startListening(q.word) },
                    contentAlignment = Alignment.Center,
                ) { Text(if (listening) "〰️" else "🎙️", fontSize = 40.sp) }
                Text(
                    if (micDenied) "Allow the microphone in Settings to use speaking."
                    else if (listener.problem.isNotEmpty()) listener.problem
                    else when (listener.state) {
                        SpeechListener.State.Listening -> if (listener.heard.isEmpty()) "Listening… say “${q.word.hanzi}”" else "Heard: ${listener.heard}"
                        SpeechListener.State.Missed -> if (listener.heard.isEmpty()) "Didn't catch that. Try again." else "Heard “${listener.heard}”. Try again!"
                        SpeechListener.State.Unavailable -> "Speech recognition isn't available on this phone."
                        else -> "Tap the mic and say the word"
                    },
                    color = if (listener.state == SpeechListener.State.Missed) Street.c.red else Street.c.secondary, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                )
                if (answered == null && (listener.state == SpeechListener.State.Unavailable || tries >= 1)) {
                    Text("🎙️ Use Google voice input", color = Street.c.sky, fontWeight = FontWeight.Bold,
                        modifier = Modifier.clickable { openVoiceDialog(q.word) }.padding(6.dp))
                }
                if (answered == null && (tries >= 2 || micDenied || listener.state == SpeechListener.State.Unavailable)) {
                    Text("Skip this one", color = Street.c.red, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { answer(false) })
                }
            }
        } else {
            val isHanzi = q.kind != Kind.HanziToMeaning
            q.options.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { o ->
                        val isAnswer = o.id == q.word.id
                        val isPicked = picked?.id == o.id
                        val bg = when { answered == null -> Street.c.card; isAnswer -> Street.c.jade.copy(alpha = 0.25f); isPicked -> Street.c.red.copy(alpha = 0.22f); else -> Street.c.card }
                        Column(
                            Modifier.weight(1f).heightIn(min = 74.dp).streetCard(bg, if (answered != null && isAnswer) Street.c.jade else Street.c.ink, shadow = 3.dp)
                                .clickable(enabled = answered == null) { picked = o; answer(isAnswer) }.padding(8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                        ) {
                            Text(q.label(o), fontSize = if (isHanzi) 28.sp else 16.sp, fontWeight = if (isHanzi) FontWeight.Medium else FontWeight.Bold,
                                color = Street.c.text, textAlign = TextAlign.Center, maxLines = 2)
                            if (isHanzi && allowPinyin && app.settings.showPinyin) PinyinText(o.pinyin, 12.sp)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        answered?.let { right ->
            Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row {
                    Column(Modifier.weight(1f)) {
                        Text(if (right) listOf("太好了!", "对了!", "厉害!", "Nice!")[index % 4] else "Almost!", style = street(22.sp), color = if (right) Street.c.jade else Street.c.red)
                        if (right && index % 4 < 3) Text(listOf("tài hǎo le · great", "duì le · correct", "lìhai · awesome")[index % 4], fontSize = 12.sp, color = Street.c.secondary)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text("${q.word.hanzi} · ${q.word.pinyin}", fontWeight = FontWeight.Bold, color = Street.c.text)
                        Text(q.word.meaning, fontSize = 13.sp, color = Street.c.secondary)
                    }
                }
                BigButton(if (index + 1 < items.size) "Continue" else "Finish", brush = if (right) Street.jade() else Street.warm()) {
                    val n = index + 1
                    if (n >= items.size || !shouldContinue(n)) { onDone(correct); return@BigButton }
                    listener.reset(); picked = null; answered = null; tries = 0
                    items[n] = items[n].adjusted(app.settings)
                    index = n
                }
            }
        }
    }
}

/** Compact 2×2 options used by battles and the Swear Sprint. */
@Composable
fun FastQuestion(q: Question, picked: CoreWord?, locked: Boolean, reveal: Boolean, compact: Boolean = false, onPick: (CoreWord) -> Unit) {
    val app = LocalApp.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(min = if (compact) 70.dp else 110.dp).card().padding(10.dp), contentAlignment = Alignment.Center) {
            if (q.kind == Kind.Listen) Column(horizontalAlignment = Alignment.CenterHorizontally) {
                // listening duel: no characters, just the sound
                LaunchedEffect(q.id) { Speaker.say(q.word.hanzi) }
                SpeakButton(q.word.hanzi, if (compact) 64.dp else 84.dp, Street.c.jade)
                Text("listen and tap it", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
            }
            else if (q.kind == Kind.HanziToMeaning) RubyText(q.word.hanzi, q.word.pinyin, if (compact) 38.sp else 54.sp, FontWeight.SemiBold, center = true)
            else Text("“${q.word.shortMeaning}”", style = street(if (compact) 24.sp else 30.sp), color = Street.c.text, textAlign = TextAlign.Center)
        }
        q.options.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { o ->
                    val isAnswer = o.id == q.word.id
                    val isPicked = picked?.id == o.id
                    val bg = when { reveal && isAnswer -> Street.c.jade.copy(alpha = 0.25f); isPicked && !isAnswer -> Street.c.red.copy(alpha = 0.22f); isPicked -> Street.c.jade.copy(alpha = 0.25f); else -> Street.c.card }
                    val isHanzi = q.kind != Kind.HanziToMeaning
                    Column(
                        Modifier.weight(1f).heightIn(min = if (compact) 54.dp else 66.dp).streetCard(bg, Street.c.ink, shadow = 3.dp)
                            .graphicsLayer { alpha = if (locked && !isPicked && !(reveal && isAnswer)) 0.45f else 1f }
                            .clickable(enabled = !locked && picked == null) { onPick(o) }.padding(6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Text(if (isHanzi) o.hanzi else o.shortMeaning, fontSize = if (isHanzi) 24.sp else 15.sp, fontWeight = FontWeight.Bold, color = Street.c.text, textAlign = TextAlign.Center, maxLines = 2)
                        if (isHanzi && app.settings.showPinyin) PinyinText(o.pinyin, 11.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun StatBox(value: String, label: String, color: Color = Street.c.text, modifier: Modifier = Modifier) {
    Column(modifier.card().padding(vertical = 12.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = street(26.sp), color = color)
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
    }
}

@Composable
fun GradientIcon(emoji: String, brush: Brush, size: Dp = 46.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(12.dp)).background(brush).border(2.dp, Street.c.ink, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
        Text(emoji, fontSize = (size.value * 0.48f).sp)
    }
}

@Composable
fun Gap(h: Dp) = Spacer(Modifier.height(h))

@Composable
fun Wide(content: @Composable () -> Unit) = Box(Modifier.fillMaxWidth().width(0.dp)) { content() }
