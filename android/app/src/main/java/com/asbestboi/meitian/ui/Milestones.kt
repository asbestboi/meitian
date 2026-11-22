package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Sfx
import uniffi.meitian_core.milestoneAt

/** Today: XP earned today on its way to the next milestone. There's always a next one. */
@Composable
fun MilestoneCard() {
    val app = LocalApp.current
    val p = app.milestoneProgress
    val xpToday = app.today.xp.coerceAtLeast(0)
    Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("today's milestones ✦", style = street(18.sp), color = Street.c.text, modifier = Modifier.weight(1f))
            Text("$xpToday XP today", fontWeight = FontWeight.ExtraBold, color = Street.c.gold)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(p.next.emoji, fontSize = 28.sp,
                modifier = Modifier.clip(RoundedCornerShape(16.dp)).background(Street.c.gold.copy(alpha = 0.16f)).padding(10.dp))
            HSpacer(12.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row {
                    Text(p.next.title, fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f))
                    Text("$xpToday / ${p.next.xp}", fontSize = 12.sp, color = Street.c.secondary)
                }
                Box(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(50)).background(Street.c.gold.copy(alpha = 0.15f))) {
                    Box(Modifier.fillMaxWidth(p.progress.toFloat().coerceIn(0.04f, 1f)).height(10.dp).clip(RoundedCornerShape(50)).background(Street.gold()))
                }
                Text("+${p.next.bonus} bonus XP when you get there", fontSize = 12.sp, color = Street.c.secondary)
            }
        }
        if (p.reached > 0u) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (1..p.reached.toInt()).forEach { i ->
                    val m = milestoneAt(i.toUInt())
                    Text("${m.emoji} ${m.title}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.text,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.c.gold.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 5.dp))
                }
            }
        }
    }
}

/** Pops up when a milestone is reached, one at a time (waits until no lesson/game is open). */
@Composable
fun MilestoneCelebration() {
    val app = LocalApp.current
    val m = app.milestoneQueue.firstOrNull()
    var confetti by remember { mutableIntStateOf(0) }
    if (m != null) {
        LaunchedEffect(m.index) { confetti++; Sfx.play(SoundId.MILESTONE) }
        val dismiss = { if (app.milestoneQueue.isNotEmpty()) app.milestoneQueue.removeAt(0) }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f))
            .clickable(remember { MutableInteractionSource() }, null) { dismiss() }, contentAlignment = Alignment.Center) {
            Column(
                Modifier.padding(24.dp).widthIn(max = 340.dp).clip(RoundedCornerShape(32.dp)).background(Street.c.card)
                    .clickable(remember { MutableInteractionSource() }, null) {}.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(m.emoji, fontSize = 72.sp)
                Text("milestone ${m.index}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
                Text(m.title, style = street(30.sp), color = Street.c.text, textAlign = TextAlign.Center)
                Text("${m.xp} XP today ✦ +${m.bonus} bonus XP", fontWeight = FontWeight.SemiBold, color = Street.c.gold)
                val next = milestoneAt(m.index + 1u)
                Text("next up: ${next.emoji} ${next.title} at ${next.xp} XP", fontSize = 13.sp, color = Street.c.secondary, textAlign = TextAlign.Center)
                Gap(6.dp)
                BigButton("keep going →", onClick = dismiss)
            }
        }
    }
    Confetti(confetti, sound = false)
}
