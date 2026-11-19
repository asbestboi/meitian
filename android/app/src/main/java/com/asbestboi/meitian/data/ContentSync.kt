package com.asbestboi.meitian.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import uniffi.meitian_core.ContentStats
import uniffi.meitian_core.PackInfo
import uniffi.meitian_core.contentClear
import uniffi.meitian_core.contentLoad
import uniffi.meitian_core.contentStats
import uniffi.meitian_core.packsForLevel
import uniffi.meitian_core.parseManifest
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Downloads learning content (HSK words, sentences, stories) from the meitian-content site,
 * caches it in filesDir/content and loads it into the Rust core. Works offline from the cache.
 */
object ContentSync {
    const val DEFAULT_URL = "https://asbestboi.github.io/meitian-content/"

    sealed interface Status {
        data object Idle : Status
        data object Checking : Status
        data class Downloading(val done: Int, val total: Int) : Status
        data object Ready : Status
        data class Failed(val message: String) : Status
    }

    var status by mutableStateOf<Status>(Status.Idle); private set
    var stats by mutableStateOf<ContentStats>(contentStats()); private set
    var credits by mutableStateOf(listOf<String>()); private set
    /** Bumped after new content loads. */
    var generation by mutableIntStateOf(0); private set

    private val loaded = mutableSetOf<String>()
    private val mutex = Mutex()

    private fun prefs(c: Context) = c.getSharedPreferences("content", Context.MODE_PRIVATE)
    private fun dir(c: Context) = File(c.filesDir, "content").apply { mkdirs() }
    private fun file(c: Context, p: PackInfo) = File(dir(c), p.url.substringAfterLast('/'))

    fun baseUrl(c: Context): String = prefs(c).getString("url", null)?.takeIf { it.isNotBlank() } ?: DEFAULT_URL
    fun allLevels(c: Context) = prefs(c).getBoolean("all", false)
    fun setAllLevels(c: Context, on: Boolean) = prefs(c).edit().putBoolean("all", on).apply()
    fun cacheBytes(c: Context): Long = dir(c).listFiles()?.sumOf { it.length() } ?: 0L

    /** Load the cache, then refresh from the network if the last check is over a day old. */
    suspend fun start(c: Context, level: Int) {
        loadCached(c)
        val last = prefs(c).getLong("checked", 0)
        if (System.currentTimeMillis() - last > 24 * 3600_000L || stats.sentences == 0u) refresh(c, level)
        else status = Status.Ready
    }

    suspend fun loadCached(c: Context) {
        val m = File(dir(c), "manifest.json").takeIf { it.exists() } ?: return
        val manifest = runCatching { parseManifest(m.readText()) }.getOrNull() ?: return
        credits = manifest.credits
        load(c, manifest.packs.filter { file(c, it).exists() })
    }

    suspend fun refresh(c: Context, level: Int) {
        if (mutex.isLocked) return
        mutex.withLock {
            status = Status.Checking
            try {
                val base = baseUrl(c).let { if (it.endsWith("/")) it else "$it/" }
                val manifestBytes = fetch(URL(URL(base), "manifest.json"))
                val manifest = parseManifest(String(manifestBytes))
                val wanted = packsForLevel(manifest, level.coerceAtLeast(1).toUByte(), allLevels(c))
                val missing = withContext(Dispatchers.IO) { wanted.filter { !isCurrent(c, it) } }
                missing.forEachIndexed { i, pack ->
                    status = Status.Downloading(i, missing.size)
                    val bytes = fetch(URL(URL(base), pack.url))
                    if (pack.sha256.isNotEmpty() && sha256(bytes) != pack.sha256) error("Download of ${pack.id} was damaged. Try again.")
                    withContext(Dispatchers.IO) { file(c, pack).writeBytes(bytes) }
                    loaded.remove(pack.url)
                }
                withContext(Dispatchers.IO) { File(dir(c), "manifest.json").writeBytes(manifestBytes) }
                credits = manifest.credits
                prefs(c).edit().putLong("checked", System.currentTimeMillis()).apply()
                load(c, wanted)
                status = Status.Ready
            } catch (e: Exception) {
                status = if (stats.sentences > 0u) Status.Ready
                else Status.Failed(e.message?.takeIf { it.startsWith("Download") } ?: "Couldn't download lessons. Using the built-in words.")
            }
        }
    }

    fun clear(c: Context) {
        dir(c).deleteRecursively()
        prefs(c).edit().remove("checked").apply()
        contentClear()
        loaded.clear()
        afterLoad()
        status = Status.Idle
    }

    private suspend fun load(c: Context, packs: List<PackInfo>) {
        val todo = packs.filter { it.url !in loaded }.sortedBy { if (it.kind == "words") 0 else 1 }
        if (todo.isEmpty()) return
        val ok = withContext(Dispatchers.Default) {
            todo.filter { p -> runCatching { contentLoad(p.kind, file(c, p).readText()) }.isSuccess }.map { it.url }
        }
        loaded += ok
        afterLoad()
    }

    private fun afterLoad() {
        Words.reload()
        stats = contentStats()
        generation++
    }

    private fun isCurrent(c: Context, p: PackInfo): Boolean {
        val f = file(c, p)
        if (!f.exists()) return false
        return p.sha256.isEmpty() || sha256(f.readBytes()) == p.sha256
    }

    private suspend fun fetch(url: URL): ByteArray = withContext(Dispatchers.IO) {
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 30_000
        conn.useCaches = false
        try {
            if (conn.responseCode !in 200..299) error("The content site answered ${conn.responseCode}.")
            conn.inputStream.use { it.readBytes() }
        } finally {
            conn.disconnect()
        }
    }

    private fun sha256(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
}
