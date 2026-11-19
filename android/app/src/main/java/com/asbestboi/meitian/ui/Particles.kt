package com.asbestboi.meitian.ui

import android.graphics.Paint
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.sp
import uniffi.meitian_core.EffectSpec
import uniffi.meitian_core.ParticleShape
import uniffi.meitian_core.auraSpec
import uniffi.meitian_core.effectSpec
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.launch

fun hexColor(hex: String): Color = runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrDefault(Color.White)

/** Tiny particle simulation, stepped by a frame loop and drawn on a Canvas (same recipes as iOS). */
class ParticleSystem {
    class P(var x: Float, var y: Float, var vx: Float, var vy: Float, val life: Float, val size: Float, val color: Color,
            val glyph: String?, var rot: Float, val spin: Float, var age: Float = 0f)

    val particles = ArrayList<P>()
    private var debt = 0f

    fun burst(spec: EffectSpec, x: Float, y: Float, dir: Float = (-PI / 2).toFloat(), count: Int = spec.burst.toInt(), density: Float) {
        repeat(count) { spawn(spec, x, y, dir, Random.nextFloat() * 0.65f + 0.35f, density) }
    }

    fun emit(spec: EffectSpec, x: Float, y: Float, dt: Float, radius: Float = 0f, speedScale: Float = 0.35f, density: Float) {
        debt += spec.rate * dt
        while (debt >= 1f) {
            debt -= 1f
            val a = Random.nextFloat() * 2f * PI.toFloat()
            spawn(spec, x + cos(a) * radius, y + sin(a) * radius, a, speedScale, density)
        }
    }

    private fun spawn(spec: EffectSpec, x: Float, y: Float, dir: Float, speedScale: Float, density: Float) {
        if (particles.size >= 320) return
        val spread = spec.spread * PI.toFloat() / 180f
        val a = dir + (Random.nextFloat() - 0.5f) * spread
        val v = spec.speed * speedScale * density
        particles += P(
            x, y, cos(a) * v, sin(a) * v,
            life = spec.lifetime * (0.7f + Random.nextFloat() * 0.5f),
            size = spec.size * density * (0.6f + Random.nextFloat() * 0.7f),
            color = hexColor(spec.colors.randomOrNull() ?: "#FFFFFF"),
            glyph = if (spec.shape == ParticleShape.GLYPH) spec.glyphs.randomOrNull() else null,
            rot = Random.nextFloat() * 360f, spin = spec.spin * (Random.nextFloat() * 2f - 1f),
        )
    }

    fun step(dt: Float, gravity: Float, density: Float) {
        val it = particles.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.age += dt
            if (p.age >= p.life) { it.remove(); continue }
            p.vy += gravity * density * dt
            p.vx *= 1f - 1.2f * dt
            p.x += p.vx * dt; p.y += p.vy * dt
            p.rot += p.spin * dt
        }
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER }

    fun draw(scope: DrawScope, spec: EffectSpec) = with(scope) {
        val blend = if (spec.glow) BlendMode.Plus else BlendMode.SrcOver
        for (p in particles) {
            val t = p.age / p.life
            val alpha = (if (t < 0.15f) t / 0.15f else 1f - ((t - 0.15f) / 0.85f).pow(1.6f)).coerceIn(0f, 1f)
            when (spec.shape) {
                ParticleShape.GLYPH -> {
                    val g = p.glyph ?: continue
                    rotate(p.rot, Offset(p.x, p.y)) {
                        paint.textSize = p.size * 2f
                        paint.color = android.graphics.Color.argb((alpha * 255).toInt(), (p.color.red * 255).toInt(), (p.color.green * 255).toInt(), (p.color.blue * 255).toInt())
                        drawContext.canvas.nativeCanvas.drawText(g, p.x, p.y + p.size * 0.7f, paint)
                    }
                }
                ParticleShape.DOT -> {
                    val s = p.size * (1f - 0.5f * t)
                    drawCircle(p.color.copy(alpha = alpha * 0.35f), s, Offset(p.x, p.y), blendMode = blend)
                    drawCircle(p.color.copy(alpha = alpha), s / 2f, Offset(p.x, p.y), blendMode = blend)
                }
                else -> drawLine(
                    p.color.copy(alpha = alpha), Offset(p.x, p.y), Offset(p.x - p.vx * 0.04f, p.y - p.vy * 0.04f),
                    strokeWidth = (p.size * 0.6f).coerceAtLeast(3f), cap = StrokeCap.Round, blendMode = blend,
                )
            }
        }
    }
}

@Composable
private fun reduceMotion(): Boolean {
    val ctx = LocalContext.current
    return remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * A hit: the projectile flies from [from] to [to] (fractions of this box) leaving a trail,
 * then bursts with a flash. [onImpact] gets the shake strength (dp).
 */
@Composable
fun HitEffect(effectId: String, trigger: Int, from: Offset, to: Offset, damage: Int? = null, modifier: Modifier = Modifier.fillMaxSize(), onImpact: (Float) -> Unit = {}) {
    val spec = remember(effectId) { effectSpec(effectId) }
    val system = remember { ParticleSystem() }
    val density = LocalDensity.current.density
    val reduce = reduceMotion()
    var frame by remember { mutableLongStateOf(0L) }
    var flightT by remember { mutableStateOf(-1f) }
    var boltUntil by remember { mutableLongStateOf(0L) }
    val flash = remember { Animatable(0f) }
    val dmg = remember { Animatable(0f) }

    BoxWithConstraints(modifier) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val ax = from.x * w; val ay = from.y * h
        val bx = to.x * w; val by = to.y * h

        LaunchedEffect(trigger) {
            if (trigger == 0) return@LaunchedEffect
            if (reduce) {
                dmg.snapTo(1f); kotlinx.coroutines.delay(800); dmg.animateTo(0f, tween(200)); return@LaunchedEffect
            }
            dmg.snapTo(0f)
            var last = withFrameNanos { it }
            val start = last
            var impacted = false
            while (true) {
                val now = withFrameNanos { it }
                val dt = ((now - last) / 1e9f).coerceAtMost(0.05f)
                last = now
                val t = (now - start) / 1e9f / 0.38f
                if (t < 1f) {
                    flightT = t
                    val (px, py) = arc(ax, ay, bx, by, t)
                    if (spec.rate > 0f) system.emit(spec, px, py, dt, density = density)
                } else if (!impacted) {
                    impacted = true
                    flightT = -1f
                    system.burst(spec, bx, by, if (by < ay) (-PI / 2).toFloat() else (PI / 2).toFloat(), density = density)
                    if (spec.shape == ParticleShape.BOLT) boltUntil = now + 320_000_000L
                    onImpact(spec.shake)
                    launch { if (spec.flash.isNotEmpty()) { flash.snapTo(0.35f); flash.animateTo(0f, tween(350)) } }
                    launch { dmg.animateTo(1f, androidx.compose.animation.core.spring(0.6f)); kotlinx.coroutines.delay(600); dmg.animateTo(0f, tween(250)) }
                }
                system.step(dt, spec.gravity, density)
                frame = now
                if (impacted && system.particles.isEmpty() && now > boltUntil) break
            }
        }

        Canvas(Modifier.fillMaxSize()) {
            if (frame < 0L) return@Canvas   // reading frame redraws every tick
            if (flightT >= 0f && spec.projectile.isNotEmpty()) {
                val (px, py) = arc(ax, ay, bx, by, flightT)
                val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; textSize = 54f * density * (1f + flightT * 0.6f) }
                drawContext.canvas.nativeCanvas.drawText(spec.projectile, px, py + p.textSize * 0.35f, p)
            }
            if (frame < boltUntil) drawBolt(ax, ay, bx, by, hexColor(spec.colors.firstOrNull() ?: "#FFFFFF"), (frame / 33_000_000L).toInt())
            system.draw(this, spec)
        }
        damage?.let { d ->
            Text("-$d", fontSize = 44.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.offset { IntOffset((bx - 40 * density).roundToInt(), (by + (if (to.y < 0.5f) 50 else -110) * density).roundToInt()) }
                    .scale(0.4f + 0.6f * dmg.value).alpha(dmg.value))
        }
        if (flash.value > 0f) Box(Modifier.fillMaxSize().background(hexColor(spec.flash.ifEmpty { "#FFFFFF" }).copy(alpha = flash.value)))
    }
}

private fun arc(ax: Float, ay: Float, bx: Float, by: Float, t: Float): Pair<Float, Float> {
    val e = t * t * (3 - 2 * t)
    val mx = (ax + bx) / 2 + 90f
    val my = (ay + by) / 2
    val x = (1 - e) * (1 - e) * ax + 2 * (1 - e) * e * mx + e * e * bx
    val y = (1 - e) * (1 - e) * ay + 2 * (1 - e) * e * my + e * e * by
    return x to y
}

private fun DrawScope.drawBolt(ax: Float, ay: Float, bx: Float, by: Float, color: Color, seed: Int) {
    val r = Random(seed)
    var px = ax; var py = ay
    for (i in 1..12) {
        val t = i / 12f
        val nx = if (i == 12) bx else ax + (bx - ax) * t + (r.nextFloat() - 0.5f) * 70f
        val ny = ay + (by - ay) * t
        drawLine(color.copy(alpha = 0.35f), Offset(px, py), Offset(nx, ny), strokeWidth = 14f, cap = StrokeCap.Round, blendMode = BlendMode.Plus)
        drawLine(Color.White, Offset(px, py), Offset(nx, ny), strokeWidth = 3f, cap = StrokeCap.Round)
        px = nx; py = ny
    }
}

/** Idle particle aura around an avatar (au.* cosmetics). Draws nothing for "no aura". */
@Composable
fun Aura(auraId: String?, radiusDp: Float, modifier: Modifier = Modifier) {
    val spec = remember(auraId) { auraId?.let { auraSpec(it) } } ?: return
    if (reduceMotion()) return
    val system = remember(auraId) { ParticleSystem() }
    val density = LocalDensity.current.density
    var frame by remember { mutableLongStateOf(0L) }
    BoxWithConstraints(modifier) {
        val cx = constraints.maxWidth / 2f
        val cy = constraints.maxHeight / 2f
        LaunchedEffect(auraId) {
            var last = withFrameNanos { it }
            while (true) {
                val now = withFrameNanos { it }
                val dt = ((now - last) / 1e9f).coerceAtMost(0.05f)
                last = now
                system.emit(spec, cx, cy, dt, radiusDp * density, 1f, density)
                system.step(dt, spec.gravity, density)
                frame = now
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            if (frame < 0L) return@Canvas
            system.draw(this, spec)
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

@Suppress("unused")
private val unusedAlign = Alignment.Center
