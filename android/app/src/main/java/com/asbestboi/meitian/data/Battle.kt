package com.asbestboi.meitian.data

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import uniffi.meitian_core.Battle
import uniffi.meitian_core.BattleAnswer
import uniffi.meitian_core.BattleMode
import uniffi.meitian_core.BattleOut
import uniffi.meitian_core.BattlePlayer
import uniffi.meitian_core.BattleResult
import uniffi.meitian_core.BattleView
import uniffi.meitian_core.SoundId

/** Their player card, once their hello arrived. */
val BattlePlayer.playerCard: PlayerCard?
    get() = card.takeIf { it.isNotEmpty() }?.let { runCatching { PlayerCard.from(JSONObject(it)) }.getOrNull() }

/**
 * One battle over a server room: connects the socket to the Rust core's battle engine (which referees, keeps the
 * state and decides everything) and exposes its view to Compose. Reconnects by itself when the network drops.
 */
class BattleSession(
    private val path: String,
    val me: PlayerCard,
    auto: BattleMode?,
    /** Records the result and returns the coins it paid. */
    private val payOut: (BattleResult, BattlePlayer?) -> Int,
) {
    class Hit(val tick: Int, val attacker: String, val targets: List<String>, val damage: Int)

    private val engine = Battle(me.json().toString(), auto)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var socket: okhttp3.WebSocket? = null
    private var attempt = 0
    private var stopped = false

    var view by mutableStateOf<BattleView>(engine.view(now()))
        private set
    /** The last hit that landed (drives the effect animation). */
    var hit by mutableStateOf<Hit?>(null)
        private set
    var coins by mutableIntStateOf(0)
        private set

    private fun now() = SystemClock.elapsedRealtime().toULong()

    fun open() {
        connect()
        scope.launch { while (true) { handle(engine.tick(now())); delay(100) } }
    }

    private fun connect() {
        if (stopped) return
        socket = Online.socket(path, { text -> scope.launch { attempt = 0; handle(engine.onText(text, now())) } }) { code -> scope.launch { closed(code) } }
    }

    private fun closed(code: Int) {
        socket = null
        if (stopped || code == 4000) return           // left, or replaced by a newer connection
        if (code in 4400..4499) { stopped = true; handle(engine.onRefused((code - 4000).toUShort())); return }
        handle(engine.onClosed())
        val wait = minOf(8_000L, 500L shl minOf(attempt++, 4))
        scope.launch { delay(wait); connect() }
    }

    private fun handle(out: List<BattleOut>) {
        for (o in out) when (o) {
            is BattleOut.Send -> socket?.send(o.json)
            is BattleOut.Sound -> Sfx.play(o.sound)
            is BattleOut.Hit -> {
                hit = Hit((hit?.tick ?: 0) + 1, o.attacker, o.targets, o.damage.toInt())
                val effect = view.players.firstOrNull { it.id == o.attacker }?.playerCard?.effect ?: "fx.boom"
                // lands with the projectile
                scope.launch { delay(380); Sfx.playHit(effect) }
            }
            is BattleOut.Finished -> {
                val v = engine.view(now())
                coins = payOut(o.result, v.players.firstOrNull { it.id == o.result.rival })
                if (coins > 0) scope.launch { delay(900); Sfx.play(SoundId.COIN) }
            }
        }
        view = engine.view(now())
    }

    fun start(mode: BattleMode) = handle(engine.start(mode, now()))
    fun answer(a: BattleAnswer) = handle(engine.answer(a, now()))
    fun rematch() = handle(engine.rematch())

    /** Closes the battle for good. */
    fun leave() {
        if (!stopped) engine.leave().forEach { if (it is BattleOut.Send) socket?.send(it.json) }
        stopped = true
        socket?.close(1000, "bye")
        socket = null
        scope.cancel()
    }
}
