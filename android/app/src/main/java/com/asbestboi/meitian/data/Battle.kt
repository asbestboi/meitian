package com.asbestboi.meitian.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import uniffi.meitian_core.Outcome
import uniffi.meitian_core.battlePool
import uniffi.meitian_core.battleQuestions
import uniffi.meitian_core.blitzWinner
import uniffi.meitian_core.canMatch
import uniffi.meitian_core.duelDamage

/** QR payload, identical to iOS: "meitian-duel:<player id>". */
object DuelQR {
    const val PREFIX = "meitian-duel:"
    fun payload(id: String) = PREFIX + id
    fun playerId(code: String): String? = code.takeIf { it.startsWith(PREFIX) }?.removePrefix(PREFIX)?.takeIf { it.length >= 32 }
}

/**
 * Offline link between two Android phones with Google Nearby Connections (Bluetooth / Wi‑Fi, no server).
 * The phone that scanned the other's code requests the connection, naming who it scanned; the other
 * side only accepts requests that name *its* id, so strangers can't join. Drops reconnect automatically.
 */
class BattleLink(context: Context, private val myId: String) {
    enum class State { Idle, Searching, Connecting, Connected, Reconnecting }

    var state by mutableStateOf(State.Idle)
        private set
    var onMessage: (JSONObject) -> Unit = {}
    var onReconnected: () -> Unit = {}
    var onDropped: () -> Unit = {}

    private val client = Nearby.getConnectionsClient(context)
    private val serviceId = "com.asbestboi.meitian.duel"
    private val found = mutableMapOf<String, String>() // player id → endpoint id
    private var endpoint: String? = null
    private var target: String? = null
    var partner: String? = null
        private set
    private var requested = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var ping: Job? = null

    private val payloads = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, p: Payload) {
            val bytes = p.asBytes() ?: return
            val o = runCatching { JSONObject(String(bytes)) }.getOrNull() ?: return
            if (o.optString("t") != "ping") onMessage(o)
        }
        override fun onPayloadTransferUpdate(id: String, u: PayloadTransferUpdate) {}
    }

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(id: String, info: ConnectionInfo) {
            // name = "<their id>|<who they want>"
            val parts = info.endpointName.split("|")
            val theirId = parts.getOrNull(0) ?: ""
            val wants = parts.getOrNull(1) ?: ""
            val ok = if (info.isIncomingConnection) wants == myId && (partner == null || partner == theirId) else true
            if (ok) client.acceptConnection(id, payloads) else client.rejectConnection(id)
        }

        override fun onConnectionResult(id: String, result: ConnectionResolution) {
            if (result.status.isSuccess) {
                val wasReconnecting = state == State.Reconnecting
                endpoint = id
                state = State.Connected
                requested = false
                client.stopAdvertising(); client.stopDiscovery()
                ping?.cancel()
                ping = scope.launch { while (true) { delay(2000); send(JSONObject().put("t", "ping")) } }
                if (wasReconnecting) onReconnected()
            } else {
                requested = false
                scope.launch { delay(1500); requestIfFound() }
            }
        }

        override fun onDisconnected(id: String) {
            if (id != endpoint) return
            endpoint = null
            ping?.cancel()
            onDropped()
            state = State.Reconnecting
            found.clear()
            startDiscovery()
        }
    }

    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) {
            found[info.endpointName.substringBefore("|")] = id
            requestIfFound()
        }
        override fun onEndpointLost(id: String) { found.values.remove(id) }
    }

    fun start() {
        state = State.Searching
        startDiscovery()
    }

    private fun startDiscovery() {
        client.stopAdvertising(); client.stopDiscovery()
        client.startAdvertising("$myId|", serviceId, lifecycle, AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build())
        client.startDiscovery(serviceId, discovery, DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build())
    }

    /** After scanning the opponent's QR code. */
    fun connect(to: String) {
        if (to == myId) return
        target = to
        if (state != State.Connected) state = State.Connecting
        requestIfFound()
    }

    fun setPartner(id: String) { if (id != myId) partner = id }

    private fun requestIfFound() {
        if (state == State.Connected || requested) return
        // before pairing: whoever scanned asks; after: the smaller id asks, so both never ask at once
        val who = partner ?: target ?: return
        if (partner != null && myId > partner!!) return
        val ep = found[who] ?: return
        requested = true
        client.requestConnection("$myId|$who", ep, lifecycle).addOnFailureListener {
            requested = false
            scope.launch { delay(1500); requestIfFound() }
        }
    }

    fun send(o: JSONObject) {
        val ep = endpoint ?: return
        client.sendPayload(ep, Payload.fromBytes(o.toString().toByteArray()))
    }

    fun stop() {
        ping?.cancel()
        client.stopAllEndpoints(); client.stopAdvertising(); client.stopDiscovery()
        state = State.Idle
        scope.cancel()
    }
}

data class WireQ(val wordId: String, val kind: Int, val options: List<String>) {
    fun question(): Question? {
        val w = Words[wordId] ?: return null
        val opts = options.mapNotNull { Words[it] }
        if (opts.size != options.size) return null
        return Question(w, if (kind == 0) Kind.HanziToMeaning else Kind.MeaningToHanzi, opts)
    }
    fun json() = JSONObject().put("w", wordId).put("k", kind).put("o", JSONArray(options))
    companion object {
        fun from(o: JSONObject) = WireQ(o.getString("w"), o.getInt("k"), o.getJSONArray("o").let { a -> (0 until a.length()).map { a.getString(it) } })
    }
}

enum class Mode(val title: String, val emoji: String, val blurb: String) {
    Duel("Duel", "⚔️", "Same question for both. First right answer hits. Knock their HP to 0!"),
    Blitz("Blitz", "⚡", "45 seconds. Answer as many as you can. Most correct wins."),
}

/** Networked match. Host (smaller id) referees; reaction time is measured on each phone. */
class Match(val link: BattleLink, val me: PlayerCard, private val onFinish: (Outcome, PlayerCard, Int, Int?) -> Int) {
    enum class Phase { Lobby, Countdown, Playing, RoundResult, Finished }

    var opponent by mutableStateOf<PlayerCard?>(null)
    var incompatible by mutableStateOf(false)
    var phase by mutableStateOf(Phase.Lobby)
    var count by mutableIntStateOf(3)
    var mode by mutableStateOf(Mode.Duel)
    var questions by mutableStateOf(listOf<Question>())
    private var wire = listOf<WireQ>()
    var index by mutableIntStateOf(0)
    val hp = mutableStateMapOf<String, Int>()
    var myPick by mutableStateOf<uniffi.meitian_core.CoreWord?>(null)
    var lockedOut by mutableStateOf(false)
    var roundWinner by mutableStateOf<String?>(null)
    var lastDamage by mutableIntStateOf(0)
    var hitTick by mutableIntStateOf(0)
    var myScore by mutableIntStateOf(0)
    var oppScore by mutableIntStateOf(0)
    var myDone by mutableStateOf(false)
    private var oppDone = false
    var blitzEnds by mutableStateOf(0L)
    var winner by mutableStateOf<String?>(null)
    var finished by mutableStateOf(false)
    var coins by mutableIntStateOf(0)
    var fastest by mutableStateOf<Int?>(null)
    var damageDealt by mutableIntStateOf(0)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var token = 0
    private var shownAt = 0L
    private val answers = mutableMapOf<String, Pair<Boolean, Int>>()
    private var resolveScheduled = false

    val isHost get() = opponent?.let { me.id < it.id } ?: false
    val current get() = questions.getOrNull(if (questions.isEmpty()) 0 else index % questions.size)
    fun hpOf(id: String?) = id?.let { hp[it] } ?: 100

    init {
        link.onMessage = { handle(it) }
        link.onDropped = { if (mode == Mode.Duel && inGame) token++ }
        link.onReconnected = { reconnected() }
    }

    private val inGame get() = phase == Phase.Countdown || phase == Phase.Playing || phase == Phase.RoundResult

    fun hello() = link.send(JSONObject().put("t", "hello").put("card", me.json()))

    private fun send(t: String, f: JSONObject.() -> Unit = {}) = link.send(JSONObject().put("t", t).apply(f))

    fun hostStart(m: Mode) {
        val o = opponent ?: return
        if (!isHost || incompatible) return
        val pool = battlePool(me.level.toUByte(), o.level.toUByte(), me.swearsOn, o.swearsOn)
        val list = battleQuestions(pool, if (m == Mode.Duel) 40u else 80u).map { WireQ(it.wordId, it.kind.toInt(), it.optionIds) }
        send("start") { put("mode", m.name); put("q", JSONArray(list.map { it.json() })) }
        begin(m, list)
    }

    private fun begin(m: Mode, list: List<WireQ>) {
        mode = m; wire = list; questions = list.mapNotNull { it.question() }; index = 0
        hp.clear(); hp[me.id] = 100; opponent?.let { hp[it.id] = 100 }
        myScore = 0; oppScore = 0; myDone = false; oppDone = false; winner = null; finished = false
        coins = 0; fastest = null; damageDealt = 0
        val t = ++token
        phase = Phase.Countdown
        scope.launch {
            for (n in 3 downTo 1) { if (t != token) return@launch; count = n; Sfx.play(Sfx.Sound.Tick); delay(800) }
            if (t != token) return@launch
            if (mode == Mode.Duel) { if (isHost) hostRound(0) } else startBlitz()
        }
    }

    private fun hostRound(i: Int) {
        send("round") { put("i", i) }
        showRound(i)
        val t = token
        scope.launch { delay(10_000); if (t == token && index == i && phase == Phase.Playing) resolve(i) }
    }

    private fun showRound(i: Int) {
        index = i; myPick = null; lockedOut = false; roundWinner = null; answers.clear(); resolveScheduled = false
        token++; shownAt = System.currentTimeMillis(); phase = Phase.Playing
    }

    fun pick(o: uniffi.meitian_core.CoreWord) {
        val q = current ?: return
        if (phase != Phase.Playing || myPick != null || lockedOut || myDone) return
        val right = o.id == q.word.id
        val ms = (System.currentTimeMillis() - shownAt).toInt()
        myPick = o
        Sfx.play(if (right) Sfx.Sound.Correct else Sfx.Sound.Wrong)
        if (mode == Mode.Blitz) { blitz(right); return }
        if (!right) lockedOut = true else fastest = minOf(fastest ?: Int.MAX_VALUE, ms)
        if (isHost) receive(me.id, index, right, ms) else send("answer") { put("i", index); put("ok", right); put("ms", ms) }
    }

    private fun receive(id: String, i: Int, right: Boolean, ms: Int) {
        if (!isHost || i != index || phase != Phase.Playing || answers.containsKey(id)) return
        answers[id] = right to ms
        if (right && !resolveScheduled) {
            resolveScheduled = true
            val t = token
            scope.launch { delay(300); if (t == token) resolve(i) }
        } else if (answers.size == 2 && answers.values.none { it.first }) resolve(i)
    }

    private fun resolve(i: Int) {
        val o = opponent ?: return
        if (!isHost || phase != Phase.Playing) return
        val best = answers.filter { it.value.first }.minByOrNull { it.value.second }
        var dmg = 0
        if (best != null) {
            dmg = duelDamage(best.value.second.toUInt()).toInt()
            val target = if (best.key == me.id) o.id else me.id
            hp[target] = (hpOf(target) - dmg).coerceAtLeast(0)
        }
        send("result") { put("w", best?.key ?: ""); put("hp", JSONObject(hp.toMap())); put("d", dmg) }
        applyResult(best?.key, hp.toMap(), dmg)
        val t = token
        scope.launch {
            delay(1500)
            if (t != token) return@launch
            val dead = hp.entries.firstOrNull { it.value <= 0 }?.key
            if (dead != null) { val w = if (dead == me.id) o.id else me.id; send("finished") { put("w", w) }; finish(w) } else hostRound(i + 1)
        }
    }

    private fun applyResult(w: String?, newHp: Map<String, Int>, dmg: Int) {
        newHp.forEach { (k, v) -> hp[k] = v }
        roundWinner = w; lastDamage = dmg
        if (w == me.id) damageDealt += dmg
        if (w != null) { hitTick++; Sfx.play(Sfx.Sound.Hit) }
        phase = Phase.RoundResult
    }

    private fun startBlitz() {
        showRound(0)
        blitzEnds = System.currentTimeMillis() + 45_000
        val t = token
        scope.launch {
            delay(45_000)
            if (t != token || myDone) return@launch
            myDone = true
            send("progress") { put("s", myScore); put("done", true) }
            checkBlitz()
        }
    }

    private fun blitz(right: Boolean) {
        if (right) { myScore++; send("progress") { put("s", myScore); put("done", false) } } else lockedOut = true
        scope.launch {
            delay(if (right) 350 else 1000)
            if (mode == Mode.Blitz && !myDone && phase == Phase.Playing) { index++; myPick = null; lockedOut = false }
        }
    }

    private fun checkBlitz() {
        val o = opponent ?: return
        if (!myDone || !oppDone || finished) return
        val r = blitzWinner(myScore.toUInt(), oppScore.toUInt())
        finish(when (r) { true -> me.id; false -> o.id; null -> null })
    }

    private fun finish(w: String?) {
        if (finished) return
        token++
        winner = w; finished = true; phase = Phase.Finished
        val outcome = when (w) { null -> Outcome.DRAW; me.id -> Outcome.WIN; else -> Outcome.LOSS }
        val bonus = if (mode == Mode.Duel) hpOf(me.id) / 5 else myScore
        coins = opponent?.let { onFinish(outcome, it, bonus, fastest) } ?: 0
        if (outcome == Outcome.LOSS) Sfx.play(Sfx.Sound.Lose)
    }

    fun backToLobby(notify: Boolean = true) {
        token++
        if (notify) send("lobby")
        phase = Phase.Lobby; finished = false; winner = null
    }

    private fun reconnected() {
        hello()
        if (mode == Mode.Blitz && inGame) send("progress") { put("s", myScore); put("done", myDone) }
        if (!isHost) return
        send("resume") {
            put("mode", mode.name); put("q", JSONArray(wire.map { it.json() })); put("i", index); put("hp", JSONObject(hp.toMap()))
            put("inGame", inGame); put("finished", finished); put("w", winner ?: "")
        }
        val o = opponent ?: return
        if (mode == Mode.Duel && inGame) {
            val dead = hp.entries.firstOrNull { it.value <= 0 }?.key
            if (dead != null) { val w = if (dead == me.id) o.id else me.id; send("finished") { put("w", w) }; finish(w); return }
            val t = token
            scope.launch { delay(1200); if (t == token && link.state == BattleLink.State.Connected) hostRound(index) }
        }
    }

    private fun handle(o: JSONObject) {
        when (o.optString("t")) {
            "hello" -> {
                val card = PlayerCard.from(o.getJSONObject("card"))
                val first = opponent == null
                opponent = card
                if (!canMatch(me.swearsOn, card.swearsOn)) incompatible = true else link.setPartner(card.id)
                if (first) hello()
            }
            "start" -> begin(Mode.valueOf(o.getString("mode")), o.getJSONArray("q").let { a -> (0 until a.length()).map { WireQ.from(a.getJSONObject(it)) } })
            "round" -> if (!isHost) showRound(o.getInt("i"))
            "answer" -> opponent?.let { receive(it.id, o.getInt("i"), o.getBoolean("ok"), o.getInt("ms")) }
            "result" -> if (!isHost) {
                val h = o.getJSONObject("hp")
                applyResult(o.optString("w").ifEmpty { null }, h.keys().asSequence().associateWith { h.getInt(it) }, o.getInt("d"))
            }
            "progress" -> { oppScore = o.getInt("s"); if (o.getBoolean("done")) { oppDone = true; checkBlitz() } }
            "finished" -> finish(o.optString("w").ifEmpty { null })
            "lobby" -> backToLobby(false)
            "resume" -> if (!isHost) {
                if (o.getBoolean("finished")) { finish(o.optString("w").ifEmpty { null }); return }
                if (!o.getBoolean("inGame")) { if (inGame) backToLobby(false); return }
                if (Mode.valueOf(o.getString("mode")) != Mode.Duel) return
                val list = o.getJSONArray("q").let { a -> (0 until a.length()).map { WireQ.from(a.getJSONObject(it)) } }
                if (list != wire) { wire = list; questions = list.mapNotNull { it.question() } }
                mode = Mode.Duel
                val h = o.getJSONObject("hp"); h.keys().forEach { hp[it] = h.getInt(it) }
                index = o.getInt("i"); token++; phase = Phase.RoundResult
            }
        }
    }

    fun close() { scope.cancel(); link.stop() }
}
