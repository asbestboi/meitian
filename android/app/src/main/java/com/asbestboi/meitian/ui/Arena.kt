package com.asbestboi.meitian.ui

import uniffi.meitian_core.SoundId
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.LocalNav
import com.asbestboi.meitian.data.Online
import uniffi.meitian_core.battleModes
import com.asbestboi.meitian.data.Catalog
import com.asbestboi.meitian.data.Cosmetic
import com.asbestboi.meitian.data.CosmeticKind
import com.asbestboi.meitian.data.Sfx
import kotlinx.coroutines.delay
import uniffi.meitian_core.ServerState
import kotlinx.coroutines.launch

@Composable
fun ArenaScreen() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val context = LocalContext.current
    val a = app.arena
    // battles need internet; ask the server whether it can be reached (null = still checking)
    var online by remember { mutableStateOf<ServerState?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(retry) { Online.init(context); online = null; online = Online.state() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenTitle("Arena")
        PlayerCardView(app.myCard(), coins = a.coins, picture = { MyPicture(74.dp) })
        Box(Modifier.clickable { nav.show { ArenaRoad { nav.close() } } }) { ArenaBadge(app.arenaTheme) }
        if (online == ServerState.OFFLINE || online == ServerState.OUTDATED) Column(Modifier.fillMaxWidth().card().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(if (online == ServerState.OUTDATED) "🛠️" else "📡", fontSize = 48.sp)
            Text(if (online == ServerState.OUTDATED) "the battle server is being updated" else "battles need internet", style = street(22.sp), color = Street.c.text)
            Text(if (online == ServerState.OUTDATED) "It doesn't know this version's battles yet. Come back in a little while." else "Lessons, stories and reviews work offline. Come back here when you're connected.", color = Street.c.secondary, textAlign = TextAlign.Center)
            BigButton("try again") { retry++ }
        } else {
            Row(Modifier.fillMaxWidth().block(Street.sky()).clickable { nav.show { OnlineHub { nav.close() } } }.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🌍", fontSize = 34.sp); HSpacer(14.dp)
                Column(Modifier.weight(1f)) {
                    Text("battle", style = street(26.sp), color = Color.White)
                    Text("Quick match anyone, battle friends, climb the leaderboards. iPhone + Android.", color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
                }
                val waiting = (Online.inbox?.challenges?.size ?: 0) + (Online.inbox?.requests?.toInt() ?: 0)
                if (waiting > 0) Pill("$waiting new", Color.White)
            }
            Row(Modifier.fillMaxWidth().block(Street.pink()).clickable { nav.show { OnlineHub(startAt = HubStart.Party) { nav.close() } } }.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🎉", fontSize = 34.sp); HSpacer(14.dp)
                Column(Modifier.weight(1f)) {
                    Text("party", style = street(26.sp), color = Color.White)
                    Text("Up to 4 friends in one game. Share a code, pick a mode, play.", color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
                }
            }
        }
        Row(Modifier.fillMaxWidth().card().clickable { nav.show { ShopScreen { nav.close() } } }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            GradientIcon("🛍️", Street.gold()); HSpacer(12.dp)
            Column {
                Text("shop", style = street(18.sp), color = Street.c.text)
                Text("Frames, titles, hits, auras, stickers", fontSize = 12.sp, color = Street.c.secondary)
            }
        }
        Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("games", fontWeight = FontWeight.Bold, color = Street.c.text)
            battleModes().forEach { m -> Row { Text(m.emoji, fontSize = 22.sp); HSpacer(10.dp); Column { Text(m.title.lowercase(), fontWeight = FontWeight.Bold, color = Street.c.text); Text(m.blurb, fontSize = 13.sp, color = Street.c.secondary) } } }
            Text("Win to earn 🪙 coins. Bigger wins and win streaks pay more.", color = Street.c.gold, fontWeight = FontWeight.Bold, fontSize = 13.sp)
        }
        val played = a.wins + a.losses + a.draws
        Column(Modifier.fillMaxWidth().card().padding(14.dp)) {
            Text("battle stats", fontWeight = FontWeight.Bold, color = Street.c.text)
            Gap(8.dp)
            Row { listOf("${a.wins}" to "Wins", "${a.losses}" to "Losses", "${if (played == 0) 0 else a.wins * 100 / played}%" to "Win rate").forEach { (v, l) -> Stat(v, l, Modifier.weight(1f)) } }
            Row { listOf("${a.streak}" to "Streak", "${a.bestStreak}" to "Best", (a.fastestMs?.let { "%.1fs".format(it / 1000.0) } ?: "–") to "Fastest").forEach { (v, l) -> Stat(v, l, Modifier.weight(1f)) } }
        }
        if (a.rivals.isNotEmpty()) Column(Modifier.fillMaxWidth().card().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("rivals", fontWeight = FontWeight.Bold, color = Street.c.text)
            a.rivals.values.sortedByDescending { it.last }.forEach { r ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Picture(r.id, r.name, r.picture, 36.dp); HSpacer(10.dp)
                    Text(r.name, fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f))
                    Text("${r.wins} – ${r.losses}", style = street(20.sp), color = if (r.wins >= r.losses) Street.c.jade else Street.c.red)
                }
            }
        }
        Gap(30.dp)
    }
}

@Composable
private fun Stat(v: String, l: String, modifier: Modifier) {
    Column(modifier.padding(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(v, style = street(24.sp), color = Street.c.text); Text(l, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
    }
}

// ---------- shop ----------

@Composable
fun ShopScreen(close: () -> Unit) {
    val app = LocalApp.current
    var kind by remember { mutableStateOf(CosmeticKind.Frame) }
    var confetti by remember { mutableIntStateOf(0) }
    var demoEffect by remember { mutableStateOf("fx.boom") }
    var demoTick by remember { mutableIntStateOf(0) }
    val shake = remember { Shake() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("shop", style = street(34.sp), color = Street.c.text, modifier = Modifier.weight(1f))
                Badge("🪙 ${app.arena.coins}"); HSpacer(8.dp); CloseButton(close)
            }
            if (kind == CosmeticKind.Effect) {
                // hit preview stage: tap any hit to see it fly
                Box(Modifier.fillMaxWidth().height(150.dp).offset { shake.offset(density) }.clip(RoundedCornerShape(24.dp))
                    .background(Street.night()).clickable { demoTick++ }) {
                    MyPicture(48.dp, Modifier.align(Alignment.CenterStart).offset(x = 24.dp))
                    Text("🎯", fontSize = 40.sp, modifier = Modifier.align(Alignment.CenterEnd).padding(end = 24.dp))
                    HitEffect(demoEffect, demoTick, androidx.compose.ui.geometry.Offset(0.14f, 0.55f), androidx.compose.ui.geometry.Offset(0.86f, 0.5f), damage = 22) {
                        scope.launch { shake.hit(it) }
                    }
                    Text("tap a hit to try it", fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp))
                }
            } else {
                PlayerCardView(app.myCard().copy(frame = app.arena.frame, title = app.arena.title, sticker = app.arena.sticker, aura = app.arena.aura), compact = true, picture = { MyPicture(54.dp) })
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                CosmeticKind.entries.forEach { k ->
                    Box(Modifier.clip(RoundedCornerShape(50)).background(if (kind == k) Street.c.ink else Street.c.card).clickable { kind = k }.padding(horizontal = 14.dp, vertical = 8.dp),
                        contentAlignment = Alignment.Center) { Text(k.label.lowercase(), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (kind == k) Street.c.paper else Street.c.text) }
                }
            }
            LazyVerticalGrid(GridCells.Fixed(2), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(Catalog.items(kind, app.settings.swears), key = { it.id }) { item ->
                    ShopTile(item, onTap = { if (item.kind == CosmeticKind.Effect) { demoEffect = item.id; demoTick++; scope.launch { delay(380); Sfx.playHit(item.id) } } }) { confetti++ }
                }
            }
        }
        Confetti(confetti, sound = false)
    }
}

@Composable
private fun ShopTile(item: Cosmetic, onTap: () -> Unit = {}, bought: () -> Unit) {
    val app = LocalApp.current
    val owned = item.id in app.arena.owned
    val equipped = app.equipped(item.kind) == item.id
    val affordable = app.arena.coins >= item.price
    Column(
        Modifier.fillMaxWidth().streetCard(Street.c.card, if (equipped) Street.c.jade else Street.c.ink, shadow = 4.dp).clickable {
            onTap()
            if (owned) app.equip(item) else if (app.buy(item)) { Sfx.play(SoundId.PURCHASE); bought() } else Sfx.play(SoundId.WRONG)
        }.padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.height(66.dp), contentAlignment = Alignment.Center) {
            when (item.kind) {
                CosmeticKind.Frame -> Box(Modifier.size(96.dp, 56.dp).clip(RoundedCornerShape(12.dp)).background(Catalog.frame(item.id)).border(2.dp, Street.c.ink, RoundedCornerShape(12.dp)))
                CosmeticKind.Title -> Text(item.symbol, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
                CosmeticKind.Aura -> Box(Modifier.size(110.dp, 66.dp), contentAlignment = Alignment.Center) {
                    Aura(item.id, 22f, Modifier.fillMaxSize())
                    if (item.symbol.isEmpty()) Text("🚫", fontSize = 34.sp) else MyPicture(38.dp)
                }
                CosmeticKind.Sticker -> if (item.symbol.isEmpty()) Text("🚫", fontSize = 32.sp) else Text(item.symbol, fontSize = 40.sp, modifier = Modifier.rotate(-8f))
                else -> Text(item.symbol, fontSize = 44.sp)
            }
        }
        Text(item.name, fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
        Text(when { equipped -> "✓ EQUIPPED"; owned -> "EQUIP"; else -> "🪙 ${item.price}" }, fontWeight = FontWeight.Bold, fontSize = 12.sp,
            color = when { equipped -> Street.c.jade; owned -> Street.c.sky; affordable -> Street.c.text; else -> Street.c.secondary })
    }
}
