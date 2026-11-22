package com.asbestboi.meitian.ui

import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.draw.rotate
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.BattleSession
import com.asbestboi.meitian.data.Online
import com.asbestboi.meitian.data.Speaker
import com.asbestboi.meitian.data.playerCard
import kotlinx.coroutines.launch
import uniffi.meitian_core.BattleAnswer
import uniffi.meitian_core.BattleAsk
import uniffi.meitian_core.BattleMode
import uniffi.meitian_core.BattlePhase
import uniffi.meitian_core.BattlePlayer
import uniffi.meitian_core.BattleQuestion
import uniffi.meitian_core.BattleView
import uniffi.meitian_core.ModeInfo
import uniffi.meitian_core.OnlineProfile
import uniffi.meitian_core.Outcome
import uniffi.meitian_core.arenaFor
import uniffi.meitian_core.modeInfo
import uniffi.meitian_core.modesFor
import uniffi.meitian_core.sayAfterRound

fun ModeInfo.brush(): Brush = Brush.linearGradient(colors.map(::hexColor))

/** A battle in a server room, from joining to the result. [partyCode] is shown in a party's lobby. */
@Composable
fun BattleScreen(path: String, auto: BattleMode?, partyCode: String? = null, waitingFor: List<OnlineProfile> = emptyList(), invited: String? = null, close: () -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val session = remember {
        BattleSession(path, app.myCard(), auto) { result, rival -> app.recordBattle(result, rival?.playerCard, rival?.profile?.avatar.orEmpty()) }
    }
    val v = session.view
    var confetti by remember { mutableIntStateOf(0) }
    val shake = remember { Shake() }
    val density = LocalDensity.current.density
    DisposableEffect(Unit) {
        val window = (context as? ComponentActivity)?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        session.open()
        com.asbestboi.meitian.data.Invites.busy = true
        onDispose {
            com.asbestboi.meitian.data.Invites.busy = false
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            session.leave()
        }
    }
    LaunchedEffect(v.phase) { if (v.phase == BattlePhase.FINISHED && v.result?.outcome == Outcome.WIN) confetti++ }
    LaunchedEffect(session.hit?.tick) { if (session.hit != null) haptic.performHapticFeedback(HapticFeedbackType.LongPress) }
    val leave = {
        // gave up before they came: take the invitation back
        if (invited != null && (v.phase == BattlePhase.WAITING || v.phase == BattlePhase.LOBBY)) takeBack(invited)
        session.leave(); scope.launch { Online.sync(app, force = true) }; close()
    }
    androidx.activity.compose.BackHandler { leave() }

    Box(Modifier.fillMaxSize().offset { shake.offset(density) }) {
        ArenaBackground(app.arenaTheme, strength = 0.62f)
        Column(Modifier.fillMaxSize().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CloseButton { leave() }
                Spacer(Modifier.weight(1f))
                val m = v.mode?.let(::modeInfo)
                if (m != null && v.phase != BattlePhase.LOBBY) Text("${m.emoji} ${m.title.lowercase()}", style = street(20.sp), color = Street.c.text)
                Spacer(Modifier.weight(1f))
                ConnectionDot(v)
            }
            when (v.phase) {
                BattlePhase.GONE -> Message("🚫", "can't battle", v.problem, close = leave)
                BattlePhase.WAITING -> Connecting(waitingFor)
                BattlePhase.LOBBY -> if (v.group) GroupLobby(session, v, partyCode) else DuoLobby(session, v, waitingFor)
                BattlePhase.COUNTDOWN -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("${v.count}", style = street(150.sp), color = Street.c.red)
                        v.mode?.let { Text(modeInfo(it).blurb, color = Street.c.text, textAlign = TextAlign.Center) }
                        if (v.mode == BattleMode.TEAM2V2) v.players.firstOrNull { it.id == v.me }?.let { me ->
                            val mate = v.players.firstOrNull { it.team == me.team && it.id != me.id }
                            Text("your partner: ${mate?.name ?: "?"} 🤝", fontWeight = FontWeight.Bold, color = Street.c.text)
                        }
                    }
                }
                BattlePhase.FINISHED -> Results(session, v, leave)
                else -> Game(session, v) { strength -> scope.launch { shake.hit(strength) } }
            }
        }
        AnimatedVisibility(v.notice.isNotEmpty(), Modifier.align(Alignment.TopCenter).padding(top = 64.dp)) {
            Text(v.notice, color = Color.White, fontWeight = FontWeight.Bold,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Street.ink()).padding(horizontal = 16.dp, vertical = 8.dp))
        }
        v.rating?.let { r ->
            Text(if (r.counted) "rating ${r.rating} (${if (r.delta >= 0) "+" else ""}${r.delta})" else "the phones disagreed: no rating change",
                color = Color.White, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 64.dp).clip(RoundedCornerShape(50)).background(Street.ink()).padding(horizontal = 16.dp, vertical = 8.dp))
        }
        if (v.paused) Paused(v, leave)
        Confetti(confetti, sound = false)
    }
}

private fun takeBack(room: String) {
    kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch { runCatching { Online.decline(room) } }
}

@Composable
private fun ConnectionDot(v: BattleView) {
    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(if (v.connected) Street.c.jade else Street.c.red))
    }
}

@Composable
private fun ColumnScope.Message(emoji: String, title: String, text: String, close: () -> Unit) {
    Spacer(Modifier.weight(1f))
    Text(emoji, fontSize = 80.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
    Text(title, style = street(40.sp), color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally))
    Text(text, color = Street.c.text, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    Spacer(Modifier.weight(1f))
    BigButton("Close", onClick = close)
}

@Composable
private fun ColumnScope.Connecting(people: List<OnlineProfile>) {
    Spacer(Modifier.weight(1f))
    Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(10.dp)) { people.forEach { Avatar(it, 84.dp) } }
    Text(people.joinToString(", ") { it.nickname }.ifEmpty { "connecting…" }, style = street(24.sp), color = Street.c.text, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    CircularProgressIndicator(color = Street.c.red, modifier = Modifier.align(Alignment.CenterHorizontally))
    Spacer(Modifier.weight(1f))
}

@Composable
private fun Paused(v: BattleView, leave: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(enabled = false) {}, contentAlignment = Alignment.Center) {
        Column(Modifier.padding(30.dp).card().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(color = Street.c.red)
            val away = v.players.filter { !it.here && it.id != v.me }.joinToString(", ") { it.name }
            Text(if (!v.connected) "Reconnecting…" else "Waiting for $away to reconnect…", fontWeight = FontWeight.Bold, color = Street.c.text, textAlign = TextAlign.Center)
            Text(if (!v.connected) "The battle continues where it left off." else "If they're gone for 30 seconds, they forfeit.", color = Street.c.secondary, textAlign = TextAlign.Center)
            Text("Leave battle", color = Street.c.red, fontWeight = FontWeight.Bold, modifier = Modifier.clickable(onClick = leave).padding(6.dp))
        }
    }
}

// ---------- lobby ----------

@Composable
private fun ColumnScope.DuoLobby(session: BattleSession, v: BattleView, waitingFor: List<OnlineProfile>) {
    val app = LocalApp.current
    val opp = v.players.firstOrNull { it.id != v.me }
    val card = opp?.playerCard
    if (opp == null || card == null) {
        Connecting(listOfNotNull(opp?.profile).ifEmpty { waitingFor })
        Text("they got your invitation ✉️ it stays open for 30 minutes. The battle starts as soon as they accept.", color = Street.c.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        return
    }
    PlayerCardView(session.me, compact = true, picture = { MyPicture(54.dp) })
    Text("VS", style = street(32.sp), color = Street.c.red, modifier = Modifier.align(Alignment.CenterHorizontally))
    PlayerCardView(card, compact = true, picture = { BattlePicture(opp, 54.dp) })
    Box(Modifier.align(Alignment.CenterHorizontally)) { ArenaBadge(arenaFor(opp.level, 1u)) }
    val r = app.arena.rivals[card.id]
    Text(r?.let { "Head to head: you ${it.wins} – ${it.losses} ${opp.name}" } ?: "First battle against ${opp.name}!", fontWeight = FontWeight.Bold,
        color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally))
    Spacer(Modifier.weight(1f))
    ModeMenu(session, v, 2)
}

@Composable
private fun ColumnScope.GroupLobby(session: BattleSession, v: BattleView, code: String?) {
    val here = v.players.count { it.here && it.card.isNotEmpty() }
    if (code != null) {
        val ctx = LocalContext.current
        Row(Modifier.fillMaxWidth().block(Street.pink()).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("party code", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.85f))
                Text(code, style = street(34.sp), color = Color.White)
            }
            Pill("share", Color.White, modifier = Modifier.clickable {
                ctx.startActivity(android.content.Intent.createChooser(android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(android.content.Intent.EXTRA_TEXT, "Join my Měitiān party: $code"), null))
            })
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (i in 0 until 4) {
            val p = v.players.getOrNull(i)
            Column(Modifier.weight(1f).card().then(p?.playerCard?.let { Modifier.border(3.dp, com.asbestboi.meitian.data.Catalog.frame(it.frame), RoundedCornerShape(20.dp)) } ?: Modifier).padding(8.dp).alpha(if (p == null || p.here) 1f else 0.4f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (p != null) {
                    Box {
                        DressedPicture(p, 52.dp)
                        p.playerCard?.stickerSymbol?.let { Text(it, fontSize = 22.sp, modifier = Modifier.align(Alignment.TopEnd).offset(x = 8.dp, y = (-8).dp).rotate(14f)) }
                    }
                    BattleName(p, p.name, 12.sp)
                    Text(if (p.id == v.host) "host 👑" else arenaFor(p.level, 1u).emoji + " HSK ${p.level}", fontSize = 11.sp, color = Street.c.secondary, maxLines = 1)
                } else {
                    Box(Modifier.size(52.dp).clip(CircleShape).background(Street.c.secondary.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) { Text("＋", color = Street.c.secondary) }
                    Text("free", fontSize = 12.sp, color = Street.c.secondary); Text(" ", fontSize = 11.sp)
                }
            }
        }
    }
    if (code != null && v.players.size < 4) InviteFriends(code, v)
    Spacer(Modifier.weight(1f))
    ModeMenu(session, v, here)
}

/** Friends who aren't in the party yet: one tap puts an invitation into their inbox. */
@Composable
private fun InviteFriends(code: String, v: BattleView) {
    val scope = rememberCoroutineScope()
    var friends by remember { mutableStateOf<List<OnlineProfile>>(emptyList()) }
    val invited = remember { mutableStateListOf<String>() }
    LaunchedEffect(Unit) { runCatching { friends = Online.friends().friends } }
    val free = friends.filter { f -> v.players.none { it.id == f.id } }.take(6)
    if (free.isEmpty()) return
    Column(Modifier.fillMaxWidth().card().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("invite friends", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
        free.forEach { f ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(f, 34.dp); HSpacer(10.dp)
                Text(f.nickname + if (f.online) " · online" else "", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.weight(1f), maxLines = 1)
                val done = f.id in invited
                Pill(if (done) "invited ✓" else "invite", if (done) Street.c.secondary else Street.c.jade, modifier = Modifier.clickable(enabled = !done) {
                    scope.launch { if (runCatching { Online.inviteToParty(code, f.id) }.isSuccess) invited.add(f.id) }
                })
            }
        }
    }
}

/** The host picks a game; everyone else waits. */
@Composable
private fun ColumnScope.ModeMenu(session: BattleSession, v: BattleView, players: Int) {
    if (!v.isHost) {
        Text(if (v.mode != null) "starting soon…" else "${v.players.firstOrNull { it.id == v.host }?.name ?: "The host"} is picking a game…", fontWeight = FontWeight.Bold, color = Street.c.text,
            modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 40.dp))
        return
    }
    if (v.mode != null) {
        Text("starting as soon as everyone is here…", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 40.dp))
        return
    }
    if (!v.canStart) {
        Text("you need at least one more player", fontWeight = FontWeight.Bold, color = Street.c.secondary, modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 40.dp))
        return
    }
    Text("pick a game", style = street(20.sp), color = Street.c.text)
    Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        modesFor(players.toUInt()).forEach { m ->
            Row(Modifier.fillMaxWidth().block(m.brush()).clickable { session.start(m.mode) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(m.emoji, fontSize = 28.sp); HSpacer(12.dp)
                Column { Text(m.title.lowercase(), style = street(20.sp), color = Color.White); Text(m.blurb, fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f), maxLines = 2) }
            }
        }
    }
}

// ---------- the game ----------

private val BattleMode.isRace get() = this == BattleMode.BLITZ || this == BattleMode.SURVIVAL
private val BattleMode.hasHp get() = this == BattleMode.DUEL || this == BattleMode.LISTEN || this == BattleMode.SUDDEN || this == BattleMode.TONE_CLASH || this == BattleMode.TEAM2V2

@Composable
private fun ColumnScope.Game(session: BattleSession, v: BattleView, onImpact: (Float) -> Unit) {
    val mode = v.mode ?: return
    val others = v.players.filter { it.id != v.me }
    val me = v.players.firstOrNull { it.id == v.me }
    // where everybody is on screen, for the hit effects
    val spots = remember { androidx.compose.runtime.mutableStateMapOf<String, Offset>() }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var area by remember { mutableStateOf(Offset(1f, 1f)) }
    fun at(id: String, fallback: Offset) = spots[id]?.let { Offset(((it.x - origin.x) / area.x).coerceIn(0f, 1f), ((it.y - origin.y) / area.y).coerceIn(0f, 1f)) } ?: fallback
    Box(Modifier.weight(1f).onGloballyPositioned { c ->
        origin = c.positionInRoot()
        area = Offset(c.size.width.coerceAtLeast(1).toFloat(), c.size.height.coerceAtLeast(1).toFloat())
    }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (others.size == 1) PlayerBar(others[0], mode, v, spots) else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                others.forEach { PlayerChip(it, mode, v, spots, Modifier.weight(1f)) }
            }
            TimeBar(v, mode)
            Spacer(Modifier.weight(1f))
            when {
                mode.isRace && me?.done == true -> Waiting("time! waiting for the others…")
                v.spectating -> Waiting("you're out 👀 watching")
                else -> v.question?.let { q -> QuestionPanel(q, v) { session.answer(it) } }
            }
            Banner(v, mode)
            Spacer(Modifier.weight(1f))
            me?.let { PlayerBar(it, mode, v, spots, mine = true) }
            if (v.maxLives > 0u) Text((0 until v.maxLives.toInt()).joinToString(" ") { if (it < v.lives.toInt()) "❤️" else "🤍" }, fontSize = 22.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
        }
        session.hit?.let { hit ->
            val effect = v.players.firstOrNull { it.id == hit.attacker }?.playerCard?.effect ?: "fx.boom"
            hit.targets.forEach { t ->
                HitEffect(effect, hit.tick, at(hit.attacker, Offset(0.5f, 0.9f)), at(t, Offset(0.5f, 0.1f)), damage = hit.damage, onImpact = onImpact)
            }
        }
    }
}

@Composable
private fun Waiting(text: String) = Column(Modifier.fillMaxWidth().card().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
    CircularProgressIndicator(color = Street.c.red)
    Text(text, fontWeight = FontWeight.Bold, color = Street.c.text)
}

@Composable
private fun TimeBar(v: BattleView, mode: BattleMode) {
    val total = v.timeTotalMs.toFloat()
    if (total <= 0f) { Spacer(Modifier.height(8.dp)); return }
    val left = v.timeLeftMs.toFloat()
    val low = left < 3_000f || (mode.isRace && left < 10_000f)
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        if (mode.isRace) Text("${kotlin.math.ceil(left / 1000).toInt()}", style = street(40.sp), color = if (low) Street.c.red else Street.c.text)
        LinearProgressIndicator(progress = { left / total }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)), color = if (low) Street.c.red else Street.c.sky)
    }
}

/** Remembers where this is on screen (its centre), so hits can fly there. */
private fun Modifier.spot(id: String, spots: MutableMap<String, Offset>): Modifier = onGloballyPositioned { c ->
    val at = c.positionInRoot() + Offset(c.size.width / 2f, c.size.height / 2f)
    if (spots[id] != at) spots[id] = at
}

/** Wide bar: me, or the only opponent. */
@Composable
private fun PlayerBar(p: BattlePlayer, mode: BattleMode, v: BattleView, spots: MutableMap<String, Offset>, mine: Boolean = false) {
    val hp by animateFloatAsState(p.hp.toFloat(), label = "hp")
    Dressed(p, Modifier.fillMaxWidth().spot(p.id, spots).alpha(if (p.out) 0.5f else 1f)) { Row(Modifier.fillMaxWidth().padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
        DressedPicture(p, 44.dp)
        HSpacer(10.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    BattleName(p, if (mine) "${p.name} (you)" else p.name, 16.sp)
                    p.playerCard?.titleItem?.let { TitledText("${it.symbol} · ${it.name}", it.id, 11.sp, weight = FontWeight.Bold) }
                }
                if (mode == BattleMode.TEAM2V2) Pill("team ${if (p.team == 0u) "🔴" else "🔵"}", Street.c.secondary)
                HSpacer(6.dp)
                Text(score(p, mode, v), fontWeight = FontWeight.ExtraBold, color = if (mode.hasHp && p.hp <= 30u) Street.c.red else Street.c.text)
            }
            if (mode.hasHp) LinearProgressIndicator(progress = { hp / 100f }, modifier = Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(6.dp)),
                color = if (p.hp <= 30u) Street.c.red else if (mine) Street.c.jade else Street.c.sky)
        }
    } }
}

/** A player's equipped frame around their bar, and their sticker slapped on its corner. */
@Composable
private fun Dressed(p: BattlePlayer, modifier: Modifier, content: @Composable () -> Unit) {
    val card = p.playerCard
    val shape = RoundedCornerShape(22.dp)
    Box(modifier) {
        Box(Modifier.clip(shape).background(Street.c.card).border(5.dp, com.asbestboi.meitian.data.Catalog.frame(card?.frame ?: "fr.lantern"), shape)) { content() }
        card?.stickerSymbol?.let { Text(it, fontSize = 28.sp, modifier = Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-12).dp).rotate(14f)) }
    }
}

/** A player's picture with their aura around it. */
@Composable
private fun DressedPicture(p: BattlePlayer, size: androidx.compose.ui.unit.Dp) {
    Box(contentAlignment = Alignment.Center) {
        Aura(p.playerCard?.aura, size.value / 2f, Modifier.requiredSize(size * 1.9f))
        BattlePicture(p, size)
    }
}

/** A player's name in their title's colours. */
@Composable
private fun BattleName(p: BattlePlayer, text: String, size: androidx.compose.ui.unit.TextUnit, modifier: Modifier = Modifier) =
    TitledText(text, p.playerCard?.title ?: p.profile?.cosmeticTitle.orEmpty(), size, modifier)

/** Narrow card: one of several opponents. */
@Composable
private fun PlayerChip(p: BattlePlayer, mode: BattleMode, v: BattleView, spots: MutableMap<String, Offset>, modifier: Modifier) {
    val hp by animateFloatAsState(p.hp.toFloat(), label = "hp")
    Dressed(p, modifier.spot(p.id, spots).alpha(if (p.out || !p.here) 0.45f else 1f)) { Column(Modifier.fillMaxWidth().padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box {
            DressedPicture(p, 40.dp)
            if (mode == BattleMode.TEAM2V2) Text(if (p.team == 0u) "🔴" else "🔵", fontSize = 12.sp, modifier = Modifier.align(Alignment.BottomEnd))
            if (p.answered && v.phase == BattlePhase.PLAYING) Text("💬", fontSize = 12.sp, modifier = Modifier.align(Alignment.TopEnd))
        }
        BattleName(p, p.name, 12.sp)
        Text(if (p.out) "out" else score(p, mode, v), fontSize = 13.sp, fontWeight = FontWeight.ExtraBold, color = if (p.out) Street.c.red else Street.c.text)
        if (mode.hasHp) LinearProgressIndicator(progress = { hp / 100f }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)), color = if (p.hp <= 30u) Street.c.red else Street.c.sky)
    } }
}

private fun score(p: BattlePlayer, mode: BattleMode, v: BattleView) = when {
    mode.hasHp -> "${p.hp} HP"
    mode == BattleMode.BATTLE_ROYALE -> if (p.out) "out" else "in 👑"
    v.target > 0u -> "${p.score} / ${v.target}"
    else -> "${p.score}" + if (p.done) " ✓" else ""
}

@Composable
private fun Banner(v: BattleView, mode: BattleMode) {
    val w = v.players.firstOrNull { it.id == v.roundWinner }
    val (text, color) = when {
        v.phase == BattlePhase.ROUND_RESULT && mode == BattleMode.BATTLE_ROYALE -> "${v.players.count { !it.out }} still in" to Street.c.text
        v.phase == BattlePhase.ROUND_RESULT && v.reveal && w == null -> "nobody got it" to Street.c.secondary
        v.phase == BattlePhase.ROUND_RESULT && w?.id == v.me -> (if (mode.hasHp) "hit! -${v.lastDamage} · %.1fs ⚡".format(v.lastMs.toInt() / 1000.0) else "point! %.1fs ⚡".format(v.lastMs.toInt() / 1000.0)) to Street.c.jade
        v.phase == BattlePhase.ROUND_RESULT && w != null -> "${w.name} was faster!" to Street.c.red
        v.locked && mode.isRace -> (if (mode == BattleMode.SURVIVAL) "ouch! -1 life" else "oops! 1 s penalty") to Street.c.red
        v.locked -> "not quite, try again" to Street.c.red
        v.answered && !mode.isRace -> "waiting…" to Street.c.secondary
        else -> " " to Street.c.text
    }
    Text(text, style = street(20.sp), color = color, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    if (v.reveal && v.phase == BattlePhase.ROUND_RESULT) v.question?.let { Text(it.solution, color = Street.c.text, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
}

/** A question with its way of answering: four options, word tiles or a pinyin field. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QuestionPanel(q: BattleQuestion, v: BattleView, answer: (BattleAnswer) -> Unit) {
    val app = LocalApp.current
    val open = v.phase == BattlePhase.PLAYING && !v.answered && !v.locked
    LaunchedEffect(v.index, q.say) { if (q.say.isNotEmpty() && v.phase == BattlePhase.PLAYING) Speaker.say(q.say) }
    // the finished sentence, once the round is over
    LaunchedEffect(v.index, v.phase) { if (v.phase == BattlePhase.ROUND_RESULT) sayAfterRound(q).let { if (it.isNotEmpty()) Speaker.say(it) } }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(min = 96.dp).card().padding(12.dp), contentAlignment = Alignment.Center) {
            when (q.ask) {
                BattleAsk.LISTEN, BattleAsk.TONE -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    SpeakButton(q.say, 72.dp, Street.c.jade)
                    Text(if (q.ask == BattleAsk.TONE) "which tone? “${q.prompt}”" else "listen and tap it", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Street.c.secondary)
                }
                BattleAsk.MEANING -> RubyText(q.prompt, q.promptPinyin, if (q.prompt.length > 3) 42.sp else 54.sp, FontWeight.SemiBold, center = true)
                BattleAsk.PINYIN -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(q.prompt, fontSize = if (q.prompt.length > 3) 42.sp else 58.sp, fontWeight = FontWeight.SemiBold, color = Street.c.text)
                    HSpacer(14.dp)
                    SpeakButton(q.prompt, 48.dp, Street.c.jade)
                }
                else -> Text("“${q.prompt}”", style = street(if (q.prompt.length > 24) 20.sp else 28.sp), color = Street.c.text, textAlign = TextAlign.Center)
            }
        }
        when (q.ask) {
            BattleAsk.SENTENCE -> {
                val built = remember(v.index) { mutableStateListOf<Int>() }
                FlowRow(Modifier.fillMaxWidth().heightIn(min = 52.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    built.forEach { i -> BattleTile(q.tiles[i], false) { if (open) built.remove(i) } }
                }
                Box(Modifier.fillMaxWidth().height(1.dp).background(Street.c.secondary.copy(alpha = 0.4f)))
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    q.tiles.forEachIndexed { i, t -> BattleTile(t, i in built) { if (open && i !in built) { Speaker.say(t); built.add(i) } } }
                }
                BigButton("check", brush = Street.jade(), enabled = open && built.size == q.tiles.size) { answer(BattleAnswer.Tiles(built.map { q.tiles[it] })) }
            }
            BattleAsk.PINYIN -> {
                var text by remember(v.index) { mutableStateOf("") }
                val focus = remember { FocusRequester() }
                LaunchedEffect(v.index) { runCatching { focus.requestFocus() } }
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().focusRequester(focus), label = { Text("pinyin, e.g. nihao") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { if (open && text.isNotBlank()) answer(BattleAnswer.Text(text)) }))
                BigButton("go", brush = Street.jade(), enabled = open && text.isNotBlank()) { answer(BattleAnswer.Text(text)) }
            }
            else -> q.options.withIndex().chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { (i, o) ->
                        val right = i == q.answer.toInt()
                        val mine = v.myOption?.toInt() == i
                        val bg = when {
                            v.reveal && right -> Street.c.jade.copy(alpha = 0.25f)
                            mine && v.reveal -> Street.c.red.copy(alpha = 0.22f)
                            mine -> if (right) Street.c.jade.copy(alpha = 0.25f) else Street.c.red.copy(alpha = 0.22f)
                            else -> Street.c.card
                        }
                        Column(
                            Modifier.weight(1f).heightIn(min = 64.dp).streetCard(bg, Street.c.ink, shadow = 3.dp).alpha(if (!open && !mine && !(v.reveal && right)) 0.5f else 1f)
                                .clickable(enabled = open) { answer(BattleAnswer.Option(i.toUInt())) }.padding(6.dp),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                        ) {
                            val chinese = q.ask != BattleAsk.MEANING
                            Text(o.label, fontSize = if (chinese) 24.sp else 15.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 2,
                                color = if (q.ask == BattleAsk.TONE) toneColor(i + 1) else Street.c.text)
                            if (o.pinyin.isNotEmpty() && app.settings.showPinyin) PinyinText(o.pinyin, 11.sp)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BattleTile(text: String, used: Boolean, onClick: () -> Unit) {
    Text(text, fontSize = 22.sp, color = if (used) Color.Transparent else Street.c.text,
        modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(if (used) Street.c.secondary.copy(alpha = 0.12f) else Street.c.card)
            .border(1.dp, if (used) Color.Transparent else Street.c.secondary.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
            .clickable(enabled = !used, onClick = onClick).padding(horizontal = 13.dp, vertical = 8.dp))
}

// ---------- result ----------

@Composable
private fun ColumnScope.Results(session: BattleSession, v: BattleView, leave: () -> Unit) {
    val app = LocalApp.current
    val r = v.result
    Spacer(Modifier.weight(1f))
    Column(Modifier.align(Alignment.CenterHorizontally), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (v.group && r != null) {
            Text(listOf("🥇", "🥈", "🥉", "🎖️")[(r.place.toInt() - 1).coerceIn(0, 3)], fontSize = 84.sp)
            Text(when (r.place.toInt()) { 1 -> "第一名 · first place!"; 2 -> "第二名 · second"; 3 -> "第三名 · third"; else -> "第四名 · fourth" }, style = street(32.sp), color = if (r.place == 1u) Street.c.gold else Street.c.text)
        } else {
            val o = r?.outcome
            Text(when (o) { Outcome.WIN -> "🏆"; Outcome.DRAW -> "🤝"; else -> "😤" }, fontSize = 84.sp)
            Text(when (o) { Outcome.WIN -> "胜利 · VICTORY!"; Outcome.DRAW -> "平局 · DRAW!"; else -> "失败 · DEFEAT" }, style = street(36.sp), color = if (o == Outcome.WIN) Street.c.gold else Street.c.text)
            Text(when (o) { Outcome.WIN -> "shènglì"; Outcome.DRAW -> "píngjú"; else -> "shībài" }, color = Street.c.secondary)
        }
        Badge("+${session.coins} 🪙")
    }
    Column(Modifier.fillMaxWidth().card().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        v.players.sortedBy { it.place }.forEach { p ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${p.place}", style = street(20.sp), color = Street.c.secondary, modifier = Modifier.padding(end = 10.dp))
                DressedPicture(p, 36.dp); HSpacer(10.dp)
                BattleName(p, if (p.id == v.me) "${p.name} (you)" else p.name, 16.sp, Modifier.weight(1f))
                p.playerCard?.stickerSymbol?.let { Text(it, fontSize = 20.sp); HSpacer(8.dp) }
                v.mode?.let { Text(score(p, it, v), fontWeight = FontWeight.Bold, color = Street.c.secondary) }
            }
        }
    }
    if (r != null) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (v.mode?.hasHp == true) StatBox("${r.damage}", "damage", modifier = Modifier.weight(1f))
        StatBox(r.fastestMs?.let { "%.1fs".format(it.toInt() / 1000.0) } ?: "–", "fastest", modifier = Modifier.weight(1f))
        if (r.ranked) StatBox("${app.arena.streak}", "win streak", modifier = Modifier.weight(1f))
    }
    Spacer(Modifier.weight(1f))
    if (v.canRematch) BigButton(if (v.group) "play again" else "rematch") { session.rematch() }
    else Text("waiting for ${v.players.firstOrNull { it.id == v.host }?.name ?: "the host"} to start the next game…", color = Street.c.text, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    Text("Done", fontWeight = FontWeight.Bold, color = Street.c.text, modifier = Modifier.align(Alignment.CenterHorizontally).clickable(onClick = leave).padding(8.dp))
}
