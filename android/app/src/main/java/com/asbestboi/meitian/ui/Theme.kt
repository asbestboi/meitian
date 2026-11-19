package com.asbestboi.meitian.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The "street" look shared with iOS: concrete paper, ink outlines, hard offset shadows, loud colors. */
data class StreetColors(
    val paper: Color,
    val card: Color,
    val ink: Color,
    val text: Color,
    val secondary: Color,
    val red: Color,
    val gold: Color,
    val jade: Color,
    val sky: Color = Color(0xFF3370FF),
    val plum: Color = Color(0xFF9E54FF),
    val pink: Color = Color(0xFFFF338C),
)

private val Light = StreetColors(
    paper = Color(0xFFE8E4DB), card = Color(0xFFF9F6F0), ink = Color(0xFF151515), text = Color(0xFF151515),
    secondary = Color(0xFF6B6760), red = Color(0xFFF53326), gold = Color(0xFFED8F00), jade = Color(0xFF178F4A),
)
private val Dark = StreetColors(
    paper = Color(0xFF111111), card = Color(0xFF1F1F1F), ink = Color(0xFFEDE9E0), text = Color(0xFFF2EFE6),
    secondary = Color(0xFFA29E96), red = Color(0xFFFF5C4A), gold = Color(0xFFFFC726), jade = Color(0xFF42DE85),
)

val LocalStreet = staticCompositionLocalOf { Light }

object Street {
    val c: StreetColors @Composable get() = LocalStreet.current

    fun warm() = Brush.linearGradient(listOf(Color(0xFFFF5C33), Color(0xFFE01C29)))
    fun gold() = Brush.linearGradient(listOf(Color(0xFFFFA81A), Color(0xFFEB6B00)))
    fun jade() = Brush.linearGradient(listOf(Color(0xFF29C266), Color(0xFF0D8545)))
    fun sky() = Brush.linearGradient(listOf(Color(0xFF4285FF), Color(0xFF2B3BDB)))
    fun pink() = Brush.linearGradient(listOf(Color(0xFFFF5C9E), Color(0xFFDB126E)))
    fun ink() = Brush.linearGradient(listOf(Color(0xFF383838), Color(0xFF0D0D0D)))
    fun purple() = Brush.linearGradient(listOf(Color(0xFFB873FF), Color(0xFF7A38EB)))

    fun level(level: Int): Brush = when (level) {
        1 -> jade(); 2 -> sky(); 3 -> purple(); 5 -> pink(); else -> warm()
    }

    @Composable
    fun levelColor(level: Int): Color = when (level) {
        1 -> c.jade; 2 -> c.sky; 3 -> c.plum; 5 -> c.pink; else -> c.red
    }

    val radius = 14.dp
}

/** Condensed-feel headline: black weight, tight tracking. */
fun street(size: TextUnit) = TextStyle(fontWeight = FontWeight.Black, fontSize = size, letterSpacing = (-0.02).sp * size.value)

@Composable
fun MeitianTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val colors = if (dark) Dark else Light
    val scheme = if (dark) darkColorScheme(primary = colors.red, background = colors.paper, surface = colors.card)
    else lightColorScheme(primary = colors.red, background = colors.paper, surface = colors.card)
    CompositionLocalProvider(LocalStreet provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** Card with ink outline and hard offset shadow. */
fun Modifier.streetCard(card: Color, ink: Color, radius: Dp = Street.radius, shadow: Dp = 5.dp): Modifier =
    this
        .padding(end = shadow, bottom = shadow)
        .drawBehind {
            val r = radius.toPx()
            val s = shadow.toPx()
            drawRoundRect(ink, topLeft = Offset(s * 0.8f, s), size = size, cornerRadius = CornerRadius(r))
        }
        .clip(RoundedCornerShape(radius))
        .background(card)
        .border(2.5.dp, ink, RoundedCornerShape(radius))

@Composable
fun Modifier.card(): Modifier = streetCard(Street.c.card, Street.c.ink)

@Composable
fun Modifier.block(brush: Brush): Modifier {
    val ink = Street.c.ink
    return this
        .padding(end = 6.dp, bottom = 6.dp)
        .drawBehind {
            drawRoundRect(ink, topLeft = Offset(5.dp.toPx(), 6.dp.toPx()), size = size, cornerRadius = CornerRadius(18.dp.toPx()))
        }
        .clip(RoundedCornerShape(18.dp))
        .background(brush)
        .border(3.dp, ink, RoundedCornerShape(18.dp))
}

/** Big chunky button that gets pushed down into its ink shadow. */
@Composable
fun BigButton(
    title: String,
    modifier: Modifier = Modifier,
    brush: Brush = Street.warm(),
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val ink = Street.c.ink
    val haptic = LocalHapticFeedback.current
    val dy by animateDpAsState(if (pressed) 4.dp else 0.dp, spring(dampingRatio = Spring.DampingRatioMediumBouncy), label = "press")
    Box(
        modifier
            .fillMaxWidth()
            .padding(bottom = 5.dp)
            .drawBehind {
                drawRoundRect(ink, topLeft = Offset(0f, 5.dp.toPx()), size = size, cornerRadius = CornerRadius(Street.radius.toPx()))
            }
            .offset(y = dy)
            .clip(RoundedCornerShape(Street.radius))
            .background(brush, alpha = if (enabled) 1f else 0.4f)
            .border(3.dp, ink, RoundedCornerShape(Street.radius))
            .clickable(source, null, enabled) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                onClick()
            }
            .padding(vertical = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title.uppercase(), color = Color.White, style = street(20.sp), letterSpacing = 1.sp)
    }
}

/** Sticker tag: solid color, ink outline, slightly crooked. */
@Composable
fun Pill(text: String, color: Color, tilt: Float = -2f, modifier: Modifier = Modifier) {
    Box(
        modifier
            .rotate(tilt)
            .clip(RoundedCornerShape(6.dp))
            .background(color)
            .border(1.5.dp, Street.c.ink, RoundedCornerShape(6.dp))
            .padding(horizontal = 9.dp, vertical = 3.dp),
    ) {
        Text(text.uppercase(), color = Color.White, fontWeight = FontWeight.Black, fontSize = 12.sp)
    }
}

/** Masking tape strip. */
@Composable
fun Tape(modifier: Modifier = Modifier, angle: Float = -6f) {
    Box(modifier.rotate(angle).width(70.dp).padding(0.dp)) {
        Canvas(Modifier.width(70.dp).padding(0.dp).then(Modifier)) {
            drawRect(Color(0xD9F5EBB3), size = Size(size.width, 22.dp.toPx()))
        }
    }
}

/** Printed-paper grain, drawn from a fixed seed. */
@Composable
fun Grain(modifier: Modifier = Modifier, alpha: Float = 0.06f) {
    Canvas(modifier) {
        var seed = 0x9E3779B97F4A7C15uL
        fun rnd(): Float {
            seed = seed * 6364136223846793005uL + 1442695040888963407uL
            return ((seed shr 40).toLong() and 0xFFFFFF).toFloat() / 0xFFFFFF.toFloat()
        }
        val count = (size.width * size.height / 250f).toInt().coerceAtMost(40_000)
        repeat(count) {
            val x = rnd() * size.width
            val y = rnd() * size.height
            val s = 1f + rnd() * 2.5f
            drawRect(if (rnd() > 0.45f) Color.Black else Color.White, Offset(x, y), Size(s, s), alpha = alpha)
        }
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(text.uppercase(), color = Street.c.secondary, fontWeight = FontWeight.Black, fontSize = 13.sp,
        modifier = Modifier.padding(start = 4.dp, top = 6.dp, bottom = 4.dp))
}

@Composable
fun HSpacer(w: Dp) = Spacer(Modifier.width(w))

@Composable
fun RowCenter(content: @Composable () -> Unit) = Row(verticalAlignment = Alignment.CenterVertically) { content() }
