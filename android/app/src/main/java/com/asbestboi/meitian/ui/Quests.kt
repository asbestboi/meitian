package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Sfx
import uniffi.meitian_core.QuestStatus
import uniffi.meitian_core.questsAllDoneBonus
import uniffi.meitian_core.streakFreezeMax
import uniffi.meitian_core.streakFreezePrice

private val Sky = Color(0xFF3D7AFF)

/** Today: three daily quests that pay Arena coins, plus streak freezes to spend them on. */
@Composable
fun QuestCard() {
    val app = LocalApp.current
    Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        app.freezeNotice?.let { saved ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Sky.copy(alpha = 0.15f)).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("🧊", fontSize = 22.sp); HSpacer(10.dp)
                Text("A streak freeze saved your $saved-day streak!", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f))
                Text("✕", color = Street.c.secondary, modifier = Modifier.clickable { app.freezeNotice = null }.padding(6.dp))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("daily quests ✦", style = street(18.sp), color = Street.c.text, modifier = Modifier.weight(1f))
            Text("🪙 ${app.arena.coins}", fontWeight = FontWeight.ExtraBold, color = Street.c.gold)
        }
        app.quests.forEach { QuestRow(it) }
        Text("finish all three for +${questsAllDoneBonus()} bonus coins", fontSize = 12.sp, color = Street.c.secondary)
        HorizontalDivider(color = Street.c.ink.copy(alpha = 0.12f))
        val price = streakFreezePrice().toInt()
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("🧊", fontSize = 22.sp); HSpacer(10.dp)
            Column(Modifier.weight(1f)) {
                Text("streak freezes: ${app.profile.freezes}/${streakFreezeMax()}", fontWeight = FontWeight.Bold, color = Street.c.text)
                Text("covers a missed day so your streak survives", fontSize = 12.sp, color = Street.c.secondary)
            }
            if (app.canHoldMoreFreezes) {
                val affordable = app.arena.coins >= price
                Text("🪙 $price", fontWeight = FontWeight.ExtraBold, fontSize = 13.sp,
                    color = if (affordable) Street.c.text else Street.c.secondary,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Sky.copy(alpha = if (affordable) 0.25f else 0.08f))
                        .clickable(enabled = affordable) { if (app.buyFreeze()) Sfx.play(SoundId.PURCHASE) }
                        .padding(horizontal = 12.dp, vertical = 7.dp))
            }
        }
    }
}

@Composable
private fun QuestRow(q: QuestStatus) {
    val app = LocalApp.current
    val claimed = app.isClaimed(q.quest)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(q.quest.emoji, fontSize = 22.sp,
            modifier = Modifier.clip(RoundedCornerShape(14.dp)).background(Sky.copy(alpha = 0.14f)).padding(9.dp))
        HSpacer(12.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(q.quest.title, fontWeight = FontWeight.Bold, color = if (claimed) Street.c.secondary else Street.c.text,
                textDecoration = if (claimed) TextDecoration.LineThrough else null)
            Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)).background(Sky.copy(alpha = 0.15f))) {
                val f = (q.progress.toFloat() / q.quest.target.toFloat().coerceAtLeast(1f)).coerceIn(0.04f, 1f)
                Box(Modifier.fillMaxWidth(f).height(8.dp).clip(RoundedCornerShape(50)).background(if (q.done) Street.c.jade else Sky))
            }
        }
        HSpacer(10.dp)
        if (q.done && !claimed) {
            Text("+${q.quest.reward}", fontWeight = FontWeight.ExtraBold, color = Color.Black,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.c.gold)
                    .clickable { if (app.claimQuest(q) > 0) Sfx.play(SoundId.COIN) }.padding(horizontal = 12.dp, vertical = 8.dp))
        } else {
            Text(if (claimed) "✓" else "${q.progress}/${q.quest.target}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
        }
    }
}
