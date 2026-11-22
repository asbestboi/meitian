package com.asbestboi.meitian.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.data.Sfx
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import uniffi.meitian_core.ArenaTheme
import uniffi.meitian_core.SoundId
import uniffi.meitian_core.ArenaStop
import uniffi.meitian_core.ArenaStopState
import uniffi.meitian_core.arenaFrame
import uniffi.meitian_core.arenaRoad
import uniffi.meitian_core.arenaScene
import com.asbestboi.meitian.LocalApp

/** Part of the scenery, rendered once. Taller than the view, so moving it up never uncovers its bottom. */
private class SceneImage(val image: ImageBitmap, val parallax: Float)

private const val SCENE_SCALE = 0.75f
private const val SCENE_TALL = 1.15f

/** Renders the still layers; without parallax ([flat]) they become one picture. */
private fun renderScene(theme: ArenaTheme, w: Float, h: Float, dark: Boolean, density: Float, flat: Boolean): List<SceneImage> {
    val layers = arenaScene(theme, w, h, dark)
    val renderer = OpsRenderer()
    val px = (w * density * SCENE_SCALE).toInt().coerceAtLeast(1)
    val py = (h * density * SCENE_SCALE * (if (flat) 1f else SCENE_TALL)).toInt().coerceAtLeast(1)
    fun bitmap(parts: List<uniffi.meitian_core.SceneLayer>) = android.graphics.Bitmap.createBitmap(px, py, android.graphics.Bitmap.Config.ARGB_8888).also { bm ->
        val c = android.graphics.Canvas(bm)
        parts.forEach { renderer.draw(c, it.ops, density * SCENE_SCALE) }
        bm.prepareToDraw()
    }.asImageBitmap()
    return if (flat) listOf(SceneImage(bitmap(layers), 0f)) else layers.map { SceneImage(bitmap(listOf(it)), it.parallax) }
}

/**
 * An arena's scenery, drawn by the core: still layers that move a little with [scroll] (px, parallax) and a moving
 * part on top. [strength] fades it into the paper colour so text on top stays readable.
 */
@Composable
fun ArenaBackground(theme: ArenaTheme, modifier: Modifier = Modifier, strength: Float = 0.55f, live: Boolean = true, scroll: (() -> Float)? = null) {
    val dark = isSystemInDarkTheme()
    val reduce = reduceMotion()
    val density = LocalDensity.current.density
    val paper = Street.c.paper
    val renderer = remember { OpsRenderer() }
    var frame by remember { mutableLongStateOf(0L) }
    if (!reduce && live) LaunchedEffect(theme.id) {
        var last = 0L
        while (true) withFrameNanos { now ->
            // thirty frames a second is plenty for drifting petals
            if (now - last >= 30_000_000L) { last = now; frame = now }
        }
    }
    BoxWithConstraints(modifier.fillMaxSize().clipToBounds()) {
        val w = constraints.maxWidth / density
        val h = constraints.maxHeight / density
        // rendered once, away from the main thread
        val scene by produceState(emptyList<SceneImage>(), theme.id, w, h, dark) {
            value = withContext(Dispatchers.Default) { renderScene(theme, w, h, dark, density, scroll == null) }
        }
        Canvas(Modifier.fillMaxSize()) {
            val y = if (reduce || scroll == null) 0f else scroll()
            scene.forEach { layer ->
                val shift = (y * layer.parallax).coerceIn(-size.height * 0.12f, size.height * 0.12f)
                drawImage(layer.image, dstOffset = IntOffset(0, -shift.roundToInt()),
                    dstSize = IntSize(size.width.roundToInt(), (size.height * layer.image.height / (size.height * SCENE_SCALE)).roundToInt()),
                    filterQuality = FilterQuality.Low)
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            if (scene.isEmpty()) return@Canvas
            val ops = arenaFrame(theme, (frame / 1_000_000L).toULong(), w, h, dark)
            drawIntoCanvas { renderer.draw(it.nativeCanvas, ops, density) }
            if (strength < 1f) drawRect(paper.copy(alpha = 1f - strength))
        }
    }
}

/** Rank badge: the arena somebody plays in. */
@Composable
fun ArenaBadge(theme: ArenaTheme, color: Color = Street.c.text, background: Color = Street.c.card) {
    Row(Modifier.clip(RoundedCornerShape(50)).background(background).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(theme.emoji, fontSize = 13.sp)
        Text("${theme.nameZh} · ${theme.nameEn}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = color, maxLines = 1)
    }
}

/** Full screen: the learner crossed into a new arena. */
@Composable
fun ArenaReveal(theme: ArenaTheme, close: () -> Unit) {
    val reduce = reduceMotion()
    val haptic = LocalHapticFeedback.current
    val dark = isSystemInDarkTheme()
    val fade = remember { Animatable(0f) }
    val pop = remember { Animatable(if (reduce) 1f else 0.4f) }
    LaunchedEffect(theme.id) {
        Sfx.play(SoundId.ARENA_UNLOCK)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        launch { fade.animateTo(1f, tween(if (reduce) 200 else 700)) }
        delay(if (reduce) 0 else 450)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        pop.animateTo(1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
    }
    Box(Modifier.fillMaxSize().graphicsLayer { alpha = fade.value }) {
        ArenaBackground(theme, strength = 1f)
        // light skies get dark text, hellish ones white
        val ink = if (dark || theme.tier >= 5u) Color.White else Color(0xFF16181D)
        Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Spacer(Modifier.weight(0.6f))
            Column(Modifier.graphicsLayer { scaleX = pop.value; scaleY = pop.value }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("new arena unlocked!", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = ink.copy(alpha = 0.85f))
                Text(theme.emoji, fontSize = 88.sp)
                Text(theme.nameZh, fontSize = 60.sp, fontWeight = FontWeight.Black, color = ink, textAlign = TextAlign.Center)
                Text(theme.pinyin, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = ink.copy(alpha = 0.85f))
                Text(theme.nameEn, style = street(28.sp), color = ink, textAlign = TextAlign.Center)
                Text("arena ${theme.tier} of 6", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = ink.copy(alpha = 0.75f))
            }
            Spacer(Modifier.weight(1f))
            BigButton("enter →", onClick = close)
        }
    }
}

/** One arena on the road: its scenery, name and what it takes to get there. */
@Composable
fun ArenaPanel(stop: ArenaStop, modifier: Modifier = Modifier, live: Boolean = true) {
    val locked = stop.state == ArenaStopState.LOCKED
    val here = stop.state == ArenaStopState.CURRENT
    val shape = RoundedCornerShape(28.dp)
    val theme = stop.theme
    Box(
        modifier.clip(shape).border(if (here) 4.dp else 0.dp, if (here) Street.c.lime else Color.Transparent, shape)
            .semantics(mergeDescendants = true) { contentDescription = "Arena ${theme.tier}: ${theme.nameEn}. ${if (locked) "Locked, unlocks at HSK ${stop.level}" else if (here) "You are here" else "Conquered"}" },
    ) {
        ArenaBackground(theme, strength = 1f, live = live)
        // locked arenas stay visible, just a little dimmed
        if (locked) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f)))
        Box(Modifier.fillMaxWidth().height(150.dp).align(Alignment.BottomCenter).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.72f)))))
        Text(if (locked) "🔒" else if (here) "you are here" else "✓ conquered", fontSize = if (locked) 26.sp else 13.sp, fontWeight = FontWeight.ExtraBold,
            color = if (here) Color.Black else Color.White,
            modifier = Modifier.align(Alignment.TopEnd).padding(14.dp).clip(RoundedCornerShape(50))
                .background(if (here) Street.c.lime else Color.Black.copy(alpha = 0.45f)).padding(horizontal = 12.dp, vertical = 6.dp))
        Text("arena ${theme.tier}", fontSize = 13.sp, fontWeight = FontWeight.ExtraBold, color = Color.White,
            modifier = Modifier.align(Alignment.TopStart).padding(14.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 12.dp, vertical = 6.dp))
        Column(Modifier.align(Alignment.BottomStart).padding(18.dp)) {
            Text("${theme.emoji} ${theme.nameZh}", fontSize = 30.sp, fontWeight = FontWeight.Black, color = Color.White)
            Text("${theme.pinyin} · ${theme.nameEn}", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.9f))
            Text(if (locked) "HSK ${stop.level} · pass the HSK ${stop.level.toInt() - 1} test" else "HSK ${stop.level}", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.8f))
        }
    }
}

/** Every arena, the last one at the top: climb from the meadow to the gates of hell. */
@Composable
fun ArenaRoad(close: () -> Unit) {
    val app = LocalApp.current
    val stops = remember(app.currentLevel) { arenaRoad(app.currentLevel.coerceIn(0, 255).toUByte(), 1u).reversed() }
    val here = stops.indexOfFirst { it.state == ArenaStopState.CURRENT }.coerceAtLeast(0)
    val state = rememberLazyListState(initialFirstVisibleItemIndex = here)
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            CloseButton(close); HSpacer(12.dp)
            Text("arena road", style = street(24.sp), color = Street.c.text)
        }
        LazyColumn(state = state, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            items(stops.size, key = { stops[it].theme.id }) { i ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // only what's on screen moves
                    ArenaPanel(stops[i], Modifier.fillMaxWidth().height(400.dp))
                    if (i < stops.size - 1) Text("▲", fontSize = 22.sp, color = if (stops[i].state == ArenaStopState.LOCKED) Street.c.secondary else Street.c.lime, modifier = Modifier.padding(vertical = 4.dp))
                }
            }
        }
    }
}
