package com.asbestboi.meitian.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.LocalNav
import com.asbestboi.meitian.data.Catalog
import com.asbestboi.meitian.data.ContentSync
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.Speaker
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.Sentence
import uniffi.meitian_core.SlotPrize
import uniffi.meitian_core.SoundId
import uniffi.meitian_core.SpinResult
import uniffi.meitian_core.pinyinTypedOk
import uniffi.meitian_core.shuffledTiles
import uniffi.meitian_core.slotSymbols
import uniffi.meitian_core.spinSentenceXp
import uniffi.meitian_core.wordOrderCorrect

/** Today: the spins earned by finishing units and the won sentence, pinned above the path. */
@Composable
fun SlotCard() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val left = app.spinsLeft
    val ready = left > 0
    val next = app.learnPath.firstOrNull { u -> u.nodes.any { it.kind == uniffi.meitian_core.PathNodeKind.STORY && it.state != uniffi.meitian_core.PathNodeState.DONE } }?.number
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            Modifier.weight(1f).clip(RoundedCornerShape(20.dp)).then(if (ready) Modifier.background(Street.gold()) else Modifier.background(Street.c.card))
                .clickable { nav.show { SlotMachine { nav.close() } } }.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("🎰", fontSize = 24.sp); HSpacer(10.dp)
            Column {
                Text(if (left == 1) "you have a spin!" else if (ready) "you have $left spins!" else "next spin", fontWeight = FontWeight.ExtraBold, fontSize = if (ready) 15.sp else 12.sp,
                    color = if (ready) Color.Black else Street.c.secondary)
                Text(if (ready) "one for every finished unit" else if (next != null) "finish unit $next" else "finish a unit", fontWeight = FontWeight.Bold, fontSize = if (ready) 12.sp else 15.sp,
                    color = if (ready) Color.Black.copy(alpha = 0.7f) else Street.c.text)
            }
        }
        // only when something changed
        val sentence = remember(app.slots.sentenceId, ContentSync.generation, app.knownList.size) { app.slotSentence }
        if (sentence != null) Row(
            Modifier.weight(1f).clip(RoundedCornerShape(20.dp)).background(Street.c.card)
                .clickable { nav.show { SentenceOfTheDay(sentence) { nav.close() } } }.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (app.slots.sentenceDone) "✅" else "📝", fontSize = 24.sp); HSpacer(10.dp)
            Column {
                Text("bonus sentence", fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, color = Street.c.secondary, maxLines = 1)
                Text(if (app.slots.sentenceDone) sentence.zh else "hear, build, type · +${spinSentenceXp()} XP", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
            }
        }
    }
}

/** The slot machine: a free spin for every finished unit, and spins stack up. */
@Composable
fun SlotMachine(close: () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val reduce = reduceMotion()
    val symbols = remember { slotSymbols() }
    val reels = remember { mutableStateListOf("🪙", "🎨", "📝") }
    val bounce = remember { List(3) { Animatable(1f) } }
    val lever = remember { Animatable(0f) }
    val glow = remember { Animatable(1f) }
    var busy by remember { mutableStateOf(false) }
    var won by remember { mutableStateOf<SpinResult?>(null) }
    var confetti by remember { mutableIntStateOf(0) }
    val left = app.spinsLeft

    fun spin() {
        if (busy) return
        busy = true; won = null
        scope.launch {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            launch { lever.animateTo(1f, tween(160)); lever.animateTo(0f, spring(dampingRatio = 0.4f)) }
            // the prize is decided and saved before the reels move
            val result = app.spin()
            if (result == null) { busy = false; return@launch }
            if (!reduce) {
                val start = android.os.SystemClock.elapsedRealtime()
                var stopped = 0
                var at = 0
                while (stopped < 3) {
                    val t = android.os.SystemClock.elapsedRealtime() - start
                    for (i in stopped until 3) reels[i] = symbols[(at + i * 3) % symbols.size]
                    at++
                    Sfx.play(SoundId.REEL_TICK)
                    if (t > 1_000 + 650 * stopped) {
                        val i = stopped++
                        reels[i] = result.reels[i]
                        Sfx.play(SoundId.REEL_STOP)
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        launch { bounce[i].snapTo(1.35f); bounce[i].animateTo(1f, spring(dampingRatio = Spring.DampingRatioHighBouncy)) }
                    }
                    delay(75)
                }
                delay(250)
            }
            result.reels.forEachIndexed { i, s -> reels[i] = s }
            won = result
            busy = false
            val prize = result.prize
            val small = prize is SlotPrize.Coins && prize.amount <= 20u
            if (prize is SlotPrize.Coins && prize.jackpot) {
                Sfx.play(SoundId.JACKPOT)
                repeat(3) {
                    confetti++
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    launch { if (!reduce) { glow.snapTo(1.25f); glow.animateTo(1f, spring(dampingRatio = 0.35f)) } }
                    delay(900)
                }
            } else {
                if (!small) confetti++
                Sfx.play(if (small) SoundId.COIN else SoundId.WIN)
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); Spacer(Modifier.weight(1f)); Text("lucky spin", style = street(22.sp), color = Street.c.text); Spacer(Modifier.weight(1f)); Spacer(Modifier.size(40.dp))
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.graphicsLayer { scaleX = glow.value; scaleY = glow.value }.block(Street.warm()).padding(14.dp)
                        .semantics(mergeDescendants = true) { contentDescription = if (won != null) "Reels: ${reels.joinToString(" ")}" else "Slot machine" },
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    reels.forEachIndexed { i, s ->
                        Box(Modifier.size(78.dp, 108.dp).clip(RoundedCornerShape(18.dp)).background(Color(0xFFFFF8E8)).border(3.dp, Color(0xFFFFD23F), RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                            Text(s, fontSize = 46.sp, color = Color(0xFFD0021B), fontWeight = FontWeight.Black,
                                modifier = Modifier.graphicsLayer { scaleX = bounce[i].value; scaleY = bounce[i].value })
                        }
                    }
                }
                // the lever
                Box(Modifier.padding(start = 10.dp).height(130.dp).size(28.dp, 130.dp).clickable(enabled = left > 0 && !busy) { spin() }.semantics { contentDescription = "Pull the lever" }) {
                    Box(Modifier.align(Alignment.Center).size(8.dp, 110.dp).clip(RoundedCornerShape(50)).background(Street.c.secondary.copy(alpha = 0.4f)))
                    Box(Modifier.align(Alignment.TopCenter).graphicsLayer { translationY = lever.value * 80.dp.toPx() }.size(28.dp).clip(CircleShape).background(Street.c.red))
                }
            }
            Spacer(Modifier.height(6.dp))
            won?.let { PrizeView(it.prize) }
            Spacer(Modifier.weight(1f))
            when {
                busy -> BigButton("…", enabled = false) {}
                left > 0 -> {
                    if (left > 1) Text("$left spins left", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                    BigButton(if (won == null) "spin! 🎰" else "spin again 🎰", brush = Street.gold()) { spin() }
                }
                else -> {
                    Text("finish a unit to earn another spin", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                    BigButton("Done", onClick = close)
                }
            }
            Text("A free spin for every finished unit; they stack up. Coins, cosmetics and sentences only.", fontSize = 12.sp, color = Street.c.secondary, textAlign = TextAlign.Center)
        }
        Confetti(confetti, sound = false)
    }
}

@Composable
private fun ColumnScope.PrizeView(prize: SlotPrize) {
    val app = LocalApp.current
    val nav = LocalNav.current
    Column(Modifier.align(Alignment.CenterHorizontally), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when (prize) {
            is SlotPrize.Coins -> {
                if (prize.jackpot) Text("大奖！ JACKPOT!", style = street(38.sp), color = Street.c.red)
                Text("+${prize.amount} 🪙", style = street(if (prize.jackpot) 56.sp else 40.sp), color = Street.c.gold)
            }
            is SlotPrize.Cosmetic -> Catalog[prize.id]?.let { item ->
                Text("new ${item.kind.label.lowercase().removeSuffix("s")}!", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                Text("${item.symbol} ${item.name}".trim(), style = street(30.sp), color = Street.c.text)
                val on = app.equipped(item.kind) == item.id
                Pill(if (on) "equipped ✓" else "equip", if (on) Street.c.secondary else Street.c.jade, modifier = Modifier.clickable(enabled = !on) { app.equip(item) })
            }
            is SlotPrize.Sentence -> {
                Text("a bonus sentence 📝", fontWeight = FontWeight.Bold, color = Street.c.secondary)
                TokenSentence(prize.sentence.tokens, 26.sp, center = true)
                BigButton("learn it · +${spinSentenceXp()} XP", brush = Street.jade()) { nav.show { SentenceOfTheDay(prize.sentence) { nav.close() } } }
            }
        }
    }
}

/** A three-step mini-lesson: hear the sentence, build it, type it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SentenceOfTheDay(sentence: Sentence, close: () -> Unit) {
    val app = LocalApp.current
    val haptic = LocalHapticFeedback.current
    var step by remember { mutableIntStateOf(0) }
    var wrong by remember { mutableStateOf(false) }
    var gained by remember { mutableIntStateOf(0) }
    var confetti by remember { mutableIntStateOf(0) }
    val tiles = remember { shuffledTiles(sentence, kotlin.random.Random.nextLong().toULong()) }
    val built = remember { mutableStateListOf<Int>() }
    var text by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { app.markSeen(sentence.tokens.newIds); delay(400); Speaker.say(sentence.zh) }
    fun answer(right: Boolean) {
        wrong = !right
        Sfx.play(if (right) SoundId.CORRECT else SoundId.WRONG)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        if (!right) return
        step++
        if (step == 3) { gained = app.finishSlotSentence(); confetti++; Sfx.play(SoundId.WIN); Speaker.say(sentence.zh) }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton(close); Spacer(Modifier.weight(1f)); Text("bonus sentence", style = street(20.sp), color = Street.c.text); Spacer(Modifier.weight(1f)); Spacer(Modifier.size(40.dp))
            }
            Text(listOf("1 · listen", "2 · build it", "3 · type the pinyin", "done! 完成了")[step], style = street(26.sp), color = Street.c.text)
            Column(Modifier.fillMaxWidth().card().padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Box(Modifier.weight(1f)) {
                        when (step) {
                            0, 3 -> TokenSentence(sentence.tokens, 28.sp, forcePinyin = true)
                            1 -> Text("“${sentence.en}”", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text)
                            else -> Text(sentence.zh, fontSize = 28.sp, color = Street.c.text)
                        }
                    }
                    HSpacer(8.dp)
                    SpeakButton(sentence.zh, 44.dp, Street.c.sky)
                }
                if (step == 0 || step == 3) Text(sentence.en, color = Street.c.secondary)
                if (step == 0) Text("🐢 slower", fontWeight = FontWeight.Bold, color = Street.c.sky, modifier = Modifier.clickable { Speaker.say(sentence.zh, true) })
            }
            when (step) {
                0 -> BigButton("got it", brush = Street.jade()) { step = 1 }
                1 -> {
                    FlowRow(Modifier.fillMaxWidth().heightIn(min = 54.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        built.forEach { i -> Tile(tiles[i]) { built.remove(i) } }
                    }
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Street.c.secondary.copy(alpha = 0.3f)))
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        tiles.forEachIndexed { i, t -> Tile(t, used = i in built) { if (i !in built) { Speaker.say(t); built.add(i) } } }
                    }
                    BigButton("check", brush = Street.jade(), enabled = built.size == tiles.size) {
                        answer(wordOrderCorrect(sentence, built.map { tiles[it] }).also { if (!it) built.clear() })
                    }
                }
                2 -> {
                    val submit = { if (text.isNotBlank()) answer(pinyinTypedOk(text, sentence.pinyin)) }
                    OutlinedTextField(text, { text = it; wrong = false }, Modifier.fillMaxWidth(), label = { Text("pinyin, no tones needed") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { submit() }))
                    BigButton("check", brush = Street.jade(), enabled = text.isNotBlank()) { submit() }
                    if (wrong) Text("hint: ${sentence.pinyin}", color = Street.c.secondary, fontWeight = FontWeight.SemiBold)
                }
                else -> {
                    Text(if (gained > 0) "+$gained XP" else "already done · no XP", style = street(30.sp), color = if (gained > 0) Street.c.gold else Street.c.secondary,
                        textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                    BigButton("Done", onClick = close)
                }
            }
            if (wrong) Text("not quite, try again", color = Street.c.red, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        Confetti(confetti, sound = false)
    }
}
