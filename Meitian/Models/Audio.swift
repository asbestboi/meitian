import AVFoundation
import Speech
import Observation

// MARK: - Sound effects

/// Little synthesized sound effects (no audio files). Lo-fi on purpose, to fit the street look.
final class SFX {
    enum Sound: CaseIterable { case correct, wrong, hit, coin, win, lose, tick, go, swoosh, micOn, micOff }

    static let shared = SFX()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    private init() {
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.55
        for s in Sound.allCases { buffers[s] = render(s) }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: Prefs.sounds) as? Bool ?? true }

    func play(_ sound: Sound) {
        guard enabled, let buffer = buffers[sound] else { return }
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? engine.start()
        }
        guard engine.isRunning else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: .interrupts)
        p.play()
    }

    // MARK: synthesis

    private struct Note { var freq: Double; var dur: Double; var wave: Int = 0; var bend: Double = 0; var vol: Double = 1 }

    private func render(_ s: Sound) -> AVAudioPCMBuffer {
        switch s {
        case .correct: return tones([Note(freq: 880, dur: 0.08, wave: 1), Note(freq: 1320, dur: 0.14, wave: 1)])
        case .wrong: return tones([Note(freq: 200, dur: 0.24, wave: 2, bend: -80, vol: 0.6)])
        case .hit: return mix(noise(0.14, vol: 0.9), tones([Note(freq: 95, dur: 0.18, wave: 0, bend: -40)]))
        case .coin: return tones([Note(freq: 1568, dur: 0.06, wave: 2, vol: 0.5), Note(freq: 2093, dur: 0.16, wave: 2, vol: 0.5)])
        case .win: return tones([523.0, 659.0, 784.0, 1047.0].map { Note(freq: $0, dur: 0.11, wave: 1) } + [Note(freq: 1047, dur: 0.25, wave: 1)])
        case .lose: return tones([392.0, 330.0, 262.0].map { Note(freq: $0, dur: 0.16, wave: 2, vol: 0.55) })
        case .tick: return tones([Note(freq: 660, dur: 0.07, wave: 1, vol: 0.7)])
        case .go: return tones([Note(freq: 990, dur: 0.2, wave: 1)])
        case .swoosh: return noise(0.16, vol: 0.35, sweep: true)
        case .micOn: return tones([Note(freq: 740, dur: 0.06, wave: 0), Note(freq: 1110, dur: 0.08, wave: 0)])
        case .micOff: return tones([Note(freq: 1110, dur: 0.06, wave: 0), Note(freq: 740, dur: 0.08, wave: 0)])
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = AVAudioFrameCount(samples.count)
        let ch = b.floatChannelData![0]
        for (i, v) in samples.enumerated() { ch[i] = v }
        return b
    }

    private func tones(_ notes: [Note]) -> AVAudioPCMBuffer {
        let sr = 44100.0
        var out: [Float] = []
        for n in notes {
            let count = Int(n.dur * sr)
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / sr
                let f = n.freq + n.bend * (t / n.dur)
                phase += f / sr
                let x = phase.truncatingRemainder(dividingBy: 1)
                var v: Double
                switch n.wave {
                case 1: v = 1 - 4 * abs(x - 0.5)                 // triangle
                case 2: v = x < 0.5 ? 0.6 : -0.6                  // square
                default: v = sin(2 * .pi * x)                     // sine
                }
                v = (v * 8).rounded() / 8                          // light bitcrush for grit
                let attack = min(1, t / 0.005)
                let decay = exp(-3.5 * t / n.dur)
                out.append(Float(v * attack * decay * n.vol * 0.5))
            }
        }
        return buffer(out)
    }

    private func noise(_ dur: Double, vol: Double, sweep: Bool = false) -> AVAudioPCMBuffer {
        let sr = 44100.0
        let count = Int(dur * sr)
        var out: [Float] = []
        var last = 0.0
        for i in 0..<count {
            let t = Double(i) / sr
            let raw = Double.random(in: -1...1)
            // one-pole low-pass; a sweep opens the filter for a "whoosh"
            let a = sweep ? 0.05 + 0.6 * (t / dur) : 0.35
            last += a * (raw - last)
            let env = sweep ? sin(.pi * t / dur) : exp(-6 * t / dur)
            out.append(Float(last * env * vol))
        }
        return buffer(out)
    }

    private func mix(_ a: AVAudioPCMBuffer, _ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let n = Int(max(a.frameLength, b.frameLength))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<Int(a.frameLength) { out[i] += a.floatChannelData![0][i] }
        for i in 0..<Int(b.frameLength) { out[i] += b.floatChannelData![0][i] }
        return buffer(out.map { max(-1, min(1, $0)) })
    }
}

// MARK: - Speech recognition

/// Listens for Mandarin and checks whether the learner said the target word.
@Observable
final class SpeechListener {
    enum State: Equatable { case idle, listening, matched, missed, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var heard = ""

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    @ObservationIgnored private let engine = AVAudioEngine()
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
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { state = .unavailable; return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.contextualStrings = target.map { [$0.hanzi] } ?? []
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { state = .unavailable; return }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { state = .unavailable; return }

        SFX.shared.play(.micOn)
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
                if error != nil { self.finish(.missed) }
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .listening else { return }
            self.finish(.missed)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
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
