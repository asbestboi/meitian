package com.asbestboi.meitian.data

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import org.json.JSONObject

enum class CosmeticKind(val label: String) {
    Frame("Frames"), Title("Titles"), Effect("Hits"), Aura("Auras"), Sticker("Stickers")
}

data class Cosmetic(val id: String, val kind: CosmeticKind, val name: String, val symbol: String, val price: Int, val swear: Boolean = false)

/** Same ids as the iOS app. */
object Catalog {
    private fun f(id: String, name: String, p: Int) = Cosmetic(id, CosmeticKind.Frame, name, "", p)
    private fun t(id: String, name: String, s: String, p: Int, sw: Boolean = false) = Cosmetic(id, CosmeticKind.Title, name, s, p, sw)
    private fun e(id: String, name: String, s: String, p: Int, sw: Boolean = false) = Cosmetic(id, CosmeticKind.Effect, name, s, p, sw)
    private fun au(id: String, name: String, s: String, p: Int) = Cosmetic(id, CosmeticKind.Aura, name, s, p)
    private fun st(id: String, name: String, s: String, p: Int, sw: Boolean = false) = Cosmetic(id, CosmeticKind.Sticker, name, s, p, sw)

    val all = listOf(
        f("fr.lantern", "Lantern", 0), f("fr.jade", "Jade", 80), f("fr.ocean", "Ocean", 80), f("fr.royal", "Royal", 120),
        f("fr.ink", "Ink", 150), f("fr.sakura", "Sakura", 150), f("fr.gold", "Imperial Gold", 200), f("fr.galaxy", "Galaxy", 400),
        f("fr.concrete", "Concrete", 90), f("fr.acid", "Acid", 160), f("fr.graffiti", "Graffiti", 220), f("fr.neon", "Neon Night", 260),
        f("fr.camo", "Camo", 180), f("fr.hazard", "Hazard", 240),
        t("ti.newbie", "Newbie", "新手", 0), t("ti.student", "Student", "学生", 50), t("ti.panda", "Panda Pal", "熊猫朋友", 100),
        t("ti.tea", "Tea Master", "茶师", 120), t("ti.dumpling", "Dumpling King", "饺子王", 150), t("ti.kungfu", "Kung Fu", "功夫", 200),
        t("ti.dragon", "Little Dragon", "小龙", 300), t("ti.master", "Grandmaster", "大师", 600), t("ti.street", "Street Kid", "街头小子", 90),
        t("ti.boss", "Big Boss", "老大", 250), t("ti.flat", "Lying Flat", "躺平", 80), t("ti.owl", "Night Owl", "夜猫子", 110),
        t("ti.drone", "Office Drone", "社畜", 70), t("ti.legend", "Legend", "传奇", 500),
        t("ti.hooligan", "Hooligan", "流氓", 160, true), t("ti.swearking", "Swear King", "脏话王", 350, true),
        e("fx.boom", "Boom", "💥", 0), e("fx.fire", "Fire", "🔥", 100), e("fx.zap", "Lightning", "⚡️", 100),
        e("fx.envelope", "Red Envelope", "🧧", 150), e("fx.blossom", "Blossom", "🌸", 150), e("fx.dragon", "Dragon Strike", "🐉", 400),
        e("fx.bomb", "Bomb", "💣", 120), e("fx.glove", "Knockout", "🥊", 140), e("fx.firecracker", "Firecracker", "🧨", 160),
        e("fx.tomato", "Tomato", "🍅", 90), e("fx.mic", "Mic Drop", "🎤", 200), e("fx.poop", "Poop", "💩", 130, true),
        e("fx.glitch", "Glitch", "👾", 220), e("fx.chrome", "Chrome Ripple", "💿", 280), e("fx.money", "Money Rain", "💸", 320),
        e("fx.snow", "Blizzard", "❄️", 180), e("fx.hearts", "Heartbreaker", "💘", 160),
        au("au.none", "No aura", "", 0), au("au.sparkle", "Sparkle", "✦", 120), au("au.flame", "On Fire", "🔥", 260),
        au("au.hearts", "Lovestruck", "💗", 150), au("au.snow", "Frosty", "❄️", 150), au("au.notes", "Vibing", "🎶", 180),
        au("au.glitch", "Corrupted", "▓", 240), au("au.money", "Rich", "💸", 400), au("au.chrome", "Chrome", "💿", 500),
        st("st.none", "No sticker", "", 0), st("st.fire", "On Fire", "🔥", 60), st("st.crown", "Crown", "👑", 200),
        st("st.lantern", "Lantern", "🏮", 80), st("st.skate", "Skate", "🛹", 100), st("st.cap", "Snapback", "🧢", 100),
        st("st.tape", "Mixtape", "📼", 120), st("st.spray", "Spray Can", "🎨", 120), st("st.devil", "Devil", "😈", 150),
        st("st.dice", "Lucky Dice", "🎲", 90), st("st.finger", "Rude Hand", "🖕", 180, true),
    )

    private val byId = all.associateBy { it.id }
    operator fun get(id: String): Cosmetic? = byId[id]
    fun items(kind: CosmeticKind, swears: Boolean) = all.filter { it.kind == kind && (swears || !it.swear) }

    fun frame(id: String): Brush {
        fun g(vararg c: Long) = Brush.linearGradient(c.map { Color(it) })
        return when (id) {
            "fr.jade" -> g(0xFF29C266, 0xFF0D8545)
            "fr.ocean" -> g(0xFF4285FF, 0xFF2B3BDB)
            "fr.royal" -> g(0xFFBF78FF, 0xFF6638CC)
            "fr.ink" -> g(0xFF525259, 0xFF14141A)
            "fr.sakura" -> g(0xFFFFB8D6, 0xFFED669E)
            "fr.gold" -> g(0xFFFFDB73, 0xFFD98C1A)
            "fr.galaxy" -> g(0xFF261A66, 0xFF8C33BF, 0xFFF26699)
            "fr.concrete" -> g(0xFF9E9C94, 0xFF5C5C59)
            "fr.acid" -> g(0xFFB8F21A, 0xFF33B333)
            "fr.graffiti" -> g(0xFFFF338C, 0xFFFF9900, 0xFF33B3FF)
            "fr.neon" -> g(0xFF0DE6F2, 0xFFBF1AF2)
            "fr.camo" -> g(0xFF546638, 0xFF807347, 0xFF384229)
            "fr.hazard" -> g(0xFFFFD100, 0xFFF28000)
            else -> g(0xFFFF5C33, 0xFFE01C29)
        }
    }
}

/** What the other players see. Same JSON shape as the iOS PlayerCard (cards from apps up to 1.12 also carry an
 *  `avatar`, which is ignored: profile pictures replaced them). */
data class PlayerCard(
    val id: String,
    val name: String,
    val level: Int,
    val wordsLearned: Int,
    val wins: Int,
    val losses: Int,
    val frame: String,
    val title: String,
    val effect: String,
    val sticker: String? = null,
    val swears: Boolean? = null,
    val aura: String? = null,
) {
    val swearsOn get() = swears ?: false
    val effectSymbol get() = Catalog[effect]?.symbol ?: "💥"
    val titleItem get() = Catalog[title]
    val stickerSymbol get() = sticker?.let { Catalog[it]?.symbol }?.takeIf { it.isNotEmpty() }

    fun json() = JSONObject().apply {
        put("id", id); put("name", name); put("level", level); put("wordsLearned", wordsLearned); put("wins", wins)
        put("losses", losses); put("frame", frame); put("title", title); put("effect", effect)
        put("sticker", sticker ?: "st.none"); put("swears", swearsOn); put("aura", aura ?: "au.none")
    }

    companion object {
        fun from(o: JSONObject) = PlayerCard(
            o.getString("id"), o.optString("name", "Player"), o.optInt("level", 1), o.optInt("wordsLearned"),
            o.optInt("wins"), o.optInt("losses"), o.optString("frame", "fr.lantern"),
            o.optString("title", "ti.newbie"), o.optString("effect", "fx.boom"), o.optString("sticker", "st.none"),
            o.optBoolean("swears", false), o.optString("aura", "au.none"),
        )
    }
}
