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
import uniffi.meitian_core.SoundId
import uniffi.meitian_core.hitInfo
import uniffi.meitian_core.hitSoundPcm
import uniffi.meitian_core.soundPcm
import uniffi.meitian_core.soundSampleRate
import uniffi.meitian_core.speechMatches
import java.util.Locale

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
        // WeChat emoji and other emoji aren't read out
        val spoken = uniffi.meitian_core.speakable(text)
        if (spoken.isEmpty()) return
        t.setSpeechRate(if (slow) 0.6f else 0.9f)
        // a touch below full, so the voice and the sound effects sit at the same level
        val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 0.85f) }
        t.speak(spoken, TextToSpeech.QUEUE_FLUSH, params, "say")
    }
}

/** Sound effects, synthesized by the Rust core (the same on iOS) and played from static AudioTracks. */
object Sfx {
    var enabled = true
    /** 0–1, from settings. */
    var volume = 0.8f
    private val rate = soundSampleRate().toInt()
    private val cache = HashMap<Any, ByteArray>()

    fun play(sound: SoundId) = play(sound) { soundPcm(sound) }

    /** The impact of a hit effect cosmetic. */
    fun playHit(effectId: String) = hitInfo(effectId).sound.let { key -> play(key) { hitSoundPcm(key) } }

    private fun play(key: Any, render: () -> ByteArray) {
        if (!enabled || volume <= 0f) return
        val level = volume
        Thread {
            runCatching {
                val pcm = synchronized(cache) { cache.getOrPut(key, render) }
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(pcm.size)
                    .build()
                track.write(pcm, 0, pcm.size)
                track.setVolume((level * 1.25f).coerceAtMost(1f))   // 80 %, the default, is full scale
                track.play()
                Thread.sleep((pcm.size / 2 * 1000L / rate) + 60)
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
    /** Why the last attempt failed, in plain words (empty for an ordinary miss). */
    var problem by mutableStateOf("")
        private set

    private var recognizer: SpeechRecognizer? = null
    private val han: Transliterator? = runCatching { Transliterator.getInstance("Han-Latin") }.getOrNull()

    fun start(word: uniffi.meitian_core.CoreWord) {
        stop()
        heard = ""
        problem = ""
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            problem = "No background speech service on this phone. Use Google voice input below."
            state = State.Unavailable; return
        }
        val r = SpeechRecognizer.createSpeechRecognizer(context)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) = handle(results, word, final = true)
            override fun onPartialResults(partial: Bundle?) = handle(partial, word, final = false)
            override fun onError(error: Int) {
                if (state != State.Listening) return
                // a partial result may already contain the word
                if (heard.isNotEmpty() && matches(heard, word)) { finish(State.Matched); return }
                problem = when (error) {
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER ->
                        "Chinese speech recognition needs internet."
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Allow the microphone for Měitiān in Settings."
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                        "This phone's speech service has no Chinese. Use Google voice input below."
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The speech service is busy, try again."
                    SpeechRecognizer.ERROR_CLIENT -> "The speech service stopped. Try again, or use Google voice input below."
                    else -> ""   // no match / speech timeout: an ordinary miss
                }
                finish(if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS || error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                        error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE || error == SpeechRecognizer.ERROR_CLIENT) State.Unavailable else State.Missed)
            }
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
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "zh-CN")
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            // short words: give people a moment before deciding they're done
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 800L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
        }
        Sfx.play(SoundId.MIC_ON)
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
        Sfx.play(if (s == State.Matched) SoundId.CORRECT else SoundId.MIC_OFF)
    }

    fun stop() {
        recognizer?.run { runCatching { cancel(); destroy() } }
        recognizer = null
        if (state == State.Listening) state = State.Idle
    }

    fun reset() { stop(); state = State.Idle; heard = ""; problem = "" }

    /** Result from Google's voice-input popup (the fallback when the background service can't do Chinese). */
    fun dialogResult(results: List<String>, word: uniffi.meitian_core.CoreWord) {
        heard = results.firstOrNull() ?: ""
        problem = ""
        state = if (results.any { matches(it, word) }) State.Matched else State.Missed
        Sfx.play(if (state == State.Matched) SoundId.CORRECT else SoundId.MIC_OFF)
    }
}
