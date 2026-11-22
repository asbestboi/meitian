package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.data.Sfx
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.lessonHearts

/** Hearts left in this lesson. Losing one breaks it (pop, sound, haptic). */
@Composable
fun HeartsBar(hearts: Int) {
    val total = lessonHearts().toInt()
    val haptic = LocalHapticFeedback.current
    val reduce = reduceMotion()
    var before by remember { mutableIntStateOf(hearts) }
    var broken by remember { mutableIntStateOf(-1) }   // the heart that's breaking right now
    val pop = remember { Animatable(0f) }
    LaunchedEffect(hearts) {
        if (hearts < before) {
            broken = hearts
            before = hearts
            Sfx.play(SoundId.HEART_LOST)
            // two thuds, like an error buzz
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            launch { delay(110); haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
            if (!reduce) {
                pop.snapTo(0f)
                pop.animateTo(1f, tween(650))
            } else delay(650)
            broken = -1
        } else before = hearts
    }
    Row(Modifier.clearAndSetSemantics { contentDescription = "$hearts of $total hearts left" }, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        repeat(total) { i ->
            Text(
                when { i < hearts -> "❤️"; i == broken -> "💔"; else -> "🤍" }, fontSize = 18.sp,
                modifier = if (i != broken || reduce) Modifier else Modifier.graphicsLayer {
                    val t = pop.value
                    val s = 1f + 0.9f * kotlin.math.sin(t * Math.PI).toFloat()
                    scaleX = s; scaleY = s
                    rotationZ = kotlin.math.sin(t * Math.PI * 6).toFloat() * 14f * (1 - t)
                },
            )
        }
    }
}

/** The lesson is over: start again from scratch. */
@Composable
fun OutOfHearts(onRetry: () -> Unit, onQuit: () -> Unit) {
    val reduce = reduceMotion()
    val scale = remember { Animatable(if (reduce) 1f else 0.3f) }
    LaunchedEffect(Unit) {
        Sfx.play(SoundId.OUT_OF_HEARTS)
        scale.animateTo(1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
    }
    Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.graphicsLayer { scaleX = scale.value; scaleY = scale.value }) { Text("💔", fontSize = 100.sp) }
        Text("out of hearts 💔", style = street(34.sp), color = Street.c.text, textAlign = TextAlign.Center)
        Text("加油 jiāyóu! Start over with ${lessonHearts()} fresh hearts. This try doesn't count.",
            color = Street.c.secondary, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.weight(1f))
        BigButton("Retry lesson", brush = Street.warm(), onClick = onRetry)
        BigButton("Not now", onClick = onQuit)
    }
}
