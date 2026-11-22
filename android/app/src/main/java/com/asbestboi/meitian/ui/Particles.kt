package com.asbestboi.meitian.ui

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.auraFrame
import uniffi.meitian_core.hasAura
import uniffi.meitian_core.hitFrame
import uniffi.meitian_core.hitInfo
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

@Composable
fun reduceMotion(): Boolean {
    val ctx = LocalContext.current
    return remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * A hit: something flies from [from] to [to] (fractions of this box) and lands with a bang. Every frame comes from
 * the core. [onImpact] gets the shake strength (dp).
 */
@Composable
fun HitEffect(effectId: String, trigger: Int, from: Offset, to: Offset, damage: Int? = null, modifier: Modifier = Modifier.fillMaxSize(), onImpact: (Float) -> Unit = {}) {
    val info = remember(effectId) { hitInfo(effectId) }
    val renderer = remember { OpsRenderer() }
    val density = LocalDensity.current.density
    val reduce = reduceMotion()
    // milliseconds since the throw; -1 = nothing flying
    var at by remember { mutableIntStateOf(-1) }
    val dmg = remember { Animatable(0f) }

    BoxWithConstraints(modifier) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        LaunchedEffect(trigger) {
            if (trigger == 0) return@LaunchedEffect
            if (reduce) {
                // no flying particles: just show the damage
                dmg.snapTo(1f); delay(800); dmg.animateTo(0f, tween(200)); return@LaunchedEffect
            }
            dmg.snapTo(0f)
            val start = withFrameNanos { it }
            var landed = false
            while (true) {
                val t = ((withFrameNanos { it } - start) / 1_000_000L).toInt()
                if (t >= info.durationMs.toInt()) break
                at = t
                if (!landed && t >= info.impactMs.toInt()) {
                    landed = true
                    onImpact(info.shake)
                    launch { dmg.animateTo(1f, spring(0.6f)); delay(600); dmg.animateTo(0f, tween(250)) }
                }
            }
            at = -1
        }
        Canvas(Modifier.fillMaxSize()) {
            val t = at
            if (t < 0) return@Canvas
            val ops = hitFrame(info.id, t.toUInt(), w / density, h / density, from.x * w / density, from.y * h / density, to.x * w / density, to.y * h / density)
            drawIntoCanvas { renderer.draw(it.nativeCanvas, ops, density) }
        }
        damage?.let { d ->
            val bx = to.x * w; val by = to.y * h
            Text("-$d", fontSize = 44.sp, fontWeight = FontWeight.Bold, color = Color.White,
                style = TextStyle(shadow = Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 4f), 10f)),
                modifier = Modifier.offset { IntOffset((bx - 40 * density).roundToInt(), (by + (if (to.y < 0.5f) 50 else -110) * density).roundToInt()) }
                    .scale(0.4f + 0.6f * dmg.value).alpha(dmg.value))
        }
    }
}

/** Idle aura around an avatar (au.* cosmetics). Draws nothing for "no aura". */
@Composable
fun Aura(auraId: String?, radiusDp: Float, modifier: Modifier = Modifier) {
    if (auraId == null || !hasAura(auraId) || reduceMotion()) return
    val renderer = remember { OpsRenderer() }
    val density = LocalDensity.current.density
    var frame by remember { mutableLongStateOf(0L) }
    LaunchedEffect(auraId) { while (true) frame = withFrameNanos { it } }
    Box(modifier) {
        Canvas(Modifier.fillMaxSize()) {
            val ops = auraFrame(auraId, (frame / 1_000_000L).toULong(), size.width / density, size.height / density, radiusDp)
            drawIntoCanvas { renderer.draw(it.nativeCanvas, ops, density) }
        }
    }
}

/** Screen-shake offset driven by [HitEffect]'s onImpact. */
class Shake {
    val t = Animatable(1f)
    var strength by mutableStateOf(0f)
    suspend fun hit(s: Float) { strength = s; t.snapTo(0f); t.animateTo(1f, tween(450)) }
    fun offset(density: Float): IntOffset {
        val d = 1f - t.value
        return IntOffset((strength * density * d * sin(t.value * PI * 9)).toFloat().roundToInt(), (strength * 0.5f * density * d * cos(t.value * PI * 7)).toFloat().roundToInt())
    }
}
