import AVFoundation
import UserNotifications

/// Mandarin text-to-speech.
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let zh = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "zh-CN" }
        return zh.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }()

    var isSpeaking: Bool { synth.isSpeaking }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    func say(_ text: String, slow: Bool = false) {
        guard !SpeechListener.isRecording else { return } // would switch the session away from the mic
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        // WeChat emoji and other emoji aren't read out
        let spoken = speakable(text: text)
        guard !spoken.isEmpty else { return }
        let u = AVSpeechUtterance(string: spoken)
        u.voice = voice
        u.rate = slow ? 0.32 : 0.45
        u.pitchMultiplier = 1.05
        u.volume = 0.85   // the voice and the sound effects sit at the same level
        synth.speak(u)
    }
}

/// Daily local reminder.
enum Reminders {
    static func schedule(hour: Int, minute: Int, name: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        removeDaily()

        let lines = [
            ("你好\(name.isEmpty ? "" : "，\(name)")! 👋", "Your new words are waiting. Five minutes, let's go!"),
            ("今天的任务 🎯", "Today's quests are ready. Grab some coins!"),
            ("加油！🔥", "Keep your streak alive. Your words miss you."),
        ]
        for (i, line) in lines.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = line.0
            content.body = line.1
            content.sound = .default
            var date = DateComponents()
            date.hour = hour
            date.minute = minute
            date.weekday = nil
            // rotate messages across days of the week
            for weekday in stride(from: i + 1, through: 7, by: lines.count) {
                date.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
                let req = UNNotificationRequest(identifier: "daily-\(weekday)", content: content, trigger: trigger)
                try? await center.add(req)
            }
        }
        return true
    }

    private static func removeDaily() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (1...7).map { "daily-\($0)" })
    }

    static func cancel() { removeDaily() }

    // MARK: the next slot machine spin

    /// Asks for permission if needed; returns whether notifications are allowed.
    static func allow() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleSpin(afterMs: Int64) {
        guard afterMs > 1000 else { return }
        let content = UNMutableNotificationContent()
        content.title = "🎰 转一转！"
        content.body = "Your free daily spin is ready."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(afterMs) / 1000, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "spin", content: content, trigger: trigger))
    }

    static func cancelSpin() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["spin"])
    }
}
