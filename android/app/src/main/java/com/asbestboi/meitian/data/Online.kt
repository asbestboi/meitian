package com.asbestboi.meitian.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import uniffi.meitian_core.Leaderboard
import uniffi.meitian_core.BattleMode
import uniffi.meitian_core.QueueEvent
import uniffi.meitian_core.modeInfo
import uniffi.meitian_core.nicknameFrom
import uniffi.meitian_core.onlineParseParty
import uniffi.meitian_core.queueEvent
import uniffi.meitian_core.queuePath
import uniffi.meitian_core.OnlineException
import uniffi.meitian_core.OnlineFriends
import uniffi.meitian_core.OnlineInbox
import uniffi.meitian_core.OnlineProfile
import uniffi.meitian_core.onlineCheck
import uniffi.meitian_core.onlineParseAccount
import uniffi.meitian_core.onlineParseFriends
import uniffi.meitian_core.onlineParseInbox
import uniffi.meitian_core.onlineParseLeaderboard
import uniffi.meitian_core.onlineParseProfile
import uniffi.meitian_core.onlineParseSpin
import uniffi.meitian_core.ServerSpin
import uniffi.meitian_core.ServerState
import uniffi.meitian_core.serverState
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Online profile, friends, leaderboards and quick match, talking to the Měitiān server (a Cloudflare Worker).
 * The account is just a nickname: the server hands out a token (`id.secret`) that's kept in the app's private
 * storage and doubles as the recovery code for moving to a new phone.
 */
object Online {
    const val DEFAULT_URL = "https://meitian.meitian-server.workers.dev"

    var profile by mutableStateOf<OnlineProfile?>(null); private set
    var inbox by mutableStateOf<OnlineInbox?>(null); private set

    private lateinit var prefs: android.content.SharedPreferences
    private var lastSync = 0L

    val http: OkHttpClient by lazy { OkHttpClient.Builder().pingInterval(20, TimeUnit.SECONDS).build() }

    fun init(c: Context) {
        if (::prefs.isInitialized) return
        prefs = c.getSharedPreferences("online", Context.MODE_PRIVATE)
    }

    val token: String? get() = prefs.getString("token", null)
    val signedIn get() = token != null
    var baseUrl: String
        get() = prefs.getString("url", null)?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() } ?: DEFAULT_URL
        set(v) = prefs.edit().putString("url", v.trim()).apply()

    fun avatarUrl(p: OnlineProfile?): String? = p?.avatar?.takeIf { it.isNotEmpty() }?.let { baseUrl + it }

    /** One request; returns the body, or throws [OnlineException] with a readable reason. */
    private suspend fun request(method: String, path: String, body: Any? = null, auth: Boolean = true): String =
        withContext(Dispatchers.IO) {
            val conn = URL(baseUrl + path).openConnection() as HttpURLConnection
            try {
                conn.requestMethod = method
                conn.connectTimeout = 10_000
                conn.readTimeout = 20_000
                if (auth) token?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
                when (body) {
                    is ByteArray -> {
                        conn.doOutput = true
                        conn.setRequestProperty("Content-Type", "image/jpeg")
                        conn.outputStream.use { it.write(body) }
                    }
                    is JSONObject -> {
                        conn.doOutput = true
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.outputStream.use { it.write(body.toString().toByteArray()) }
                    }
                }
                val status = conn.responseCode
                val text = (if (status in 200..299) conn.inputStream else conn.errorStream)?.use { String(it.readBytes()) } ?: ""
                onlineCheck(status.toUShort(), text)
                text
            } catch (e: OnlineException) {
                throw e
            } catch (e: Exception) {
                throw OnlineException.Server(0u, "no connection to the server")
            } finally {
                conn.disconnect()
            }
        }

    // ----- account -----

    suspend fun register(nickname: String) {
        val acc = onlineParseAccount(request("POST", "/v1/register", JSONObject().put("nickname", nickname), auth = false))
        prefs.edit().putString("token", acc.token).apply()
        profile = acc.profile
    }

    /** Sign in on this phone with a recovery code from another one. */
    suspend fun recover(code: String) {
        val old = token
        prefs.edit().putString("token", code.trim()).apply()
        try {
            refreshMe()
        } catch (e: Exception) {
            prefs.edit().apply { if (old == null) remove("token") else putString("token", old) }.apply()
            throw e
        }
    }

    suspend fun refreshMe() {
        if (!signedIn) return
        profile = onlineParseProfile(request("GET", "/v1/me"))
    }

    suspend fun rename(nickname: String) {
        profile = onlineParseProfile(request("PUT", "/v1/me", JSONObject().put("nickname", nickname)))
    }

    /** Sends level, streak, XP and equipped cosmetics (at most once a minute unless forced). */
    suspend fun sync(app: AppState, force: Boolean = false) {
        if (!signedIn) return
        val now = System.currentTimeMillis()
        if (!force && now - lastSync < 60_000) return
        lastSync = now
        val card = app.myCard()
        val body = JSONObject()
            .put("level", app.currentLevel)
            .put("streak", app.streak)
            .put("xpTotal", app.xp)
            .put("cosmetics", JSONObject().put("aura", card.aura ?: "au.none").put("fx", card.effect).put("title", card.title))
        runCatching { profile = onlineParseProfile(request("PUT", "/v1/me", body)) }
    }

    suspend fun deleteAccount() {
        request("DELETE", "/v1/me")
        signOut()
    }

    fun signOut() {
        prefs.edit().remove("token").apply()
        profile = null
        inbox = null
    }

    // ----- profile picture -----

    /** Square-crops and shrinks the picked photo to 256 px, then uploads it (replacing the old one). */
    suspend fun uploadAvatar(c: Context, uri: Uri) {
        val jpeg = withContext(Dispatchers.Default) {
            val src = c.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
                ?: throw OnlineException.Server(0u, "couldn't read that picture")
            val side = minOf(src.width, src.height)
            val square = Bitmap.createBitmap(src, (src.width - side) / 2, (src.height - side) / 2, side, side)
            val small = Bitmap.createScaledBitmap(square, 256, 256, true)
            ByteArrayOutputStream().also { small.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
        }
        request("PUT", "/v1/me/avatar", jpeg)
        refreshMe()
    }

    suspend fun removeAvatar() {
        request("DELETE", "/v1/me/avatar")
        refreshMe()
    }

    // ----- people -----

    suspend fun player(id: String): OnlineProfile = onlineParseProfile(request("GET", "/v1/players/$id"))
    suspend fun report(id: String) { request("POST", "/v1/report/$id") }
    suspend fun friends(): OnlineFriends = onlineParseFriends(request("GET", "/v1/friends"))

    /** Returns "friends" or "requested". */
    suspend fun addFriend(code: String): String =
        JSONObject(request("POST", "/v1/friends", JSONObject().put("code", code))).optString("status")

    suspend fun accept(id: String) { request("POST", "/v1/friends/$id/accept") }
    suspend fun unfriend(id: String) { request("DELETE", "/v1/friends/$id") }

    suspend fun challenge(friendId: String, mode: BattleMode): String =
        JSONObject(request("POST", "/v1/challenge", JSONObject().put("friendId", friendId).put("mode", modeInfo(mode).wire))).getString("room")

    /** Records a slot machine spin; null when offline or signed out. */
    suspend fun spin(count: Int): ServerSpin? {
        if (!::prefs.isInitialized || !signedIn) return null
        return runCatching { onlineParseSpin(request("POST", "/v1/spin", JSONObject().put("count", count))) }.getOrNull()
    }

    // ----- parties -----

    /** Opens a private party and returns its code. */
    suspend fun createParty(swears: Boolean): String = onlineParseParty(request("POST", "/v1/party", JSONObject().put("swears", swears)))
    suspend fun inviteToParty(code: String, friendId: String) { request("POST", "/v1/party/$code/invite", JSONObject().put("friendId", friendId)) }

    /** Can we battle? (Battles need internet and an up-to-date server; lessons don't.) */
    suspend fun state(): ServerState = serverState(runCatching { request("GET", "/", auth = false) }.getOrNull())

    /** Creates the online profile from the learner's name, if there isn't one yet. */
    suspend fun ensureAccount(name: String) { if (!signedIn) register(nicknameFrom(name)) }

    suspend fun decline(room: String) { request("POST", "/v1/challenge/$room/decline") }

    suspend fun refreshInbox() {
        if (!signedIn) return
        runCatching { inbox = onlineParseInbox(request("GET", "/v1/inbox")) }
    }

    suspend fun leaderboard(rating: Boolean, friends: Boolean): Leaderboard =
        onlineParseLeaderboard(request("GET", "/v1/leaderboard?board=${if (rating) "rating" else "week"}&scope=${if (friends) "friends" else "global"}"))

    // ----- live sockets -----

    private fun wsUrl(path: String) = baseUrl.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") + path

    /**
     * Opens a socket and hands every message and the close/failure to the callbacks on OkHttp's thread.
     * A refused upgrade closes with 4000 + the HTTP status, a lost connection with 1006.
     */
    fun socket(path: String, onText: (String) -> Unit, closed: (code: Int) -> Unit): WebSocket {
        val req = Request.Builder().url(wsUrl(path)).header("Authorization", "Bearer ${token ?: ""}").build()
        return http.newWebSocket(req, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) = onText(text)
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(1000, null); closed(code) }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = closed(response?.code?.let { 4000 + it } ?: 1006)
        })
    }

    fun queue(mode: BattleMode, group: Boolean, swears: Boolean, onEvent: (QueueEvent) -> Unit, closed: (Int) -> Unit) =
        socket(queuePath(mode, group, swears), { onEvent(queueEvent(it)) }, closed)
}
