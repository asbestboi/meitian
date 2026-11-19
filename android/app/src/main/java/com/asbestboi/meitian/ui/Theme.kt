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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.scale
import androidx.compose.animation.core.animateFloatAsState
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

/** "Quiet base, loud accents" (shared with iOS): off-white / near-black surfaces, soft cards without
 *  outlines, big hanzi, bold type, one hypercolor accent (acid lime, hot pink) per surface. */
data class StreetColors(
    val paper: Color,
    val card: Color,
    val ink: Color,
    val text: Color,
    val secondary: Color,
    val red: Color,
    val gold: Color,
    val jade: Color,
    val sky: Color = Color(0xFF3D7AFF),
    val plum: Color = Color(0xFF945CFF),
    val pink: Color = Color(0xFFFF3DA8),
    val lime: Color = Color(0xFFC6FF3D),
)

private val Light = StreetColors(
    paper = Color(0xFFF6F5F2), card = Color(0xFFFFFFFF), ink = Color(0xFF0B0B0C), text = Color(0xFF0B0B0C),
    secondary = Color(0xFF7A7873), red = Color(0xFFF2382B), gold = Color(0xFFED8F00), jade = Color(0xFF17914A),
    lime = Color(0xFF8CC414),
)
private val Dark = StreetColors(
    paper = Color(0xFF0B0B0C), card = Color(0xFF18181B), ink = Color(0xFFF2F2F0), text = Color(0xFFF2F2F0),
    secondary = Color(0xFF9A9893), red = Color(0xFFFF5C4A), gold = Color(0xFFFFC726), jade = Color(0xFF42DE85),
)

val LocalStreet = staticCompositionLocalOf { Light }

object Street {
    val c: StreetColors @Composable get() = LocalStreet.current

    fun warm() = Brush.linearGradient(listOf(Color(0xFFFF6B4D), Color(0xFFFF2E78)))
    fun gold() = Brush.linearGradient(listOf(Color(0xFFFFCC33), Color(0xFFFF851A)))
    fun jade() = Brush.linearGradient(listOf(Color(0xFF4DE08C), Color(0xFF0DA87A)))
    fun sky() = Brush.linearGradient(listOf(Color(0xFF5499FF), Color(0xFF6B52FF)))
    fun pink() = Brush.linearGradient(listOf(Color(0xFFFF6BBF), Color(0xFFB34DFF)))
    fun ink() = Brush.linearGradient(listOf(Color(0xFF1A1A1F), Color(0xFF08080A)))
    fun night() = ink()
    fun lime() = Brush.linearGradient(listOf(Color(0xFFDBFF5C), Color(0xFF8CF273)))
    fun purple() = Brush.linearGradient(listOf(Color(0xFFB87AFF), Color(0xFF7347F2)))
    fun chrome() = Brush.linearGradient(listOf(Color(0xFFCCF2FF), Color(0xFFF9CCFF), Color(0xFFD9FFCC), Color(0xFFCCDBFF)))

    fun level(level: Int): Brush = when (level) {
        1 -> jade(); 2 -> sky(); 3 -> purple(); 4 -> warm(); 5 -> gold(); else -> pink()
    }

    @Composable
    fun levelColor(level: Int): Color = when (level) {
        1 -> c.jade; 2 -> c.sky; 3 -> c.plum; 4 -> c.red; 5 -> c.gold; else -> c.pink
    }

    val radius = 24.dp
}

/** Display headline: heavy weight, slightly tight tracking. */
fun street(size: TextUnit) = TextStyle(fontWeight = FontWeight.ExtraBold, fontSize = size, letterSpacing = (-0.015).sp * size.value)

@Composable
fun MeitianTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val colors = if (dark) Dark else Light
    val scheme = if (dark) darkColorScheme(primary = colors.ink, background = colors.paper, surface = colors.card)
    else lightColorScheme(primary = colors.ink, background = colors.paper, surface = colors.card)
    CompositionLocalProvider(LocalStreet provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** Soft card: big radius, one gentle shadow, no outline. (`ink` / `shadow` kept for call sites;
 *  a non-default ink color marks a selected card with a thin ring.) */
fun Modifier.streetCard(card: Color, ink: Color, radius: Dp = Street.radius, shadow: Dp = 5.dp): Modifier =
    this
        .shadow(if (shadow > 0.dp) 6.dp else 0.dp, RoundedCornerShape(radius), ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.10f))
        .clip(RoundedCornerShape(radius))
        .background(card)

@Composable
fun Modifier.card(): Modifier = streetCard(Street.c.card, Street.c.ink)

/** Selected-state ring for cards (equipped item, chosen option). */
fun Modifier.ring(on: Boolean, color: Color, radius: Dp = Street.radius): Modifier =
    if (on) this.border(2.dp, color, RoundedCornerShape(radius)) else this

/** Hero block: big colored surface with soft depth. */
@Composable
fun Modifier.block(brush: Brush): Modifier =
    this
        .shadow(10.dp, RoundedCornerShape(28.dp), ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.16f))
        .clip(RoundedCornerShape(28.dp))
        .background(brush)

/** Big call-to-action: full-width capsule. Default is ink (black / off-white); pass a brush for color. */
@Composable
fun BigButton(
    title: String,
    modifier: Modifier = Modifier,
    brush: Brush? = null,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val haptic = LocalHapticFeedback.current
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy), label = "press")
    val fill = brush ?: SolidColor(Street.c.ink)
    Box(
        modifier
            .fillMaxWidth()
            .scale(scale)
            .shadow(if (enabled) 8.dp else 0.dp, RoundedCornerShape(50), ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.14f))
            .clip(RoundedCornerShape(50))
            .background(fill, alpha = if (enabled) 1f else 0.35f)
            .clickable(source, null, enabled) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                onClick()
            }
            .padding(vertical = 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title.lowercase(), color = if (brush == null) Street.c.paper else Color.White, fontWeight = FontWeight.Bold, fontSize = 19.sp)
    }
}

/** Small tag: tinted capsule, no outline. */
@Composable
fun Pill(text: String, color: Color, tilt: Float = 0f, modifier: Modifier = Modifier) {
    Box(
        modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(text.lowercase(), color = color, fontWeight = FontWeight.Bold, fontSize = 12.sp)
    }
}

/** Removed from the look; kept so old call sites compile. */
@Composable
fun Tape(modifier: Modifier = Modifier, angle: Float = -6f) {}

/** Removed from the look; kept so old call sites compile. */
@Composable
fun Grain(modifier: Modifier = Modifier, alpha: Float = 0.06f) {}

@Composable
fun SectionTitle(text: String) {
    Text(text.lowercase(), color = Street.c.secondary, fontWeight = FontWeight.Bold, fontSize = 15.sp,
        modifier = Modifier.padding(start = 4.dp, top = 6.dp, bottom = 4.dp))
}

@Composable
fun HSpacer(w: Dp) = Spacer(Modifier.width(w))

@Composable
fun RowCenter(content: @Composable () -> Unit) = Row(verticalAlignment = Alignment.CenterVertically) { content() }
