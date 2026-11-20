import Foundation
import Observation
import Security
import UIKit

/// Online profile, friends, leaderboards and quick match, talking to the Měitiān server (a Cloudflare Worker).
/// The account is just a nickname: the server hands out a token (`id.secret`) that's kept in the Keychain and
/// doubles as the recovery code for moving to a new phone.
@MainActor
@Observable
final class OnlineService {
    static let shared = OnlineService()
    nonisolated static let defaultURL = "https://meitian.asbestboi.workers.dev"
    nonisolated static let urlKey = "onlineURL"

    private(set) var profile: OnlineProfile?
    private(set) var inbox: OnlineInbox?
    /// Bumped on sign-in / sign-out so views re-read `signedIn`.
    private(set) var generation = 0
    @ObservationIgnored private var lastSync = Date.distantPast

    var baseURL: String { Self.currentBase() }

    nonisolated static func currentBase() -> String {
        let s = (UserDefaults.standard.string(forKey: urlKey) ?? "").trimmingCharacters(in: .whitespaces)
        let url = s.isEmpty ? defaultURL : s
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    var token: String? { _ = generation; return Keychain.get("onlineToken") }
    var signedIn: Bool { token != nil }

    func avatarURL(_ p: OnlineProfile?) -> URL? {
        guard let path = p?.avatar, !path.isEmpty else { return nil }
        return URL(string: baseURL + path)
    }

    /// The server's own words for what went wrong.
    static func describe(_ error: Error) -> String {
        if case OnlineError.Server(_, let reason) = error { return reason }
        return "unexpected answer from the server"
    }

    // MARK: requests

    private enum Body { case none, json([String: Any]), jpeg(Data) }

    private func request(_ method: String, _ path: String, _ body: Body = .none, auth: Bool = true) async throws -> String {
        guard let url = URL(string: baseURL + path) else { throw OnlineError.Server(status: 0, reason: "bad server address") }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = method
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        switch body {
        case .none: break
        case .json(let o):
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: o)
        case .jpeg(let d):
            req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            req.httpBody = d
        }
        let status: Int
        let text: String
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            text = String(decoding: data, as: UTF8.self)
        } catch {
            throw OnlineError.Server(status: 0, reason: "no connection to the server")
        }
        try onlineCheck(status: UInt16(clamping: status), body: text)
        return text
    }

    // MARK: account

    func register(nickname: String) async throws {
        let acc = try onlineParseAccount(json: try await request("POST", "/v1/register", .json(["nickname": nickname]), auth: false))
        Keychain.set("onlineToken", acc.token)
        generation += 1
        profile = acc.profile
    }

    /// Sign in on this phone with a recovery code from another one.
    func recover(code: String) async throws {
        let old = token
        Keychain.set("onlineToken", code.trimmingCharacters(in: .whitespacesAndNewlines))
        generation += 1
        do {
            try await refreshMe()
        } catch {
            if let old { Keychain.set("onlineToken", old) } else { Keychain.delete("onlineToken") }
            generation += 1
            throw error
        }
    }

    func refreshMe() async throws {
        guard signedIn else { return }
        profile = try onlineParseProfile(json: try await request("GET", "/v1/me"))
    }

    func rename(_ nickname: String) async throws {
        profile = try onlineParseProfile(json: try await request("PUT", "/v1/me", .json(["nickname": nickname])))
    }

    /// Sends level, streak, XP and equipped cosmetics (at most once a minute unless forced).
    func sync(store: AppStore, arena: ArenaStore, force: Bool = false) async {
        guard signedIn, force || Date.now.timeIntervalSince(lastSync) > 60 else { return }
        lastSync = .now
        let card = arena.card(name: store.profile.name, level: store.currentLevel, wordsLearned: store.cards.count)
        let body: [String: Any] = [
            "level": store.currentLevel,
            "streak": store.streak,
            "xpTotal": store.xp,
            "cosmetics": ["avatar": card.avatar, "aura": card.aura ?? "au.none", "fx": card.effect, "title": card.title],
        ]
        if let text = try? await request("PUT", "/v1/me", .json(body)), let p = try? onlineParseProfile(json: text) {
            profile = p
        }
    }

    func deleteAccount() async throws {
        _ = try await request("DELETE", "/v1/me")
        signOut()
    }

    func signOut() {
        Keychain.delete("onlineToken")
        generation += 1
        profile = nil
        inbox = nil
    }

    // MARK: profile picture

    /// Square-crops and shrinks the picked photo to 256 px, then uploads it (replacing the old one).
    func uploadAvatar(_ image: UIImage) async throws {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).jpegData(withCompressionQuality: 0.85) { _ in
            let scale = 256 / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        _ = try await request("PUT", "/v1/me/avatar", .jpeg(jpeg))
        try await refreshMe()
    }

    func removeAvatar() async throws {
        _ = try await request("DELETE", "/v1/me/avatar")
        try await refreshMe()
    }

    // MARK: people

    func report(_ id: String) async throws { _ = try await request("POST", "/v1/report/\(id)") }
    func friends() async throws -> OnlineFriends { try onlineParseFriends(json: try await request("GET", "/v1/friends")) }

    /// Returns true when you're friends right away (they had already asked you).
    func addFriend(code: String) async throws -> Bool {
        let text = try await request("POST", "/v1/friends", .json(["code": code]))
        let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        return o?["status"] as? String == "friends"
    }

    func accept(_ id: String) async throws { _ = try await request("POST", "/v1/friends/\(id)/accept") }
    func unfriend(_ id: String) async throws { _ = try await request("DELETE", "/v1/friends/\(id)") }

    func challenge(_ friendId: String, mode: DuelMode) async throws -> String {
        let text = try await request("POST", "/v1/challenge", .json(["friendId": friendId, "mode": mode.wireName]))
        let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        guard let room = o?["room"] as? String else { throw OnlineError.Garbled }
        return room
    }

    func decline(_ room: String) async throws { _ = try await request("POST", "/v1/challenge/\(room)/decline") }

    func refreshInbox() async {
        guard signedIn, let text = try? await request("GET", "/v1/inbox") else { return }
        inbox = try? onlineParseInbox(json: text)
    }

    func leaderboard(rating: Bool, friends: Bool) async throws -> Leaderboard {
        let path = "/v1/leaderboard?board=\(rating ? "rating" : "week")&scope=\(friends ? "friends" : "global")"
        return try onlineParseLeaderboard(json: try await request("GET", path))
    }

    // MARK: live sockets

    /// A WebSocket to the server (not resumed yet).
    nonisolated static func socket(path: String) -> URLSessionWebSocketTask {
        let ws = currentBase().replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        var req = URLRequest(url: URL(string: ws + path)!)
        if let token = Keychain.get("onlineToken") { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return URLSession.shared.webSocketTask(with: req)
    }
}

/// Tiny Keychain wrapper for the online token (survives app updates, stays on this device).
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.asbestboi.meitian",
         kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
