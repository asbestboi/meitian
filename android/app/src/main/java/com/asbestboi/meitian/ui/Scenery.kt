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
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.data.Sfx
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.ArenaTheme
import uniffi.meitian_core.SoundId
import uniffi.meitian_core.arenaLook
import kotlin.math.PI
import kotlin.random.Random

/**
 * An arena's scenery (sky, three silhouettes, drifting particles), drawn from the core's numbers. [strength] fades it
 * into the paper colour so text on top stays readable; [scroll] (px) moves the silhouettes a little (parallax).
 */
@Composable
fun ArenaBackground(theme: ArenaTheme, modifier: Modifier = Modifier, strength: Float = 0.55f, scroll: () -> Float = { 0f }) {
    val look = remember(theme) { arenaLook(theme) }
    val dark = isSystemInDarkTheme()
    val reduce = reduceMotion()
    val density = LocalDensity.current.density
    val paper = Street.c.paper
    val sky = remember(look, dark) { (if (dark) look.skyDark else look.skyLight).map(::hexColor) }
    val system = remember(theme.id) { ParticleSystem() }
    var frame by remember { mutableLongStateOf(0L) }
    val size = remember { floatArrayOf(0f, 0f) }
    if (!reduce) LaunchedEffect(theme) {
        var last = withFrameNanos { it }
        var debt = 0f
        while (true) {
            val now = withFrameNanos { it }
            // thirty frames a second is plenty for drifting petals
            if (now - last < 30_000_000L) continue
            val dt = ((now - last) / 1e9f).coerceAtMost(0.1f)
            last = now
            debt += look.particles.rate * dt
            while (debt >= 1f && size[0] > 0f) {
                debt -= 1f
                val y = if (look.rising) size[1] * (0.75f + 0.25f * Random.nextFloat()) else -10f * density
                system.burst(look.particles, Random.nextFloat() * size[0], y, (if (look.rising) -PI / 2 else PI / 2).toFloat(), 1, density)
            }
            system.step(dt, look.particles.gravity, density)
            frame = now
        }
    }
    Canvas(modifier.fillMaxSize().clipToBounds()) {
        if (frame < 0L) return@Canvas   // reading frame redraws every tick
        size[0] = this.size.width
        size[1] = this.size.height
        val w = this.size.width
        val h = this.size.height
        drawRect(Brush.verticalGradient(sky))
        look.layers.forEach { layer ->
            val shift = if (reduce) 0f else (scroll() * layer.parallax).coerceIn(-h * 0.12f, h * 0.12f)
            val path = Path().apply {
                moveTo(0f, h)
                layer.heights.forEachIndexed { i, y -> lineTo(w * i / (layer.heights.size - 1), h - h * y + shift) }
                lineTo(w, h)
                close()
            }
            drawPath(path, hexColor(if (dark) layer.colorDark else layer.colorLight))
        }
        system.draw(this, look.particles)
        if (strength < 1f) drawRect(paper.copy(alpha = 1f - strength))
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
