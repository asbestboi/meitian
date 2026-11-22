package com.asbestboi.meitian.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.asbestboi.meitian.LocalApp
import com.asbestboi.meitian.data.Catalog
import com.asbestboi.meitian.data.Online
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.meitian_core.Leaderboard
import uniffi.meitian_core.BattleMode
import uniffi.meitian_core.OnlineChallenge
import uniffi.meitian_core.QueueEvent
import uniffi.meitian_core.battleMode
import uniffi.meitian_core.modeInfo
import uniffi.meitian_core.modesFor
import uniffi.meitian_core.SoundId
import com.asbestboi.meitian.data.Sfx
import uniffi.meitian_core.OnlineFriends
import uniffi.meitian_core.OnlineProfile
import uniffi.meitian_core.nicknameOk

/** What the online screen is showing on top of its tabs. */
private sealed interface OnlineStage {
    data object Hub : OnlineStage
    data class Searching(val mode: BattleMode, val group: Boolean) : OnlineStage
    data class Playing(val path: String, val mode: BattleMode?, val people: List<OnlineProfile>, val party: String? = null) : OnlineStage
}

enum class HubStart { Play, Party }

/** Online play: quick matches and groups, parties with friends, leaderboards, your public profile. */
@Composable
fun OnlineHub(startAt: HubStart = HubStart.Play, close: () -> Unit) {
    val app = LocalApp.current
    val ctx = LocalContext.current
    LaunchedEffect(Unit) { Online.init(ctx); runCatching { Online.refreshMe() }; Online.sync(app, force = true) }
    var stage by remember { mutableStateOf<OnlineStage>(OnlineStage.Hub) }
    val join: (OnlineChallenge) -> Unit = { c ->
        stage = if (c.party.isNotEmpty()) OnlineStage.Playing(partyPath(c.party, app.settings.swears), null, listOf(c.from), c.party)
        else OnlineStage.Playing("/v1/rooms/${c.room}", battleMode(c.mode) ?: BattleMode.DUEL, listOf(c.from))
    }
    when (val s = stage) {
        is OnlineStage.Hub ->
            if (Online.profile == null && !Online.signedIn) OnlineSetup(close)
            else OnlineTabs(close, startAt,
                play = { mode, group -> stage = OnlineStage.Searching(mode, group) }, join = join,
                challenge = { room, mode, p -> stage = OnlineStage.Playing("/v1/rooms/$room", mode, listOf(p)) },
                party = { code -> stage = OnlineStage.Playing(partyPath(code, app.settings.swears), null, emptyList(), code) })
        is OnlineStage.Searching -> QuickMatchSearch(s.mode, s.group, cancel = { stage = OnlineStage.Hub }) { room, people ->
            stage = OnlineStage.Playing("/v1/rooms/$room", s.mode, people)
        }
        is OnlineStage.Playing -> BattleScreen(s.path, s.mode, s.party, s.people) { stage = OnlineStage.Hub }
    }
}

private fun partyPath(code: String, swears: Boolean) = "/v1/party/$code?swears=${if (swears) 1 else 0}"

// ----- sign up -----

@Composable
private fun OnlineSetup(close: () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(app.profile.name.trim().take(16)) }
    var code by remember { mutableStateOf("") }
    var recovering by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { CloseButton(close); Spacer(Modifier.weight(1f)); Text("go online", style = street(22.sp), color = Street.c.text); Spacer(Modifier.weight(1f)) }
        Box(Modifier.fillMaxWidth().block(Street.sky()).padding(20.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("🌍", fontSize = 40.sp)
                Text("battle anyone, anywhere", style = street(24.sp), color = Color.White)
                Text("Quick matches against iPhone and Android players, friends by code, weekly leaderboards. No email or password: just a nickname.",
                    color = Color.White.copy(alpha = 0.92f), fontSize = 14.sp)
            }
        }
        if (!recovering) {
            OutlinedTextField(name, { name = it.take(16) }, label = { Text("nickname") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Text("2–16 letters or numbers. Everyone can see it.", fontSize = 12.sp, color = Street.c.secondary)
            BigButton(if (busy) "…" else "create my profile", enabled = !busy && nicknameOk(name)) {
                busy = true; error = null
                scope.launch {
                    runCatching { Online.register(name); Online.sync(app, force = true) }.onFailure { error = it.message }
                    busy = false
                }
            }
            Text("I already have a profile (recovery code)", color = Street.c.red, fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable { recovering = true; error = null }.padding(6.dp))
        } else {
            OutlinedTextField(code, { code = it.trim() }, label = { Text("recovery code") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Text("Find it on your old phone: online → me → recovery code.", fontSize = 12.sp, color = Street.c.secondary)
            BigButton(if (busy) "…" else "sign in", enabled = !busy && code.contains('.')) {
                busy = true; error = null
                scope.launch {
                    runCatching { Online.recover(code) }.onFailure { error = it.message }
                    busy = false
                }
            }
            Text("back", color = Street.c.secondary, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { recovering = false }.padding(6.dp))
        }
        error?.let { Text(it, color = Street.c.red, fontWeight = FontWeight.Bold) }
    }
}

// ----- tabs -----

@Composable
private fun OnlineTabs(close: () -> Unit, startAt: HubStart, play: (BattleMode, Boolean) -> Unit, join: (OnlineChallenge) -> Unit,
                       challenge: (String, BattleMode, OnlineProfile) -> Unit, party: (String) -> Unit) {
    var tab by remember { mutableIntStateOf(if (startAt == HubStart.Party) 1 else 0) }
    val me = Online.profile
    // incoming challenges and friend requests while this screen is open
    LaunchedEffect(Unit) { while (true) { Online.refreshInbox(); delay(8_000) } }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) { CloseButton(close); Spacer(Modifier.weight(1f)); Text("online", style = street(22.sp), color = Street.c.text); Spacer(Modifier.weight(1f)); Spacer(Modifier.size(44.dp)) }
            if (me != null) ProfileRow(me, trailing = "${me.rating}")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val requests = Online.inbox?.requests?.toInt() ?: 0
                listOf("play", "party", if (requests > 0) "friends ($requests)" else "friends", "ranks", "me").forEachIndexed { i, t ->
                    Box(Modifier.weight(1f).clip(RoundedCornerShape(50)).background(if (tab == i) Street.c.ink else Street.c.card).clickable { tab = i }.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                        Text(t, color = if (tab == i) Street.c.paper else Street.c.text, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1)
                    }
                }
            }
        }
        Box(Modifier.weight(1f)) {
            when (tab) {
                0 -> PlayTab(play, join)
                1 -> PartyTab(party)
                2 -> FriendsTab(challenge)
                3 -> RanksTab()
                else -> MeTab()
            }
        }
    }
}

@Composable
private fun ProfileRow(p: OnlineProfile, trailing: String? = null, rank: Int? = null, highlight: Boolean = false, onClick: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(if (highlight) Street.c.gold.copy(alpha = 0.18f) else Street.c.card)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        rank?.let { Text("$it", style = street(18.sp), color = Street.c.secondary, modifier = Modifier.padding(end = 10.dp)) }
        Box {
            Avatar(p)
            if (p.online) Box(Modifier.align(Alignment.BottomEnd).size(12.dp).clip(CircleShape).background(Street.c.jade))
        }
        HSpacer(12.dp)
        Column(Modifier.weight(1f)) {
            Text("${p.nickname} #${p.tag}", fontWeight = FontWeight.Bold, color = Street.c.text, maxLines = 1)
            Text("HSK ${p.level} · 🔥 ${p.streak} · ${p.wins}–${p.losses}", fontSize = 12.sp, color = Street.c.secondary)
        }
        trailing?.let { Text(it, style = street(18.sp), color = Street.c.text) }
    }
}

/** The modes [players] people can play, as a grid. */
@Composable
private fun ModePicker(players: Int, mode: BattleMode, pick: (BattleMode) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        modesFor(players.toUInt()).chunked(4).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { m ->
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(if (m.mode == mode) Street.c.ink else Street.c.card).clickable { pick(m.mode) }.padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(m.emoji, fontSize = 20.sp)
                        Text(m.title.lowercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (m.mode == mode) Street.c.paper else Street.c.text, maxLines = 1)
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun PlayTab(play: (BattleMode, Boolean) -> Unit, join: (OnlineChallenge) -> Unit) {
    var group by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf(BattleMode.DUEL) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Online.inbox?.challenges?.forEach { c -> ChallengeCard(c, join) }
        val info = modeInfo(mode)
        Column(Modifier.fillMaxWidth().block(info.brush()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("${info.emoji} ${info.title.lowercase()}", style = street(26.sp), color = Color.White)
            Text(info.blurb, color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(false to "1 vs 1", true to "group of 4").forEach { (g, label) ->
                Box(Modifier.weight(1f).clip(RoundedCornerShape(50)).background(if (group == g) Street.c.ink else Street.c.card).clickable {
                    group = g
                    if (modesFor(if (g) 4u else 2u).none { it.mode == mode }) mode = BattleMode.DUEL
                }.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                    Text(label, fontWeight = FontWeight.Bold, color = if (group == g) Street.c.paper else Street.c.text)
                }
            }
        }
        ModePicker(if (group) 4 else 2, mode) { mode = it }
        BigButton(if (group) "find a group" else "find an opponent", brush = info.brush()) { play(mode, group) }
        Text(if (group) "Groups are for coins: the better your place, the more you get. Ratings don't change."
            else "Wins and losses move your rating. Both phones have to agree on the result for it to count.", fontSize = 12.sp, color = Street.c.secondary)
        Gap(30.dp)
    }
}

/** Private parties of up to four: open one, or join with a code. */
@Composable
private fun PartyTab(open: (String) -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.fillMaxWidth().block(Street.pink()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("🎉 party", style = street(26.sp), color = Color.White)
            Text("Up to four friends, every mode. You get a code to share; the host picks the games.", color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
        }
        BigButton(if (busy) "…" else "start a party", brush = Street.pink(), enabled = !busy) {
            busy = true; error = null
            scope.launch {
                runCatching { Online.createParty(app.settings.swears) }.onSuccess(open).onFailure { error = it.message }
                busy = false
            }
        }
        Column(Modifier.fillMaxWidth().card().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("join a party", fontWeight = FontWeight.Bold, color = Street.c.text)
            OutlinedTextField(code, { code = it.uppercase().filter(Char::isLetterOrDigit).take(6) }, label = { Text("party code") }, singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters), modifier = Modifier.fillMaxWidth())
            BigButton("join", brush = Street.jade(), enabled = code.length == 6) { open(code) }
        }
        error?.let { Text(it, color = Street.c.red, fontWeight = FontWeight.Bold) }
        Gap(30.dp)
    }
}

@Composable
private fun ChallengeCard(c: OnlineChallenge, join: (OnlineChallenge) -> Unit) {
    val scope = rememberCoroutineScope()
    val mode = battleMode(c.mode)?.let(::modeInfo)
    Column(Modifier.fillMaxWidth().block(Street.pink()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(c.from); HSpacer(10.dp)
            Text(if (c.party.isNotEmpty()) "${c.from.nickname} invites you to a party 🎉" else "${c.from.nickname} challenges you to ${mode?.title?.lowercase() ?: "a battle"} ${mode?.emoji ?: "⚔️"}",
                color = Color.White, fontWeight = FontWeight.Bold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BigButton(if (c.party.isNotEmpty()) "join" else "accept", Modifier.weight(1f), brush = Street.jade()) { join(c) }
            BigButton("no thanks", Modifier.weight(1f)) { scope.launch { runCatching { Online.decline(c.room) }; Online.refreshInbox() } }
        }
    }
}

@Composable
private fun FriendsTab(challenge: (String, BattleMode, OnlineProfile) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var data by remember { mutableStateOf<OnlineFriends?>(null) }
    var code by remember { mutableStateOf("") }
    var note by remember { mutableStateOf<String?>(null) }
    var challengeMode by remember { mutableStateOf(BattleMode.DUEL) }
    var viewing by remember { mutableStateOf<OnlineProfile?>(null) }
    suspend fun reload() { runCatching { data = Online.friends() }.onFailure { note = it.message } }
    LaunchedEffect(Unit) { while (true) { reload(); delay(10_000) } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val myCode = Online.profile?.friendCode.orEmpty()
        Column(Modifier.fillMaxWidth().card().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("your friend code", color = Street.c.secondary, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(myCode, style = street(30.sp), color = Street.c.text, modifier = Modifier.weight(1f))
                Pill("share", Street.c.red, modifier = Modifier.clickable {
                    ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, "Add me on Měitiān: $myCode"), null))
                })
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(code, { code = it.uppercase().take(8) }, label = { Text("friend's code") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters), modifier = Modifier.weight(1f))
                Pill("add", Street.c.jade, modifier = Modifier.clickable {
                    scope.launch {
                        note = runCatching { if (Online.addFriend(code) == "friends") "You're friends now 🎉" else "Request sent. They'll see it under friends." }
                            .getOrElse { it.message }
                        code = ""
                        reload()
                    }
                })
            }
        }
        note?.let { Text(it, fontWeight = FontWeight.Bold, color = Street.c.text) }
        data?.incoming?.forEach { p ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { ProfileRow(p, highlight = true) }
                HSpacer(8.dp)
                Pill("accept", Street.c.jade, modifier = Modifier.clickable { scope.launch { runCatching { Online.accept(p.id) }; reload(); Online.refreshInbox() } })
            }
        }
        val friends = data?.friends.orEmpty()
        if (friends.isNotEmpty()) {
            SectionTitle("challenge mode")
            ModePicker(2, challengeMode) { challengeMode = it }
        }
        friends.forEach { p ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { ProfileRow(p) { viewing = p } }
                HSpacer(8.dp)
                Pill("⚔️ battle", Street.c.red, modifier = Modifier.clickable {
                    scope.launch {
                        runCatching { Online.challenge(p.id, challengeMode) }
                            .onSuccess { room -> challenge(room, challengeMode, p) }
                            .onFailure { note = it.message }
                    }
                })
            }
        }
        data?.outgoing?.forEach { p -> ProfileRow(p, trailing = "⏳") }
        if (data != null && friends.isEmpty() && data?.incoming.isNullOrEmpty()) {
            Text("No friends yet. Share your code, or type a friend's code above.", color = Street.c.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(20.dp))
        }
        Gap(30.dp)
    }
    viewing?.let { p -> ProfileSheet(p, onClose = { viewing = null }, onRemove = { scope.launch { runCatching { Online.unfriend(p.id) }; viewing = null; reload() } }) }
}

@Composable
private fun ProfileSheet(p: OnlineProfile, onClose: () -> Unit, onRemove: (() -> Unit)? = null) {
    val scope = rememberCoroutineScope()
    var reported by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)).clickable(onClick = onClose), contentAlignment = Alignment.Center) {
        Column(Modifier.padding(24.dp).card().clickable(enabled = false) {}.padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Avatar(p, 110.dp)
            Text("${p.nickname} #${p.tag}", style = street(24.sp), color = Street.c.text)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatBox("HSK ${p.level}", "level"); StatBox("${p.streak}", "streak"); StatBox("${p.rating}", "rating")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatBox("${p.wins}", "wins"); StatBox("${p.losses}", "losses"); StatBox("${p.xpWeek}", "xp this week")
            }
            Text(listOfNotNull(Catalog[p.cosmeticAura]?.let { "${it.symbol} ${it.name}" }, Catalog[p.cosmeticFx]?.let { "${it.symbol} ${it.name}" }).joinToString(" · "),
                color = Street.c.secondary, fontSize = 13.sp)
            onRemove?.let { Text("remove friend", color = Street.c.secondary, fontWeight = FontWeight.Bold, modifier = Modifier.clickable(onClick = it).padding(4.dp)) }
            Text(if (reported) "reported, thanks" else "report picture or name", color = Street.c.red, fontWeight = FontWeight.Bold,
                modifier = Modifier.clickable(enabled = !reported) { scope.launch { runCatching { Online.report(p.id) }; reported = true } }.padding(4.dp))
        }
    }
}

@Composable
private fun RanksTab() {
    var rating by remember { mutableStateOf(false) }
    var friends by remember { mutableStateOf(false) }
    var board by remember { mutableStateOf<Leaderboard?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var viewing by remember { mutableStateOf<OnlineProfile?>(null) }
    LaunchedEffect(rating, friends) {
        board = null; error = null
        runCatching { board = Online.leaderboard(rating, friends) }.onFailure { error = it.message }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill(if (rating) "battle rating" else "xp this week", Street.c.red, modifier = Modifier.clickable { rating = !rating })
            Pill(if (friends) "friends" else "everyone", Street.c.jade, modifier = Modifier.clickable { friends = !friends })
        }
        error?.let { Text(it, color = Street.c.red, fontWeight = FontWeight.Bold) }
        if (board == null && error == null) CircularProgressIndicator(color = Street.c.red, modifier = Modifier.padding(30.dp).align(Alignment.CenterHorizontally))
        board?.let { b ->
            val mine = b.me.profile.id
            if (b.top.none { it.profile.id == mine }) ProfileRow(b.me.profile, value(b.me.profile, rating), rank = b.me.rank.toInt(), highlight = true)
            b.top.forEach { e -> ProfileRow(e.profile, value(e.profile, rating), rank = e.rank.toInt(), highlight = e.profile.id == mine) { viewing = e.profile } }
            if (b.top.isEmpty()) Text("Nobody here yet this week. Learn something and you're first!", color = Street.c.secondary)
            Text("The weekly board starts again every Monday.", fontSize = 12.sp, color = Street.c.secondary)
        }
        Gap(30.dp)
    }
    viewing?.let { ProfileSheet(it, onClose = { viewing = null }) }
}

private fun value(p: OnlineProfile, rating: Boolean) = if (rating) "${p.rating}" else "${p.xpWeek} xp"

@Composable
private fun MeTab() {
    val app = LocalApp.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = Online.profile ?: return
    var name by remember(me.nickname) { mutableStateOf(me.nickname) }
    var note by remember { mutableStateOf<String?>(null) }
    var showCode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch { note = runCatching { Online.uploadAvatar(ctx, uri); "New picture saved (the old one is deleted)." }.getOrElse { it.message } }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.clickable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Avatar(me, 120.dp) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("change picture", Street.c.red, modifier = Modifier.clickable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) })
            if (me.avatar.isNotEmpty()) Pill("remove", Street.c.secondary, modifier = Modifier.clickable { scope.launch { note = runCatching { Online.removeAvatar(); "Picture deleted." }.getOrElse { it.message } } })
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(name, { name = it.take(16) }, label = { Text("nickname") }, singleLine = true, modifier = Modifier.weight(1f))
            Pill("save", Street.c.jade, modifier = Modifier.clickable(enabled = nicknameOk(name) && name != me.nickname) {
                scope.launch { note = runCatching { Online.rename(name); "Saved." }.getOrElse { it.message } }
            })
        }
        note?.let { Text(it, fontWeight = FontWeight.Bold, color = Street.c.text) }
        Column(Modifier.fillMaxWidth().card().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("recovery code", fontWeight = FontWeight.Bold, color = Street.c.text)
            Text("Your profile has no password. This code signs you in on a new phone. Keep it secret.", fontSize = 12.sp, color = Street.c.secondary)
            if (showCode) {
                Text(Online.token.orEmpty(), fontSize = 13.sp, color = Street.c.text)
                Pill("copy", Street.c.red, modifier = Modifier.clickable {
                    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Měitiān recovery code", Online.token))
                    note = "Copied."
                })
            } else Pill("show", Street.c.red, modifier = Modifier.clickable { showCode = true })
        }
        Text(if (confirmDelete) "tap again to delete your online profile for good" else "delete online profile",
            color = Street.c.red, fontWeight = FontWeight.Bold,
            modifier = Modifier.clickable {
                if (!confirmDelete) confirmDelete = true
                else scope.launch { runCatching { Online.deleteAccount() }.onFailure { note = it.message } }
            }.padding(8.dp))
        Text("Your lessons and coins stay on this phone either way.", fontSize = 12.sp, color = Street.c.secondary)
        LaunchedEffect(Unit) { Online.sync(app) }
        Gap(30.dp)
    }
}

// ----- quick match -----

@Composable
private fun QuickMatchSearch(mode: BattleMode, group: Boolean, cancel: () -> Unit, found: (String, List<OnlineProfile>) -> Unit) {
    val app = LocalApp.current
    val info = modeInfo(mode)
    var seconds by remember { mutableIntStateOf(0) }
    var waiting by remember { mutableIntStateOf(1) }
    var problem by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableIntStateOf(0) }
    DisposableEffect(retry) {
        var done = false
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        val ws = Online.queue(mode, group, app.settings.swears, { e ->
            main.post {
                if (done) return@post
                if (e is QueueEvent.Waiting) waiting = e.count.toInt()
                if (e is QueueEvent.Matched) { done = true; Sfx.play(SoundId.GO); found(e.room, e.opponents) }
            }
        }) { code ->
            main.post { if (!done && code != 1000) problem = "Lost the connection to the server." }
        }
        onDispose { done = true; ws.close(1000, "cancel") }
    }
    LaunchedEffect(retry) { seconds = 0; while (true) { delay(1000); seconds++ } }
    val pulse by rememberInfiniteTransition(label = "search").animateFloat(0.85f, 1.15f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "pulse")
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
        Box(Modifier.size(150.dp).scale(if (reduceMotion()) 1f else pulse).clip(CircleShape).background(info.brush()), contentAlignment = Alignment.Center) { Text(info.emoji, fontSize = 60.sp) }
        Text(problem ?: if (group) "looking for a group… $waiting/4" else "looking for an opponent…", style = street(24.sp), color = Street.c.text, textAlign = TextAlign.Center)
        Text(when {
            problem != null -> "Check your internet and try again."
            group && info.minPlayers < 4u -> "${info.title} · ${seconds}s. Starts with three if nobody else shows up."
            group -> "${info.title} · ${seconds}s. This one needs four players."
            else -> "${info.title} · ${seconds}s. The search widens the longer you wait."
        }, color = Street.c.secondary, textAlign = TextAlign.Center)
        if (problem != null) BigButton("try again") { problem = null; retry++ }
        BigButton("cancel", onClick = cancel)
    }
}
