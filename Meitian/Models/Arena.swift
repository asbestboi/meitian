import SwiftUI
import Observation

// MARK: - Cosmetics

enum CosmeticKind: String, Codable, CaseIterable, Identifiable {
    case avatar, frame, title, effect, aura, sticker
    var id: String { rawValue }
    var label: String {
        switch self {
        case .avatar: return "Avatars"
        case .frame: return "Frames"
        case .title: return "Titles"
        case .effect: return "Hits"
        case .aura: return "Auras"
        case .sticker: return "Stickers"
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
    /// Only shown (and usable) with swear words turned on.
    var swear = false
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
        // street drop
        Cosmetic(id: "av.skull", kind: .avatar, name: "Skull", symbol: "💀", price: 140),
        Cosmetic(id: "av.gorilla", kind: .avatar, name: "Gorilla", symbol: "🦍", price: 160),
        Cosmetic(id: "av.rat", kind: .avatar, name: "Street Rat", symbol: "🐀", price: 90),
        Cosmetic(id: "av.oni", kind: .avatar, name: "Oni Mask", symbol: "👹", price: 220),
        Cosmetic(id: "av.alien", kind: .avatar, name: "Alien", symbol: "👽", price: 180),
        Cosmetic(id: "av.robot", kind: .avatar, name: "Robot", symbol: "🤖", price: 180),
        Cosmetic(id: "av.cool", kind: .avatar, name: "Too Cool", symbol: "😎", price: 110),
        Cosmetic(id: "av.angry", kind: .avatar, name: "Rage", symbol: "🤬", price: 120, swear: true),
        Cosmetic(id: "fr.concrete", kind: .frame, name: "Concrete", symbol: "", price: 90),
        Cosmetic(id: "fr.acid", kind: .frame, name: "Acid", symbol: "", price: 160),
        Cosmetic(id: "fr.graffiti", kind: .frame, name: "Graffiti", symbol: "", price: 220),
        Cosmetic(id: "fr.neon", kind: .frame, name: "Neon Night", symbol: "", price: 260),
        Cosmetic(id: "fr.camo", kind: .frame, name: "Camo", symbol: "", price: 180),
        Cosmetic(id: "fr.hazard", kind: .frame, name: "Hazard", symbol: "", price: 240),
        Cosmetic(id: "ti.street", kind: .title, name: "Street Kid", symbol: "街头小子", price: 90),
        Cosmetic(id: "ti.boss", kind: .title, name: "Big Boss", symbol: "老大", price: 250),
        Cosmetic(id: "ti.flat", kind: .title, name: "Lying Flat", symbol: "躺平", price: 80),
        Cosmetic(id: "ti.owl", kind: .title, name: "Night Owl", symbol: "夜猫子", price: 110),
        Cosmetic(id: "ti.drone", kind: .title, name: "Office Drone", symbol: "社畜", price: 70),
        Cosmetic(id: "ti.legend", kind: .title, name: "Legend", symbol: "传奇", price: 500),
        Cosmetic(id: "ti.hooligan", kind: .title, name: "Hooligan", symbol: "流氓", price: 160, swear: true),
        Cosmetic(id: "ti.swearking", kind: .title, name: "Swear King", symbol: "脏话王", price: 350, swear: true),
        Cosmetic(id: "fx.bomb", kind: .effect, name: "Bomb", symbol: "💣", price: 120),
        Cosmetic(id: "fx.glove", kind: .effect, name: "Knockout", symbol: "🥊", price: 140),
        Cosmetic(id: "fx.firecracker", kind: .effect, name: "Firecracker", symbol: "🧨", price: 160),
        Cosmetic(id: "fx.tomato", kind: .effect, name: "Tomato", symbol: "🍅", price: 90),
        Cosmetic(id: "fx.mic", kind: .effect, name: "Mic Drop", symbol: "🎤", price: 200),
        Cosmetic(id: "fx.poop", kind: .effect, name: "Poop", symbol: "💩", price: 130, swear: true),
        // new hits (real particle effects)
        Cosmetic(id: "fx.glitch", kind: .effect, name: "Glitch", symbol: "👾", price: 220),
        Cosmetic(id: "fx.chrome", kind: .effect, name: "Chrome Ripple", symbol: "💿", price: 280),
        Cosmetic(id: "fx.money", kind: .effect, name: "Money Rain", symbol: "💸", price: 320),
        Cosmetic(id: "fx.snow", kind: .effect, name: "Blizzard", symbol: "❄️", price: 180),
        Cosmetic(id: "fx.hearts", kind: .effect, name: "Heartbreaker", symbol: "💘", price: 160),
        // auras (particles around your avatar)
        Cosmetic(id: "au.none", kind: .aura, name: "No aura", symbol: "", price: 0),
        Cosmetic(id: "au.sparkle", kind: .aura, name: "Sparkle", symbol: "✦", price: 120),
        Cosmetic(id: "au.flame", kind: .aura, name: "On Fire", symbol: "🔥", price: 260),
        Cosmetic(id: "au.hearts", kind: .aura, name: "Lovestruck", symbol: "💗", price: 150),
        Cosmetic(id: "au.snow", kind: .aura, name: "Frosty", symbol: "❄️", price: 150),
        Cosmetic(id: "au.notes", kind: .aura, name: "Vibing", symbol: "🎶", price: 180),
        Cosmetic(id: "au.glitch", kind: .aura, name: "Corrupted", symbol: "▓", price: 240),
        Cosmetic(id: "au.money", kind: .aura, name: "Rich", symbol: "💸", price: 400),
        Cosmetic(id: "au.chrome", kind: .aura, name: "Chrome", symbol: "💿", price: 500),
        // stickers (slapped on your card)
        Cosmetic(id: "st.none", kind: .sticker, name: "No sticker", symbol: "", price: 0),
        Cosmetic(id: "st.fire", kind: .sticker, name: "On Fire", symbol: "🔥", price: 60),
        Cosmetic(id: "st.crown", kind: .sticker, name: "Crown", symbol: "👑", price: 200),
        Cosmetic(id: "st.lantern", kind: .sticker, name: "Lantern", symbol: "🏮", price: 80),
        Cosmetic(id: "st.skate", kind: .sticker, name: "Skate", symbol: "🛹", price: 100),
        Cosmetic(id: "st.cap", kind: .sticker, name: "Snapback", symbol: "🧢", price: 100),
        Cosmetic(id: "st.tape", kind: .sticker, name: "Mixtape", symbol: "📼", price: 120),
        Cosmetic(id: "st.spray", kind: .sticker, name: "Spray Can", symbol: "🎨", price: 120),
        Cosmetic(id: "st.devil", kind: .sticker, name: "Devil", symbol: "😈", price: 150),
        Cosmetic(id: "st.dice", kind: .sticker, name: "Lucky Dice", symbol: "🎲", price: 90),
        Cosmetic(id: "st.finger", kind: .sticker, name: "Rude Hand", symbol: "🖕", price: 180, swear: true),
    ]

    static let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func items(_ kind: CosmeticKind, swears: Bool = false) -> [Cosmetic] {
        all.filter { $0.kind == kind && (swears || !$0.swear) }
    }
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
        case "fr.concrete": return g(Color(red: 0.62, green: 0.61, blue: 0.58), Color(red: 0.36, green: 0.36, blue: 0.35))
        case "fr.acid": return g(Color(red: 0.72, green: 0.95, blue: 0.10), Color(red: 0.20, green: 0.70, blue: 0.20))
        case "fr.graffiti": return LinearGradient(colors: [Color(red: 1.0, green: 0.20, blue: 0.55), Color(red: 1.0, green: 0.60, blue: 0.0),
                                                           Color(red: 0.20, green: 0.70, blue: 1.0)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case "fr.neon": return g(Color(red: 0.05, green: 0.90, blue: 0.95), Color(red: 0.75, green: 0.10, blue: 0.95))
        case "fr.camo": return LinearGradient(colors: [Color(red: 0.33, green: 0.40, blue: 0.22), Color(red: 0.50, green: 0.45, blue: 0.28),
                                                       Color(red: 0.22, green: 0.26, blue: 0.16)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
        case "fr.hazard": return g(Color(red: 1.0, green: 0.82, blue: 0.0), Color(red: 0.95, green: 0.50, blue: 0.0))
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
    /// Added in 1.3 (optional so older phones' cards still decode).
    var sticker: String? = nil
    var swears: Bool? = nil
    /// Added in 1.6.
    var aura: String? = nil

    var swearsOn: Bool { swears ?? false }
    var stickerSymbol: String? {
        guard let s = sticker, let item = Catalog.item(s), !item.symbol.isEmpty else { return nil }
        return item.symbol
    }
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
    var sticker: String?
    var aura: String?
}

@Observable
final class ArenaStore {
    var playerId = UUID().uuidString
    var coins = 0
    var owned: Set<String> = ["av.chick", "fr.lantern", "ti.newbie", "fx.boom", "st.none", "au.none"]
    var avatar = "av.chick"
    var frame = "fr.lantern"
    var title = "ti.newbie"
    var effect = "fx.boom"
    var sticker = "st.none"
    var aura = "au.none"
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
            sticker = s.sticker ?? "st.none"
            aura = s.aura ?? "au.none"
            owned.insert("st.none")
            owned.insert("au.none")
        } else {
            save()
        }
    }

    func save() {
        let s = ArenaSave(playerId: playerId, coins: coins, owned: owned, avatar: avatar, frame: frame, title: title,
                          effect: effect, wins: wins, losses: losses, draws: draws, streak: streak, bestStreak: bestStreak,
                          fastestMs: fastestMs, totalDamage: totalDamage, rivals: rivals, sticker: sticker, aura: aura)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
    }

    func reset() {
        let id = playerId
        coins = 0; owned = ["av.chick", "fr.lantern", "ti.newbie", "fx.boom", "st.none", "au.none"]
        avatar = "av.chick"; frame = "fr.lantern"; title = "ti.newbie"; effect = "fx.boom"; sticker = "st.none"; aura = "au.none"
        wins = 0; losses = 0; draws = 0; streak = 0; bestStreak = 0; fastestMs = nil; totalDamage = 0; rivals = [:]
        playerId = id
        save()
    }

    func card(name: String, level: Int, wordsLearned: Int) -> PlayerCard {
        let swears = Prefs.swearsOn
        // swear-only cosmetics are hidden from (and never shown to) players with swears off
        func clean(_ id: String, _ fallback: String) -> String {
            (Catalog.item(id)?.swear ?? false) && !swears ? fallback : id
        }
        return PlayerCard(id: playerId, name: name.isEmpty ? "Player" : name, level: level, wordsLearned: wordsLearned,
                          wins: wins, losses: losses, avatar: clean(avatar, "av.chick"), frame: frame,
                          title: clean(title, "ti.newbie"), effect: clean(effect, "fx.boom"),
                          sticker: clean(sticker, "st.none"), swears: swears, aura: aura)
    }

    // MARK: shop

    func equipped(_ kind: CosmeticKind) -> String {
        switch kind {
        case .avatar: return avatar
        case .frame: return frame
        case .title: return title
        case .effect: return effect
        case .aura: return aura
        case .sticker: return sticker
        }
    }

    func equip(_ item: Cosmetic) {
        guard owned.contains(item.id) else { return }
        switch item.kind {
        case .avatar: avatar = item.id
        case .frame: frame = item.id
        case .title: title = item.id
        case .effect: effect = item.id
        case .aura: aura = item.id
        case .sticker: sticker = item.id
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
        let core: Outcome
        switch outcome {
        case .win:
            wins += 1; r.wins += 1; streak += 1
            bestStreak = max(bestStreak, streak)
            core = .win
        case .loss:
            losses += 1; r.losses += 1; streak = 0
            core = .loss
        case .draw:
            draws += 1; r.draws += 1
            core = .draw
        }
        // payout rules live in the shared Rust core
        let earned = Int(matchCoins(outcome: core, bonus: UInt32(clamping: bonus), streak: UInt32(clamping: streak)))
        rivals[rival.id] = r
        coins += earned
        totalDamage += damage
        if let fastest { fastestMs = min(fastestMs ?? .max, fastest) }
        save()
        return earned
    }

    var sortedRivals: [Rival] { rivals.values.sorted { $0.lastPlayed > $1.lastPlayed } }
}
