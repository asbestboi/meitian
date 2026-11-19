package com.asbestboi.meitian.data

import android.content.Context
import android.content.Intent
import android.icu.text.Transliterator
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import uniffi.meitian_core.speechMatches
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

/** Mandarin text-to-speech. */
object Speaker {
    private var tts: TextToSpeech? = null
    private var ready = false

    fun init(context: Context) {
        if (tts != null) return
        tts = TextToSpeech(context.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.SIMPLIFIED_CHINESE
                ready = true
            }
        }
    }

    fun say(text: String, slow: Boolean = false) {
        val t = tts ?: return
        if (!ready) return
        t.setSpeechRate(if (slow) 0.6f else 0.9f)
        t.speak(text, TextToSpeech.QUEUE_FLUSH, null, "say")
    }
}

/** Synthesized lo-fi sound effects (same recipes as iOS), played from static AudioTracks. */
object Sfx {
    enum class Sound { Correct, Wrong, Hit, Coin, Win, Lose, Tick, Go, Swoosh, MicOn, MicOff }

    var enabled = true
    private const val RATE = 44100
    private val cache = HashMap<Sound, ShortArray>()

    private data class Note(val f: Double, val d: Double, val wave: Int = 0, val bend: Double = 0.0, val vol: Double = 1.0)

    private fun tones(notes: List<Note>): FloatArray {
        val out = ArrayList<Float>()
        for (n in notes) {
            val count = (n.d * RATE).toInt()
            var phase = 0.0
            for (i in 0 until count) {
                val t = i.toDouble() / RATE
                phase += (n.f + n.bend * (t / n.d)) / RATE
                val x = phase % 1.0
                var v = when (n.wave) {
                    1 -> 1 - 4 * abs(x - 0.5)
                    2 -> if (x < 0.5) 0.6 else -0.6
                    else -> sin(2 * PI * x)
                }
                v = (v * 8).roundToInt() / 8.0
                val env = minOf(1.0, t / 0.005) * exp(-3.5 * t / n.d)
                out += (v * env * n.vol * 0.5).toFloat()
            }
        }
        return out.toFloatArray()
    }

    private fun noise(d: Double, vol: Double, sweep: Boolean = false): FloatArray {
        val count = (d * RATE).toInt()
        var last = 0.0
        return FloatArray(count) { i ->
            val t = i.toDouble() / RATE
            val a = if (sweep) 0.05 + 0.6 * (t / d) else 0.35
            last += a * (Random.nextDouble(-1.0, 1.0) - last)
            val env = if (sweep) sin(PI * t / d) else exp(-6 * t / d)
            (last * env * vol).toFloat()
        }
    }

    private fun mix(a: FloatArray, b: FloatArray) = FloatArray(maxOf(a.size, b.size)) { i ->
        ((a.getOrElse(i) { 0f }) + (b.getOrElse(i) { 0f })).coerceIn(-1f, 1f)
    }

    private fun render(s: Sound): FloatArray = when (s) {
        Sound.Correct -> tones(listOf(Note(880.0, 0.08, 1), Note(1320.0, 0.14, 1)))
        Sound.Wrong -> tones(listOf(Note(200.0, 0.24, 2, -80.0, 0.6)))
        Sound.Hit -> mix(noise(0.14, 0.9), tones(listOf(Note(95.0, 0.18, 0, -40.0))))
        Sound.Coin -> tones(listOf(Note(1568.0, 0.06, 2, vol = 0.5), Note(2093.0, 0.16, 2, vol = 0.5)))
        Sound.Win -> tones(listOf(523.0, 659.0, 784.0, 1047.0).map { Note(it, 0.11, 1) } + Note(1047.0, 0.25, 1))
        Sound.Lose -> tones(listOf(392.0, 330.0, 262.0).map { Note(it, 0.16, 2, vol = 0.55) })
        Sound.Tick -> tones(listOf(Note(660.0, 0.07, 1, vol = 0.7)))
        Sound.Go -> tones(listOf(Note(990.0, 0.2, 1)))
        Sound.Swoosh -> noise(0.16, 0.35, sweep = true)
        Sound.MicOn -> tones(listOf(Note(740.0, 0.06), Note(1110.0, 0.08)))
        Sound.MicOff -> tones(listOf(Note(1110.0, 0.06), Note(740.0, 0.08)))
    }

    fun play(s: Sound) {
        if (!enabled) return
        val pcm = cache.getOrPut(s) { render(s).map { (it * 0.55f * Short.MAX_VALUE).toInt().toShort() }.toShortArray() }
        Thread {
            runCatching {
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(pcm.size * 2)
                    .build()
                track.write(pcm, 0, pcm.size)
                track.play()
                Thread.sleep((pcm.size * 1000L / RATE) + 60)
                track.release()
            }
        }.start()
    }
}

/** Listens for Mandarin and checks whether the learner said the target word. */
class SpeechListener(private val context: Context) {
    enum class State { Idle, Listening, Matched, Missed, Unavailable }

    var state by mutableStateOf(State.Idle)
        private set
    var heard by mutableStateOf("")
        private set

    private var recognizer: SpeechRecognizer? = null
    private val han: Transliterator? = runCatching { Transliterator.getInstance("Han-Latin") }.getOrNull()

    fun start(word: uniffi.meitian_core.CoreWord) {
        stop()
        heard = ""
        if (!SpeechRecognizer.isRecognitionAvailable(context)) { state = State.Unavailable; return }
        val r = SpeechRecognizer.createSpeechRecognizer(context)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) = handle(results, word, final = true)
            override fun onPartialResults(partial: Bundle?) = handle(partial, word, final = false)
            override fun onError(error: Int) { if (state == State.Listening) finish(State.Missed) }
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
        }
        Sfx.play(Sfx.Sound.MicOn)
        state = State.Listening
        r.startListening(intent)
    }

    private fun handle(b: Bundle?, word: uniffi.meitian_core.CoreWord, final: Boolean) {
        if (state != State.Listening) return
        val list = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: arrayListOf()
        list.firstOrNull()?.let { heard = it }
        // any of the alternatives counts; matching rules live in the Rust core
        if (list.any { matches(it, word) }) { finish(State.Matched); return }
        if (final) finish(State.Missed)
    }

    fun matches(text: String, word: uniffi.meitian_core.CoreWord): Boolean {
        val hanzi = text.filter { it.code in 0x4E00..0x9FFF || it.code in 0x3400..0x4DBF }
        val latin = han?.transliterate(hanzi) ?: ""
        return speechMatches(hanzi, latin, word.hanzi, word.pinyin)
    }

    private fun finish(s: State) {
        stop()
        state = s
        Sfx.play(if (s == State.Matched) Sfx.Sound.Correct else Sfx.Sound.MicOff)
    }

    fun stop() {
        recognizer?.run { runCatching { cancel(); destroy() } }
        recognizer = null
        if (state == State.Listening) state = State.Idle
    }

    fun reset() { stop(); state = State.Idle; heard = "" }
}
