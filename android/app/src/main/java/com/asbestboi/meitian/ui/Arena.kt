package com.asbestboi.meitian.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.LocalNav
import com.asbestboi.meitian.data.BattleLink
import com.asbestboi.meitian.data.Catalog
import com.asbestboi.meitian.data.Cosmetic
import com.asbestboi.meitian.data.CosmeticKind
import com.asbestboi.meitian.data.DuelQR
import com.asbestboi.meitian.data.Match
import com.asbestboi.meitian.data.Mode
import com.asbestboi.meitian.data.Question
import com.asbestboi.meitian.data.Sfx
import com.asbestboi.meitian.data.WireQ
import com.asbestboi.meitian.data.Words
import com.google.zxing.BarcodeFormat
import com.journeyapps.barcodescanner.BarcodeEncoder
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.CoreWord
import uniffi.meitian_core.battleQuestions
import uniffi.meitian_core.duelDamage

@Composable
fun ArenaScreen() {
    val app = LocalApp.current
    val nav = LocalNav.current
    val a = app.arena
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenTitle("Arena")
        PlayerCardView(app.myCard(), coins = a.coins)
        Row(Modifier.fillMaxWidth().block(Street.warm()).clickable { nav.show { OnlineBattle { nav.close() } } }.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("📷", fontSize = 34.sp); HSpacer(14.dp)
            Column(Modifier.weight(1f)) {
                Text("battle a friend", style = street(26.sp), color = Color.White)
                Text("Scan each other's QR code. Works offline, no internet needed. (Android ↔ Android)", color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f).card().clickable { nav.show { LocalDuel { nav.close() } } }.padding(14.dp)) {
                GradientIcon("📱", Street.sky()); Gap(8.dp)
                Text("same phone", style = street(18.sp), color = Street.c.text)
                Text("Split screen duel on one phone", fontSize = 12.sp, color = Street.c.secondary)
            }
            Column(Modifier.weight(1f).card().clickable { nav.show { ShopScreen { nav.close() } } }.padding(14.dp)) {
                GradientIcon("🛍️", Street.gold()); Gap(8.dp)
                Text("shop", style = street(18.sp), color = Street.c.text)
                Text("Avatars, frames, titles, hits, stickers", fontSize = 12.sp, color = Street.c.secondary)
            }
        }
        Column(Modifier.fillMaxWidth().card().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("games", fontWeight = FontWeight.Bold, color = Street.c.text)
            Mode.entries.forEach { m -> Row { Text(m.emoji, fontSize = 22.sp); HSpacer(10.dp); Column { Text(m.title.lowercase(), fontWeight = FontWeight.Bold, color = Street.c.text); Text(m.blurb, fontSize = 13.sp, color = Street.c.secondary) } } }
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
                    Text(Catalog[r.avatar]?.symbol ?: "🐣", fontSize = 26.sp); HSpacer(10.dp)
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
    var kind by remember { mutableStateOf(CosmeticKind.Avatar) }
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
                    Text(app.myCard().avatarSymbol, fontSize = 40.sp, modifier = Modifier.align(Alignment.CenterStart).padding(start = 24.dp))
                    Text("🎯", fontSize = 40.sp, modifier = Modifier.align(Alignment.CenterEnd).padding(end = 24.dp))
                    HitEffect(demoEffect, demoTick, androidx.compose.ui.geometry.Offset(0.14f, 0.55f), androidx.compose.ui.geometry.Offset(0.86f, 0.5f), damage = 22) {
                        scope.launch { shake.hit(it) }
                    }
                    Text("tap a hit to try it", fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp))
                }
            } else {
                PlayerCardView(app.myCard().copy(avatar = app.arena.avatar, frame = app.arena.frame, title = app.arena.title, sticker = app.arena.sticker, aura = app.arena.aura), compact = true)
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                CosmeticKind.entries.forEach { k ->
                    Box(Modifier.clip(RoundedCornerShape(50)).background(if (kind == k) Street.c.ink else Street.c.card).clickable { kind = k }.padding(horizontal = 14.dp, vertical = 8.dp),
                        contentAlignment = Alignment.Center) { Text(k.label.lowercase(), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (kind == k) Street.c.paper else Street.c.text) }
                }
            }
            LazyVerticalGrid(GridCells.Fixed(2), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(Catalog.items(kind, app.settings.swears), key = { it.id }) { item ->
                    ShopTile(item, onTap = { if (item.kind == CosmeticKind.Effect) { demoEffect = item.id; demoTick++ } }) { confetti++ }
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
            if (owned) app.equip(item) else if (app.buy(item)) { Sfx.play(Sfx.Sound.Coin); bought() } else Sfx.play(Sfx.Sound.Wrong)
        }.padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.height(66.dp), contentAlignment = Alignment.Center) {
            when (item.kind) {
                CosmeticKind.Frame -> Box(Modifier.size(96.dp, 56.dp).clip(RoundedCornerShape(12.dp)).background(Catalog.frame(item.id)).border(2.dp, Street.c.ink, RoundedCornerShape(12.dp)))
                CosmeticKind.Title -> Text(item.symbol, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
                CosmeticKind.Aura -> Box(Modifier.size(110.dp, 66.dp), contentAlignment = Alignment.Center) {
                    Aura(item.id, 22f, Modifier.fillMaxSize())
                    Text(if (item.symbol.isEmpty()) "🚫" else "🐣", fontSize = 34.sp)
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

// ---------- shared battle bits ----------

@Composable
fun HealthBar(name: String, avatar: String, hp: Int, color: Color, aura: String? = null) {
    Row(Modifier.fillMaxWidth().card().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(contentAlignment = Alignment.Center) {
            Aura(aura, 20f, Modifier.size(80.dp))
            Text(avatar, fontSize = 28.sp)
        }
        HSpacer(4.dp)
        Column {
            Row { Text(name, fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f), maxLines = 1); Text("$hp HP", fontWeight = FontWeight.Bold, color = if (hp <= 30) Street.c.red else Street.c.text) }
            LinearProgressIndicator(progress = { hp / 100f }, modifier = Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(6.dp)), color = if (hp <= 30) Street.c.red else color)
        }
    }
}

// ---------- same-phone duel ----------

@Composable
fun LocalDuel(close: () -> Unit) {
    val app = LocalApp.current
    var started by remember { mutableStateOf(false) }
    val questions = remember { mutableStateListOf<Question>() }
    var index by remember { mutableIntStateOf(0) }
    val hp = remember { mutableStateListOf(100, 100) }
    val picks = remember { mutableStateListOf<CoreWord?>(null, null) }
    val locked = remember { mutableStateListOf(false, false) }
    var resolved by remember { mutableStateOf(false) }
    var roundWinner by remember { mutableStateOf<Int?>(null) }
    var lastDamage by remember { mutableIntStateOf(0) }
    var winner by remember { mutableStateOf<Int?>(null) }
    var shownAt by remember { mutableLongStateOf(0L) }
    var confetti by remember { mutableIntStateOf(0) }
    var roundKey by remember { mutableIntStateOf(0) }
    val names = listOf("Player 1", "Player 2"); val avatars = listOf("🐼", "🐯")

    fun next(i: Int) { index = i % questions.size.coerceAtLeast(1); picks[0] = null; picks[1] = null; locked[0] = false; locked[1] = false; roundWinner = null; resolved = false; shownAt = System.currentTimeMillis() }
    fun start() {
        var pool = Words.all.filter { it.level.toInt() <= app.currentLevel }.map { it.id }
        if (app.settings.swears) pool = pool + Words.swears.map { it.id }
        questions.clear(); questions += battleQuestions(pool, 60u).mapNotNull { WireQ(it.wordId, it.kind.toInt(), it.optionIds).question() }
        hp[0] = 100; hp[1] = 100; winner = null; next(0); started = true
    }
    fun pick(p: Int, o: CoreWord) {
        if (resolved || picks[p] != null || locked[p]) return
        picks[p] = o
        if (o.id == questions[index].word.id) {
            val dmg = duelDamage((System.currentTimeMillis() - shownAt).toUInt()).toInt()
            lastDamage = dmg; roundWinner = p; resolved = true; hp[1 - p] = (hp[1 - p] - dmg).coerceAtLeast(0); Sfx.play(Sfx.Sound.Hit)
        } else { locked[p] = true; Sfx.play(Sfx.Sound.Wrong); if (locked[0] && locked[1]) resolved = true }
        if (resolved) roundKey++
    }
    LaunchedEffect(roundKey) {
        if (roundKey == 0) return@LaunchedEffect
        delay(1300)
        if (hp.contains(0)) { winner = if (hp[0] == 0) 1 else 0; confetti++ } else next(index + 1)
    }

    Box(Modifier.fillMaxSize()) {
        when {
            !started -> Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(Modifier.fillMaxWidth()) { CloseButton(close) }
                Spacer(Modifier.weight(1f))
                Text("🐼 vs 🐯", fontSize = 60.sp)
                Text("same‑phone duel", style = street(36.sp), color = Street.c.text)
                Text("Lay the phone flat between you. Each player gets their own half. Same question for both: first right answer hits, a wrong answer locks you out for the round.",
                    color = Street.c.secondary, textAlign = TextAlign.Center)
                Text("Friendly match: no coins. Battle on two phones to earn 🪙.", color = Street.c.gold, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Spacer(Modifier.weight(1f))
                BigButton("Start") { start() }
            }
            winner != null -> Column(Modifier.fillMaxSize().padding(20.dp).rotate(if (winner == 1) 180f else 0f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Spacer(Modifier.weight(1f))
                Text(avatars[winner!!], fontSize = 90.sp)
                Text("${names[winner!!].lowercase()} WINS!", style = street(40.sp), color = Street.c.text)
                Text("胜利 shènglì · victory", color = Street.c.secondary)
                Spacer(Modifier.weight(1f))
                BigButton("Rematch") { start() }
                Text("Done", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.clickable(onClick = close).padding(8.dp))
            }
            else -> Column(Modifier.fillMaxSize().padding(horizontal = 12.dp)) {
                listOf(1, 0).forEach { p ->
                    if (p == 0) Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        CloseButton(close); Spacer(Modifier.weight(1f))
                        Text(roundWinner?.let { "${names[it]} hits! -$lastDamage" } ?: if (resolved) "Nobody got it" else "Round ${index + 1}",
                            fontWeight = FontWeight.Bold, color = if (roundWinner == null) Street.c.secondary else Street.c.red)
                        Spacer(Modifier.weight(1f))
                    }
                    Column(Modifier.weight(1f).rotate(if (p == 1) 180f else 0f).padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        HealthBar(names[p], avatars[p], hp[p], if (p == 0) Street.c.jade else Street.c.sky)
                        questions.getOrNull(index)?.let { FastQuestion(it, picks[p], locked[p] || resolved, resolved, compact = true) { o -> pick(p, o) } }
                    }
                }
            }
        }
        Confetti(confetti)
    }
}

// ---------- online battle (QR + Nearby Connections) ----------

private fun battlePermissions(): Array<String> = buildList {
    add(Manifest.permission.CAMERA)
    if (Build.VERSION.SDK_INT >= 31) { add(Manifest.permission.BLUETOOTH_SCAN); add(Manifest.permission.BLUETOOTH_ADVERTISE); add(Manifest.permission.BLUETOOTH_CONNECT) }
    if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.NEARBY_WIFI_DEVICES)
    if (Build.VERSION.SDK_INT <= 32) add(Manifest.permission.ACCESS_FINE_LOCATION)
}.toTypedArray()

@Composable
fun OnlineBattle(close: () -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    var granted by remember { mutableStateOf(battlePermissions().all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r -> granted = r.values.all { it } }
    val me = remember { app.myCard() }
    val link = remember { BattleLink(context, me.id) }
    val match = remember { Match(link, me) { outcome, opp, bonus, fastest -> app.recordMatch(outcome, opp, bonus, fastest) } }
    var scanning by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var confetti by remember { mutableIntStateOf(0) }

    DisposableEffect(Unit) {
        val window = (context as? ComponentActivity)?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); match.close() }
    }
    LaunchedEffect(granted) { if (granted) link.start() else launcher.launch(battlePermissions()) }
    LaunchedEffect(link.state) { if (link.state == BattleLink.State.Connected) match.hello() }

    Box(Modifier.fillMaxSize()) {
        if (match.opponent != null) {
            MatchScreen(match, close) { confetti++ }
            if (link.state != BattleLink.State.Connected) {
                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)), contentAlignment = Alignment.Center) {
                    Column(Modifier.padding(30.dp).card().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(color = Street.c.red)
                        Text("Reconnecting to ${match.opponent?.name}…", fontWeight = FontWeight.Bold, color = Street.c.text)
                        Text("Keep both phones close with the app open. The match continues where it left off.", color = Street.c.secondary, textAlign = TextAlign.Center)
                        Text("Leave match", color = Street.c.red, fontWeight = FontWeight.Bold, modifier = Modifier.clickable(onClick = close).padding(6.dp))
                    }
                }
            }
        } else if (scanning) {
            Scanner(onCancel = { scanning = false }) { code ->
                scanning = false
                val id = DuelQR.playerId(code)
                message = when {
                    id == null -> "That's not a Měitiān duel code."
                    id == me.id -> "That's your own code 😄"
                    else -> { link.connect(id); null }
                }
            }
        } else {
            Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { CloseButton(close); Spacer(Modifier.weight(1f)); Text("battle a friend", style = street(22.sp), color = Street.c.text); Spacer(Modifier.weight(1f)) }
                PlayerCardView(me, compact = true)
                val bmp = remember { runCatching { BarcodeEncoder().encodeBitmap(DuelQR.payload(me.id), BarcodeFormat.QR_CODE, 640, 640) }.getOrNull() }
                bmp?.let { Image(it.asImageBitmap(), "Your duel QR code", Modifier.size(240.dp).clip(RoundedCornerShape(18.dp)).background(Color.White).border(3.dp, Street.c.ink, RoundedCornerShape(18.dp)).padding(10.dp)) }
                Text("Your friend scans this code, or you scan theirs.", color = Street.c.secondary, textAlign = TextAlign.Center)
                Badge(when (link.state) {
                    BattleLink.State.Connecting -> "Connecting… keep the phones close"
                    BattleLink.State.Connected -> "Connected! Saying hello…"
                    BattleLink.State.Reconnecting -> "Reconnecting…"
                    else -> if (granted) "Waiting for your friend" else "Allow Bluetooth / nearby devices to battle"
                })
                message?.let { Text(it, color = Street.c.red, fontWeight = FontWeight.Bold) }
                Spacer(Modifier.weight(1f))
                BigButton("Scan friend's code") { message = null; scanning = true }
                Text("Both phones need Bluetooth and Wi‑Fi on. No internet or account needed. Android battles Android (iPhones use Apple's own link).",
                    fontSize = 12.sp, color = Street.c.secondary, textAlign = TextAlign.Center)
            }
        }
        Confetti(confetti)
    }
}

@Composable
private fun Scanner(onCancel: () -> Unit, onCode: (String) -> Unit) {
    var done by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                DecoratedBarcodeView(ctx).apply {
                    setStatusText("")
                    decodeContinuous { r -> if (!done && r.text != null) { done = true; onCode(r.text) } }
                    resume()
                }
            },
            onRelease = { it.pause() },
            modifier = Modifier.fillMaxSize(),
        )
        Text("Point at your friend's code", color = Color.White, fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 90.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 16.dp, vertical = 10.dp))
        Box(Modifier.align(Alignment.TopEnd).padding(20.dp).size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).border(2.dp, Color.White, CircleShape).clickable(onClick = onCancel),
            contentAlignment = Alignment.Center) { Text("✕", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold) }
        Text("cancel", color = Color.White, fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 50.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.55f)).clickable(onClick = onCancel).padding(horizontal = 28.dp, vertical = 12.dp))
    }
}

@Composable
private fun MatchScreen(m: Match, close: () -> Unit, celebrate: () -> Unit) {
    val opp = m.opponent ?: return
    val app = LocalApp.current
    val shake = remember { Shake() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val density = androidx.compose.ui.platform.LocalDensity.current.density
    Box(Modifier.fillMaxSize().offset { shake.offset(density) }) {
    Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CloseButton(close); Spacer(Modifier.weight(1f))
            if (m.phase != Match.Phase.Lobby) Text("${m.mode.emoji} ${m.mode.title.lowercase()}", style = street(20.sp), color = Street.c.text)
            Spacer(Modifier.weight(1f))
        }
        when {
            m.incompatible -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                LaunchedEffect(Unit) { Sfx.play(Sfx.Sound.Wrong) }
                Spacer(Modifier.weight(1f))
                Text("🚫", fontSize = 80.sp)
                Text("can't battle", style = street(48.sp), color = Street.c.text)
                Text(if (m.me.swearsOn) "You have swear words ON, ${opp.name} has them OFF." else "You have swear words OFF, ${opp.name} has them ON.",
                    fontWeight = FontWeight.Bold, color = Street.c.text, textAlign = TextAlign.Center)
                Text("Players can only battle with the same swear setting. Change it in Progress → Content, then pair again.", color = Street.c.secondary, textAlign = TextAlign.Center)
                Spacer(Modifier.weight(1f))
                BigButton("Close", onClick = close)
            }
            m.phase == Match.Phase.Lobby -> {
                PlayerCardView(m.me, compact = true)
                Text("VS", style = street(32.sp), color = Street.c.red, modifier = Modifier.align(Alignment.CenterHorizontally))
                PlayerCardView(opp, compact = true)
                val r = app.arena.rivals[opp.id]
                Text(r?.let { "Head to head: you ${it.wins} – ${it.losses} ${opp.name}" } ?: "First battle against ${opp.name}!", fontWeight = FontWeight.Bold,
                    color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally))
                Spacer(Modifier.weight(1f))
                if (m.isHost) {
                    Text("pick a game", style = street(20.sp), color = Street.c.text)
                    Mode.entries.forEach { mode ->
                        Row(Modifier.fillMaxWidth().block(if (mode == Mode.Duel) Street.warm() else Street.sky()).clickable { m.hostStart(mode) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(mode.emoji, fontSize = 30.sp); HSpacer(12.dp)
                            Column { Text(mode.title.lowercase(), style = street(22.sp), color = Color.White); Text(mode.blurb, fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f)) }
                        }
                    }
                } else Text("${opp.name} is picking a game…", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 40.dp))
            }
            m.phase == Match.Phase.Countdown -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("${m.count}", style = street(150.sp), color = Street.c.red)
            }
            m.phase == Match.Phase.Finished -> {
                val won = m.winner == m.me.id; val draw = m.winner == null
                LaunchedEffect(Unit) { if (won) celebrate() }
                Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Spacer(Modifier.weight(1f))
                    Text(if (draw) "🤝" else if (won) "🏆" else "😤", fontSize = 90.sp)
                    Text(if (draw) "平局 · DRAW!" else if (won) "胜利 · VICTORY!" else "失败 · DEFEAT", style = street(38.sp), color = if (won) Street.c.gold else Street.c.text)
                    Text(if (draw) "píngjú" else if (won) "shènglì" else "shībài", color = Street.c.secondary)
                    Badge("+${m.coins} 🪙")
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (m.mode == Mode.Duel) {
                            StatBox("${m.damageDealt}", "damage", modifier = Modifier.weight(1f))
                            StatBox(m.fastest?.let { "%.1fs".format(it / 1000.0) } ?: "–", "fastest", modifier = Modifier.weight(1f))
                        } else {
                            StatBox("${m.myScore}", "you", modifier = Modifier.weight(1f)); StatBox("${m.oppScore}", opp.name, modifier = Modifier.weight(1f))
                        }
                        StatBox("${app.arena.streak}", "streak", modifier = Modifier.weight(1f))
                    }
                    Spacer(Modifier.weight(1f))
                    BigButton("Rematch") { m.backToLobby() }
                    Text("Done", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.clickable(onClick = close).padding(8.dp))
                }
            }
            m.mode == Mode.Duel -> {
                HealthBar(opp.name, opp.avatarSymbol, m.hpOf(opp.id), Street.c.sky, opp.aura)
                Spacer(Modifier.weight(1f))
                m.current?.let { FastQuestion(it, m.myPick, m.lockedOut || m.phase == Match.Phase.RoundResult, m.phase == Match.Phase.RoundResult) { o -> m.pick(o) } }
                val w = m.roundWinner
                Text(
                    when {
                        m.phase == Match.Phase.RoundResult && w == null -> "Nobody got it."
                        m.phase == Match.Phase.RoundResult && w == m.me.id -> "${m.me.effectSymbol} HIT! -${m.lastDamage}"
                        m.phase == Match.Phase.RoundResult -> "${opp.effectSymbol} ${opp.name} was faster! -${m.lastDamage}"
                        m.lockedOut -> "Wrong! Locked out this round 🔒"
                        m.myPick != null -> "Waiting…"
                        else -> " "
                    },
                    style = street(22.sp), color = if (w == m.me.id) Street.c.jade else Street.c.red, modifier = Modifier.align(Alignment.CenterHorizontally),
                )
                Spacer(Modifier.weight(1f))
                HealthBar(m.me.name, m.me.avatarSymbol, m.hpOf(m.me.id), Street.c.jade, m.me.aura)
            }
            else -> {
                var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
                LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(200) } }
                val left = ((m.blitzEnds - now) / 1000.0).coerceAtLeast(0.0)
                Text(if (m.myDone) "TIME!" else "${kotlin.math.ceil(left).toInt()}", style = street(48.sp), color = if (left < 10) Street.c.red else Street.c.text,
                    modifier = Modifier.align(Alignment.CenterHorizontally))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatBox("${m.myScore}", "${m.me.avatarSymbol} You", Street.c.jade, Modifier.weight(1f))
                    StatBox("${m.oppScore}", "${opp.avatarSymbol} ${opp.name}", Street.c.sky, Modifier.weight(1f))
                }
                Spacer(Modifier.weight(1f))
                if (m.myDone) Text("Waiting for ${opp.name} to finish…", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally))
                else m.current?.let { FastQuestion(it, m.myPick, m.lockedOut, m.lockedOut) { o -> m.pick(o) } }
                if (m.lockedOut) Text("Oops! 1 s penalty", color = Street.c.red, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.CenterHorizontally))
                Spacer(Modifier.weight(1f))
            }
        }
    }
    if (m.mode == Mode.Duel && !m.incompatible) {
        val iWon = m.roundWinner == m.me.id
        HitEffect(if (iWon) m.me.effect else opp.effect, m.hitTick,
            androidx.compose.ui.geometry.Offset(0.5f, if (iWon) 0.9f else 0.1f), androidx.compose.ui.geometry.Offset(0.5f, if (iWon) 0.1f else 0.9f),
            damage = m.lastDamage) { scope.launch { shake.hit(it) } }
    }
    }
}
