import AVFoundation
import Speech
import Observation

// MARK: - Sound effects

/// Sound effects, synthesized by the Rust core (the same on Android).
final class SFX {
    static let shared = SFX()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [SoundId: AVAudioPCMBuffer] = [:]
    private var hits: [String: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(soundSampleRate()), channels: 1)!

    private init() {
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: Prefs.sounds) as? Bool ?? true }

    func play(_ sound: SoundId) {
        guard enabled else { return }
        if buffers[sound] == nil { buffers[sound] = buffer(soundPcm(id: sound)) }
        play(buffers[sound])
    }

    /// The impact of a hit effect cosmetic.
    func playHit(_ effectId: String) {
        guard enabled else { return }
        let key = hitInfo(id: effectId).sound
        if hits[key] == nil { hits[key] = buffer(hitSoundPcm(key: key)) }
        play(hits[key])
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        // Never touch the audio session while the microphone is recording: switching it to playback
        // silences the mic and speech recognition hears nothing.
        guard !SpeechListener.isRecording, let buffer else { return }
        // ambient: effects respect the silent switch and mix with music (speech keeps its own session)
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient && !Speaker.shared.isSpeaking {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        engine.mainMixerNode.outputVolume = min(Float(Prefs.soundVolume) * 1.25, 1)   // 80 %, the default, is full scale
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: .interrupts)
        p.play()
    }

    /// 16-bit samples from the core, as the engine's floats.
    private func buffer(_ pcm: Data) -> AVAudioPCMBuffer? {
        let count = pcm.count / 2
        guard count > 0, let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let out = b.floatChannelData?[0] else { return nil }
        b.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { raw in
            for i in 0..<count {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                out[i] = Float(sample) / 32768
            }
        }
        return b
    }
}

// MARK: - Speech recognition

/// Listens for Mandarin and checks whether the learner said the target word.
@Observable
final class SpeechListener {
    enum State: Equatable { case idle, listening, matched, missed, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var heard = ""

    /// True while the mic is open; sound effects and text-to-speech stay quiet meanwhile.
    static var isRecording = false

    /// Why the last attempt failed, in plain words (shown under the mic).
    private(set) var problem = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    // a fresh engine per attempt: one reused across audio-session changes can stop delivering audio
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var target: Word?
    @ObservationIgnored private var timeout: DispatchWorkItem?

    func start(for word: Word) {
        stop()
        target = word
        heard = ""
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.state = .denied; return }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self.state = .denied; return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        problem = ""
        guard let recognizer else { problem = "Chinese speech recognition isn't supported on this iPhone."; state = .unavailable; return }
        guard recognizer.isAvailable else {
            problem = "Speech recognition needs internet and Siri & Dictation turned on (Settings → General → Keyboard → Enable Dictation)."
            state = .unavailable
            return
        }
        Speaker.shared.stop() // don't record our own text-to-speech
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { problem = "The microphone is busy (\(error.localizedDescription))."; state = .unavailable; return }
        SpeechListener.isRecording = true
        engine = AVAudioEngine()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Don't force on-device: the Chinese offline model often isn't installed and then every try fails.
        req.taskHint = .search
        req.contextualStrings = target.map { [$0.hanzi] } ?? []
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            SpeechListener.isRecording = false
            problem = "No microphone input. Is another app using the mic?"
            state = .unavailable
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            SpeechListener.isRecording = false
            problem = "Couldn't start the microphone (\(error.localizedDescription))."
            state = .unavailable
            return
        }

        state = .listening
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.state == .listening else { return }
                if let result {
                    self.heard = result.bestTranscription.formattedString
                    if let w = self.target, SpeechListener.matches(self.heard, word: w) {
                        self.finish(.matched)
                        return
                    }
                    if result.isFinal { self.finish(.missed) }
                }
                if let error {
                    // the last partial result may already be right
                    if let w = self.target, !self.heard.isEmpty, SpeechListener.matches(self.heard, word: w) { self.finish(.matched); return }
                    let code = (error as NSError).code
                    // 1101/1107/1110: no speech or nothing recognised — just a miss
                    if ![1101, 1107, 1110, 203, 216].contains(code) {
                        self.problem = (code == 1700 || code == 201)
                            ? "Turn on Siri & Dictation: Settings → General → Keyboard → Enable Dictation."
                            : "Speech recognition error \(code): \(error.localizedDescription)"
                    }
                    self.finish(.missed)
                }
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .listening else { return }
            self.finish(.missed)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: work)
    }

    private func finish(_ result: State) {
        stop()
        state = result
        SFX.shared.play(result == .matched ? .correct : .micOff)
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        SpeechListener.isRecording = false
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        if state == .listening { state = .idle }
    }

    func reset() {
        stop()
        state = .idle
        heard = ""
    }

    /// Accepts the exact characters, or the same syllables (tones ignored), so homophones still count.
    static func matches(_ transcript: String, word: Word) -> Bool {
        let hanzi = String(transcript.filter(Pinyin.isHanzi))
        // the platform transliterates to pinyin; the comparison rules live in the Rust core
        let latin = hanzi.applyingTransform(.mandarinToLatin, reverse: false) ?? ""
        return speechMatches(heardHanzi: hanzi, heardLatin: latin, targetHanzi: word.hanzi, targetPinyin: word.pinyin)
    }
}
