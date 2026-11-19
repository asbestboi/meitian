import SwiftUI
import Observation

// MARK: - Cosmetics

enum CosmeticKind: String, Codable, CaseIterable, Identifiable {
    case avatar, frame, title, effect
    var id: String { rawValue }
    var label: String {
        switch self {
        case .avatar: return "Avatars"
        case .frame: return "Card frames"
        case .title: return "Titles"
        case .effect: return "Hit effects"
        }
    }
}

struct Cosmetic: Identifiable, Hashable {
    let id: String
    let kind: CosmeticKind
    let name: String
    /// Emoji for avatars/effects, Chinese text for titles.
    let symbol: String
    let price: Int
}

enum Catalog {
    static let all: [Cosmetic] = [
        // avatars
        Cosmetic(id: "av.chick", kind: .avatar, name: "Chick", symbol: "🐣", price: 0),
        Cosmetic(id: "av.panda", kind: .avatar, name: "Panda", symbol: "🐼", price: 60),
        Cosmetic(id: "av.cat", kind: .avatar, name: "Lucky Cat", symbol: "🐱", price: 60),
        Cosmetic(id: "av.frog", kind: .avatar, name: "Frog", symbol: "🐸", price: 80),
        Cosmetic(id: "av.monkey", kind: .avatar, name: "Monkey King", symbol: "🐵", price: 100),
        Cosmetic(id: "av.tiger", kind: .avatar, name: "Tiger", symbol: "🐯", price: 120),
        Cosmetic(id: "av.fox", kind: .avatar, name: "Fox", symbol: "🦊", price: 120),
        Cosmetic(id: "av.dumpling", kind: .avatar, name: "Dumpling", symbol: "🥟", price: 150),
        Cosmetic(id: "av.boba", kind: .avatar, name: "Bubble Tea", symbol: "🧋", price: 150),
        Cosmetic(id: "av.lantern", kind: .avatar, name: "Lantern", symbol: "🏮", price: 200),
        Cosmetic(id: "av.unicorn", kind: .avatar, name: "Qilin", symbol: "🦄", price: 250),
        Cosmetic(id: "av.dragon", kind: .avatar, name: "Dragon", symbol: "🐲", price: 300),
        // frames
        Cosmetic(id: "fr.lantern", kind: .frame, name: "Lantern", symbol: "", price: 0),
        Cosmetic(id: "fr.jade", kind: .frame, name: "Jade", symbol: "", price: 80),
        Cosmetic(id: "fr.ocean", kind: .frame, name: "Ocean", symbol: "", price: 80),
        Cosmetic(id: "fr.royal", kind: .frame, name: "Royal", symbol: "", price: 120),
        Cosmetic(id: "fr.ink", kind: .frame, name: "Ink", symbol: "", price: 150),
        Cosmetic(id: "fr.sakura", kind: .frame, name: "Sakura", symbol: "", price: 150),
        Cosmetic(id: "fr.gold", kind: .frame, name: "Imperial Gold", symbol: "", price: 200),
        Cosmetic(id: "fr.galaxy", kind: .frame, name: "Galaxy", symbol: "", price: 400),
        // titles
        Cosmetic(id: "ti.newbie", kind: .title, name: "Newbie", symbol: "新手", price: 0),
        Cosmetic(id: "ti.student", kind: .title, name: "Student", symbol: "学生", price: 50),
        Cosmetic(id: "ti.panda", kind: .title, name: "Panda Pal", symbol: "熊猫朋友", price: 100),
        Cosmetic(id: "ti.tea", kind: .title, name: "Tea Master", symbol: "茶师", price: 120),
        Cosmetic(id: "ti.dumpling", kind: .title, name: "Dumpling King", symbol: "饺子王", price: 150),
        Cosmetic(id: "ti.kungfu", kind: .title, name: "Kung Fu", symbol: "功夫", price: 200),
        Cosmetic(id: "ti.dragon", kind: .title, name: "Little Dragon", symbol: "小龙", price: 300),
        Cosmetic(id: "ti.master", kind: .title, name: "Grandmaster", symbol: "大师", price: 600),
        // hit effects
        Cosmetic(id: "fx.boom", kind: .effect, name: "Boom", symbol: "💥", price: 0),
        Cosmetic(id: "fx.fire", kind: .effect, name: "Fire", symbol: "🔥", price: 100),
        Cosmetic(id: "fx.zap", kind: .effect, name: "Lightning", symbol: "⚡️", price: 100),
        Cosmetic(id: "fx.envelope", kind: .effect, name: "Red Envelope", symbol: "🧧", price: 150),
        Cosmetic(id: "fx.blossom", kind: .effect, name: "Blossom", symbol: "🌸", price: 150),
        Cosmetic(id: "fx.dragon", kind: .effect, name: "Dragon Strike", symbol: "🐉", price: 400),
    ]

    static let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func items(_ kind: CosmeticKind) -> [Cosmetic] { all.filter { $0.kind == kind } }
    static func item(_ id: String) -> Cosmetic? { byId[id] }

    static func frameGradient(_ id: String) -> LinearGradient {
        func g(_ a: Color, _ b: Color) -> LinearGradient {
            LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        switch id {
        case "fr.jade": return Theme.jadeGradient
        case "fr.ocean": return Theme.skyGradient
        case "fr.royal": return g(Color(red: 0.75, green: 0.47, blue: 1.0), Color(red: 0.40, green: 0.22, blue: 0.80))
        case "fr.ink": return g(Color(red: 0.32, green: 0.32, blue: 0.36), Color(red: 0.08, green: 0.08, blue: 0.10))
        case "fr.sakura": return g(Color(red: 1.0, green: 0.72, blue: 0.84), Color(red: 0.93, green: 0.40, blue: 0.62))
        case "fr.gold": return g(Color(red: 1.0, green: 0.86, blue: 0.45), Color(red: 0.85, green: 0.55, blue: 0.10))
        case "fr.galaxy": return LinearGradient(colors: [Color(red: 0.15, green: 0.10, blue: 0.40), Color(red: 0.55, green: 0.20, blue: 0.75),
                                                         Color(red: 0.95, green: 0.40, blue: 0.60)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return Theme.warmGradient
        }
    }
}

// MARK: - Player card (what the opponent sees)

struct PlayerCard: Codable, Hashable {
    var id: String
    var name: String
    var level: Int
    var wordsLearned: Int
    var wins: Int
    var losses: Int
    var avatar: String
    var frame: String
    var title: String
    var effect: String

    var avatarSymbol: String { Catalog.item(avatar)?.symbol ?? "🐣" }
    var titleItem: Cosmetic? { Catalog.item(title) }
    var effectSymbol: String { Catalog.item(effect)?.symbol ?? "💥" }
}

struct Rival: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var avatar: String
    var wins = 0
    var losses = 0
    var draws = 0
    var lastPlayed = Date.now
}

enum DuelMode: String, Codable, CaseIterable, Identifiable {
    case duel, blitz
    var id: String { rawValue }
    var title: String { self == .duel ? "Duel" : "Blitz" }
    var emoji: String { self == .duel ? "⚔️" : "⚡️" }
    var blurb: String {
        self == .duel ? "Same question for both. First right answer hits. Knock their HP to 0!"
                      : "45 seconds. Answer as many as you can. Most correct wins."
    }
}

enum MatchOutcome { case win, loss, draw }

// MARK: - Store

private struct ArenaSave: Codable {
    var playerId: String
    var coins: Int
    var owned: Set<String>
    var avatar: String
    var frame: String
    var title: String
    var effect: String
    var wins: Int
    var losses: Int
    var draws: Int
    var streak: Int
    var bestStreak: Int
    var fastestMs: Int?
    var totalDamage: Int
    var rivals: [String: Rival]
}

@Observable
final class ArenaStore {
    var playerId = UUID().uuidString
    var coins = 0
    var owned: Set<String> = ["av.chick", "fr.lantern", "ti.newbie", "fx.boom"]
    var avatar = "av.chick"
    var frame = "fr.lantern"
    var title = "ti.newbie"
    var effect = "fx.boom"
    var wins = 0
    var losses = 0
    var draws = 0
    var streak = 0
    var bestStreak = 0
    var fastestMs: Int?
    var totalDamage = 0
    var rivals: [String: Rival] = [:]

    private let url: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("arena.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(ArenaSave.self, from: data) {
            playerId = s.playerId; coins = s.coins; owned = s.owned
            avatar = s.avatar; frame = s.frame; title = s.title; effect = s.effect
            wins = s.wins; losses = s.losses; draws = s.draws; streak = s.streak; bestStreak = s.bestStreak
            fastestMs = s.fastestMs; totalDamage = s.totalDamage; rivals = s.rivals
        } else {
            save()
        }
    }

    func save() {
        let s = ArenaSave(playerId: playerId, coins: coins, owned: owned, avatar: avatar, frame: frame, title: title,
                          effect: effect, wins: wins, losses: losses, draws: draws, streak: streak, bestStreak: bestStreak,
                          fastestMs: fastestMs, totalDamage: totalDamage, rivals: rivals)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
    }

    func reset() {
        let id = playerId
        coins = 0; owned = ["av.chick", "fr.lantern", "ti.newbie", "fx.boom"]
        avatar = "av.chick"; frame = "fr.lantern"; title = "ti.newbie"; effect = "fx.boom"
        wins = 0; losses = 0; draws = 0; streak = 0; bestStreak = 0; fastestMs = nil; totalDamage = 0; rivals = [:]
        playerId = id
        save()
    }

    func card(name: String, level: Int, wordsLearned: Int) -> PlayerCard {
        PlayerCard(id: playerId, name: name.isEmpty ? "Player" : name, level: level, wordsLearned: wordsLearned,
                   wins: wins, losses: losses, avatar: avatar, frame: frame, title: title, effect: effect)
    }

    // MARK: shop

    func equipped(_ kind: CosmeticKind) -> String {
        switch kind {
        case .avatar: return avatar
        case .frame: return frame
        case .title: return title
        case .effect: return effect
        }
    }

    func equip(_ item: Cosmetic) {
        guard owned.contains(item.id) else { return }
        switch item.kind {
        case .avatar: avatar = item.id
        case .frame: frame = item.id
        case .title: title = item.id
        case .effect: effect = item.id
        }
        save()
    }

    @discardableResult
    func buy(_ item: Cosmetic) -> Bool {
        guard !owned.contains(item.id), coins >= item.price else { return false }
        coins -= item.price
        owned.insert(item.id)
        equip(item)
        return true
    }

    // MARK: results

    /// Records a networked match. Returns coins earned.
    @discardableResult
    func record(_ outcome: MatchOutcome, mode: DuelMode, against rival: PlayerCard, bonus: Int, damage: Int, fastest: Int?) -> Int {
        var r = rivals[rival.id] ?? Rival(id: rival.id, name: rival.name, avatar: rival.avatar)
        r.name = rival.name
        r.avatar = rival.avatar
        r.lastPlayed = .now
        let earned: Int
        switch outcome {
        case .win:
            wins += 1; r.wins += 1; streak += 1
            bestStreak = max(bestStreak, streak)
            earned = 40 + bonus + min(streak - 1, 5) * 5
        case .loss:
            losses += 1; r.losses += 1; streak = 0
            earned = 10
        case .draw:
            draws += 1; r.draws += 1
            earned = 20
        }
        rivals[rival.id] = r
        coins += earned
        totalDamage += damage
        if let fastest { fastestMs = min(fastestMs ?? .max, fastest) }
        save()
        return earned
    }

    var sortedRivals: [Rival] { rivals.values.sorted { $0.lastPlayed > $1.lastPlayed } }
}
