//! Battle modes, questions, damage and coins. The referee that plays them is in `battle.rs`.

use serde::{Deserialize, Serialize};

use crate::content::sentences;
use crate::pinyin::{is_hanzi_char, pinyin_tone, toneless};
use crate::words::*;

pub const MAX_HP: u32 = 100;
pub const MAX_PLAYERS: u32 = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum BattleMode {
    Duel,
    Blitz,
    Listen,
    Sudden,
    Survival,
    ToneClash,
    SentenceBuilder,
    PinyinType,
    BattleRoyale,
    Team2v2,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ModeInfo {
    pub mode: BattleMode,
    /// Name on the wire and on the server.
    pub wire: String,
    pub title: String,
    pub emoji: String,
    pub blurb: String,
    /// Gradient, "#RRGGBB" twice.
    pub colors: Vec<String>,
    pub min_players: u32,
    pub max_players: u32,
}

/// How a mode is played.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Rules {
    /// Same question for everyone; the first right answer hits everyone else.
    Hp,
    /// Same question for everyone; the first right answer scores a point.
    Points,
    /// Same question for everyone; a wrong answer (or none) and you're out.
    LastStanding,
    /// Everyone answers their own questions against the clock.
    Race,
}

const ALL_MODES: [BattleMode; 10] = [
    BattleMode::Duel,
    BattleMode::Blitz,
    BattleMode::Listen,
    BattleMode::ToneClash,
    BattleMode::SentenceBuilder,
    BattleMode::PinyinType,
    BattleMode::Sudden,
    BattleMode::Survival,
    BattleMode::BattleRoyale,
    BattleMode::Team2v2,
];

impl BattleMode {
    pub(crate) fn rules(self) -> Rules {
        use BattleMode::*;
        match self {
            Duel | Listen | Sudden | ToneClash | Team2v2 => Rules::Hp,
            SentenceBuilder | PinyinType => Rules::Points,
            BattleRoyale => Rules::LastStanding,
            Blitz | Survival => Rules::Race,
        }
    }

    pub(crate) fn is_race(self) -> bool {
        self.rules() == Rules::Race
    }

    /// Milliseconds per round. Battle Royale gets faster and faster, so it always ends.
    pub(crate) fn round_ms(self, index: u32) -> u64 {
        use BattleMode::*;
        match self {
            Sudden | ToneClash => 6_000,
            SentenceBuilder => 25_000,
            PinyinType => 15_000,
            BattleRoyale => 9_000u64.saturating_sub(350 * index as u64).max(2_500),
            _ => 10_000,
        }
    }

    pub(crate) fn race_ms(self) -> u64 {
        if self == BattleMode::Survival {
            120_000
        } else {
            45_000
        }
    }

    pub(crate) fn lives(self) -> u32 {
        if self == BattleMode::Survival {
            3
        } else {
            0
        }
    }

    /// Points modes: the score that wins, and the most rounds before the leader wins.
    pub(crate) fn target(self) -> (u32, u32) {
        (5, 12)
    }

    /// Typing and building: a wrong try costs a second instead of the round.
    pub(crate) fn retries(self) -> bool {
        self.rules() == Rules::Points
    }

    pub(crate) fn damage(self, reaction_ms: u32) -> u32 {
        if self == BattleMode::Sudden {
            34
        } else {
            duel_damage(reaction_ms)
        }
    }

    pub(crate) fn questions(self) -> u32 {
        if self.is_race() {
            80
        } else {
            40
        }
    }
}

#[uniffi::export]
pub fn mode_info(mode: BattleMode) -> ModeInfo {
    use BattleMode::*;
    let (wire, title, emoji, blurb, colors, min, max) = match mode {
        Duel => ("Duel", "Duel", "⚔️", "Same question for everyone. First right answer hits the others. Knock their HP to 0!", ["#FF6B4D", "#FF2E78"], 2, 4),
        Blitz => ("Blitz", "Blitz", "⚡️", "45 seconds. Answer as many as you can. Most correct wins.", ["#5499FF", "#6B52FF"], 2, 4),
        Listen => ("Listen", "Listen duel", "🎧", "No characters on screen: you only hear the word. First to tap it hits.", ["#4DE08C", "#0DA87A"], 2, 4),
        Sudden => ("Sudden", "Sudden death", "☠️", "Three hits and you're out. Only 6 seconds per round.", ["#3A3A44", "#0B0B10"], 2, 4),
        Survival => ("Survival", "Survival", "❤️", "3 lives each. A wrong answer costs a life. Most correct before you run out wins.", ["#FF6BBF", "#B34DFF"], 2, 4),
        ToneClash => ("ToneClash", "Tone clash", "🎵", "Hear a syllable, tap its tone. First right answer hits.", ["#FFCC33", "#FF6A1A"], 2, 4),
        SentenceBuilder => ("SentenceBuilder", "Sentence builder", "🧩", "Race to put the words in order. Fastest scores, first to 5 wins.", ["#2BC0E4", "#2B6FE4"], 2, 4),
        PinyinType => ("PinyinType", "Pinyin type", "⌨️", "See the characters, type the pinyin (no tones needed). Fastest scores, first to 5 wins.", ["#B87AFF", "#5B3DF2"], 2, 4),
        BattleRoyale => ("BattleRoyale", "Battle royale", "👑", "3–4 players. One wrong answer and you're out. Late on, the slowest goes too. Last one standing wins.", ["#FFD23F", "#D9480F"], 3, 4),
        Team2v2 => ("Team2v2", "Team 2v2", "🤝", "Two against two with shared HP. Any right answer hits the other team.", ["#17C3B2", "#227C9D"], 4, 4),
    };
    ModeInfo {
        mode,
        wire: wire.into(),
        title: title.into(),
        emoji: emoji.into(),
        blurb: blurb.into(),
        colors: colors.iter().map(|c| c.to_string()).collect(),
        min_players: min,
        max_players: max,
    }
}

/// Every mode, in menu order.
#[uniffi::export]
pub fn battle_modes() -> Vec<ModeInfo> {
    ALL_MODES.iter().map(|&m| mode_info(m)).collect()
}

/// The modes `players` people can play.
#[uniffi::export]
pub fn modes_for(players: u32) -> Vec<ModeInfo> {
    battle_modes().into_iter().filter(|m| (m.min_players..=m.max_players).contains(&players)).collect()
}

/// Mode from its name on the wire.
#[uniffi::export]
pub fn battle_mode(wire: String) -> Option<BattleMode> {
    battle_modes().into_iter().find(|m| m.wire == wire).map(|m| m.mode)
}

/// Damage for a right answer: faster hits harder (12–22).
#[uniffi::export]
pub fn duel_damage(reaction_ms: u32) -> u32 {
    12 + 4000u32.saturating_sub(reaction_ms) / 400
}

/// Answers this fast are critical hits (a louder sound, not more damage).
pub(crate) const CRIT_MS: u32 = 1_500;

/// Players can only battle with the same swear-word setting.
#[uniffi::export]
pub fn can_match(my_swears: bool, their_swears: bool) -> bool {
    my_swears == their_swears
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Outcome {
    Win,
    Loss,
    Draw,
}

/// Coins for a finished 1v1. `bonus` is HP left / 5 (HP modes) or the score;
/// `streak` is the win streak including this match.
#[uniffi::export]
pub fn match_coins(outcome: Outcome, bonus: u32, streak: u32) -> u32 {
    match outcome {
        Outcome::Win => 40 + bonus + streak.saturating_sub(1).min(5) * 5,
        Outcome::Loss => 10,
        Outcome::Draw => 20,
    }
}

/// Coins for a group game, by finishing place (1 = first) and how many played. Beating more people pays more.
#[uniffi::export]
pub fn group_coins(place: u32, players: u32) -> u32 {
    match (players, place) {
        (0..=1, _) | (_, 0) => 0,
        (2, 1) => 40,
        (3, 1) => 55,
        (_, 1) => 70,
        (3, 2) => 25,
        (4.., 2) => 40,
        (4.., 3) => 20,
        _ => 10,
    }
}

// ---------- questions ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum BattleAsk {
    /// Characters → meaning.
    Meaning,
    /// Meaning → characters.
    Hanzi,
    /// Hear it → characters.
    Listen,
    /// Hear a syllable → its tone (option 0 = first tone).
    Tone,
    /// Put the tiles in order.
    Sentence,
    /// Characters → type the pinyin.
    Pinyin,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct BattleOption {
    #[serde(rename = "l")]
    pub label: String,
    /// Pinyin under characters, "" otherwise.
    #[serde(rename = "p", default)]
    pub pinyin: String,
}

/// A question, complete enough to show on a phone that doesn't have the word.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct BattleQuestion {
    pub ask: BattleAsk,
    /// What's shown big: characters, a meaning or an English sentence ("" when you only listen).
    #[serde(rename = "q")]
    pub prompt: String,
    /// Pinyin over the prompt, "" to hide it.
    #[serde(rename = "qp", default)]
    pub prompt_pinyin: String,
    /// Read aloud when the question appears, "" = silent.
    #[serde(default)]
    pub say: String,
    #[serde(rename = "o", default)]
    pub options: Vec<BattleOption>,
    #[serde(rename = "a", default)]
    pub answer: u32,
    #[serde(rename = "t", default)]
    pub tiles: Vec<String>,
    /// The right answer in words, shown after the round.
    #[serde(rename = "s")]
    pub solution: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum BattleAnswer {
    Option { index: u32 },
    Text { text: String },
    Tiles { tiles: Vec<String> },
}

impl BattleQuestion {
    pub(crate) fn is_right(&self, a: &BattleAnswer) -> bool {
        match (self.ask, a) {
            (BattleAsk::Sentence, BattleAnswer::Tiles { tiles }) => tiles.concat() == self.solution,
            (BattleAsk::Pinyin, BattleAnswer::Text { text }) => pinyin_typed_ok(text.clone(), self.solution.clone()),
            (BattleAsk::Sentence | BattleAsk::Pinyin, _) => false,
            (_, BattleAnswer::Option { index }) => *index == self.answer,
            _ => false,
        }
    }
}

/// Typed pinyin: tones, tone numbers, spaces, apostrophes and capitals don't matter; v stands for ü.
#[uniffi::export]
pub fn pinyin_typed_ok(typed: String, pinyin: String) -> bool {
    let typed = toneless(typed.replace("u:", "ü").replace(['v', 'V'], "u"));
    !typed.is_empty() && typed == toneless(pinyin)
}

/// A toneless syllable ("hao") with the tone mark where it belongs.
pub(crate) fn with_tone(syllable: &str, tone: u8) -> String {
    let marks = |v: char| match v {
        'a' => ['ā', 'á', 'ǎ', 'à'],
        'e' => ['ē', 'é', 'ě', 'è'],
        'i' => ['ī', 'í', 'ǐ', 'ì'],
        'o' => ['ō', 'ó', 'ǒ', 'ò'],
        'u' => ['ū', 'ú', 'ǔ', 'ù'],
        _ => ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
    };
    let chars: Vec<char> = syllable.chars().collect();
    let pos = chars
        .iter()
        .position(|c| *c == 'a' || *c == 'e')
        .or_else(|| syllable.contains("ou").then(|| chars.iter().position(|c| *c == 'o')).flatten())
        .or_else(|| chars.iter().rposition(|c| "iouü".contains(*c)));
    chars
        .iter()
        .enumerate()
        .map(|(i, &c)| if Some(i) == pos && (1..=4).contains(&tone) { marks(c)[tone as usize - 1] } else { c })
        .collect()
}

/// Removes the tone mark but keeps ü.
fn bare(syllable: &str) -> String {
    syllable
        .chars()
        .map(|c| match c {
            'ā' | 'á' | 'ǎ' | 'à' => 'a',
            'ē' | 'é' | 'ě' | 'è' => 'e',
            'ī' | 'í' | 'ǐ' | 'ì' => 'i',
            'ō' | 'ó' | 'ǒ' | 'ò' => 'o',
            'ū' | 'ú' | 'ǔ' | 'ù' => 'u',
            'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' => 'ü',
            c => c,
        })
        .collect()
}

/// Characters the speech engine may read differently on their own, so they're no good for "hear the tone".
const POLYPHONES: &str = "了得地的着长好过都行重只还少教为分种吗呢吧啊不一会和觉乐看";

fn battle_words(level: u8, swears: bool) -> Vec<CoreWord> {
    // bundled words only: the same on every phone, so nobody gets words their app has never shown
    let mut w: Vec<CoreWord> = bundled_words().into_iter().filter(|w| w.level <= level.max(1)).collect();
    if swears {
        w.extend(swear_words());
    }
    w
}

fn choice(word: &CoreWord, pool: &[String], ask: BattleAsk) -> BattleQuestion {
    let ids = quiz_options(word.id.clone(), pool.to_vec());
    let answer = ids.iter().position(|id| *id == word.id).unwrap_or(0) as u32;
    let options = ids
        .into_iter()
        .filter_map(word_by_id)
        .map(|w| match ask {
            BattleAsk::Meaning => BattleOption { label: w.short_meaning().to_string(), pinyin: String::new() },
            _ => BattleOption { label: w.hanzi, pinyin: w.pinyin },
        })
        .collect();
    let (prompt, prompt_pinyin) = match ask {
        BattleAsk::Meaning => (word.hanzi.clone(), word.pinyin.clone()),
        BattleAsk::Hanzi => (word.short_meaning().to_string(), String::new()),
        _ => (String::new(), String::new()),
    };
    BattleQuestion {
        ask,
        prompt,
        prompt_pinyin,
        say: if ask == BattleAsk::Listen { word.hanzi.clone() } else { String::new() },
        options,
        answer,
        tiles: vec![],
        solution: format!("{} {} · {}", word.hanzi, word.pinyin, word.short_meaning()),
    }
}

fn tone_question(word: &CoreWord) -> BattleQuestion {
    let base = bare(&word.pinyin.to_lowercase());
    BattleQuestion {
        ask: BattleAsk::Tone,
        prompt: base.clone(),
        prompt_pinyin: String::new(),
        say: word.hanzi.clone(),
        options: (1..=4).map(|t| BattleOption { label: with_tone(&base, t), pinyin: String::new() }).collect(),
        answer: pinyin_tone(word.pinyin.clone()) as u32 - 1,
        tiles: vec![],
        solution: format!("{} {}", word.hanzi, word.pinyin),
    }
}

/// Sentences with their tiles: from the downloaded packs, or the bundled words' examples cut into known words.
fn sentence_pool(level: u8, rng: &mut fastrand::Rng, count: usize) -> Vec<(String, Vec<String>)> {
    let mut out: Vec<(String, Vec<String>)> = {
        let store = sentences().read().unwrap_or_else(|e| e.into_inner());
        store
            .all
            .iter()
            .filter(|s| s.level <= level.max(1))
            .map(|s| (s.en.clone(), s.words().map(|t| t.text.clone()).collect::<Vec<_>>()))
            .filter(|(_, t)| (3..=7).contains(&t.len()))
            .collect()
    };
    if out.len() < count {
        let b = bank();
        for w in b.regular[..b.bundled].iter().filter(|w| w.level <= level.max(1)) {
            let chars: Vec<char> = w.example.chars().filter(|c| is_hanzi_char(*c)).collect();
            let mut tiles = Vec::new();
            let mut i = 0;
            while i < chars.len() {
                let len = (1..=4.min(chars.len() - i))
                    .rev()
                    .find(|&l| b.by_hanzi.contains_key(&chars[i..i + l].iter().collect::<String>()))
                    .unwrap_or(1);
                tiles.push(chars[i..i + len].iter().collect());
                i += len;
            }
            if (3..=7).contains(&tiles.len()) {
                out.push((w.example_meaning.clone(), tiles));
            }
        }
    }
    rng.shuffle(&mut out);
    out.truncate(count);
    out
}

/// The questions of a game. The host makes them once and sends them to everyone.
pub(crate) fn make_questions(mode: BattleMode, level: u8, swears: bool, seed: u64) -> Vec<BattleQuestion> {
    let mut rng = fastrand::Rng::with_seed(seed);
    let count = mode.questions() as usize;
    let words = battle_words(level, swears && mode != BattleMode::ToneClash);
    let ids: Vec<String> = words.iter().map(|w| w.id.clone()).collect();
    let pool: Vec<BattleQuestion> = match mode {
        BattleMode::SentenceBuilder => sentence_pool(level, &mut rng, count)
            .into_iter()
            .map(|(en, right)| {
                let mut tiles = right.clone();
                for _ in 0..8 {
                    rng.shuffle(&mut tiles);
                    if tiles != right {
                        break;
                    }
                }
                BattleQuestion {
                    ask: BattleAsk::Sentence,
                    prompt: en,
                    prompt_pinyin: String::new(),
                    say: String::new(),
                    options: vec![],
                    answer: 0,
                    tiles,
                    solution: right.concat(),
                }
            })
            .collect(),
        BattleMode::ToneClash => words
            .iter()
            .filter(|w| w.hanzi.chars().count() == 1 && !POLYPHONES.contains(&w.hanzi) && pinyin_tone(w.pinyin.clone()) <= 4)
            .map(tone_question)
            .collect(),
        BattleMode::PinyinType => words
            .iter()
            .filter(|w| w.hanzi.chars().count() <= 3 && w.hanzi.chars().all(is_hanzi_char))
            .map(|w| BattleQuestion {
                ask: BattleAsk::Pinyin,
                prompt: w.hanzi.clone(),
                prompt_pinyin: String::new(),
                say: String::new(),
                options: vec![],
                answer: 0,
                tiles: vec![],
                solution: w.pinyin.clone(),
            })
            .collect(),
        BattleMode::Listen => words.iter().map(|w| choice(w, &ids, BattleAsk::Listen)).collect(),
        _ => words
            .iter()
            .enumerate()
            .map(|(i, w)| choice(w, &ids, if i % 2 == 0 { BattleAsk::Meaning } else { BattleAsk::Hanzi }))
            .collect(),
    };
    let mut bag: Vec<BattleQuestion> = Vec::new();
    (0..count)
        .map_while(|_| {
            if bag.is_empty() {
                bag = pool.clone();
                rng.shuffle(&mut bag);
            }
            bag.pop()
        })
        .collect()
}

/// Swear Sprint: points for a right answer at the current combo (×1 … ×5).
#[uniffi::export]
pub fn sprint_multiplier(combo: u32) -> u32 {
    (1 + combo / 3).min(5)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn damage_range() {
        assert_eq!(duel_damage(0), 22);
        assert_eq!(duel_damage(4000), 12);
        assert_eq!(duel_damage(9000), 12);
        assert_eq!(BattleMode::Sudden.damage(9000), 34);
    }

    #[test]
    fn coins() {
        assert_eq!(match_coins(Outcome::Win, 10, 1), 50);
        assert_eq!(match_coins(Outcome::Win, 0, 10), 65);
        assert_eq!(match_coins(Outcome::Loss, 99, 0), 10);
        for players in 2..=4 {
            let c: Vec<u32> = (1..=players).map(|p| group_coins(p, players)).collect();
            assert!(c.windows(2).all(|w| w[0] > w[1]), "{players}: {c:?}");
            assert!(*c.last().unwrap() > 0, "everybody gets something");
        }
        assert!(group_coins(1, 4) > group_coins(1, 3) && group_coins(1, 3) > group_coins(1, 2));
        assert_eq!(group_coins(1, 1), 0, "no coins for playing alone");
    }

    #[test]
    fn modes() {
        for m in battle_modes() {
            assert_eq!(battle_mode(m.wire.clone()), Some(m.mode));
            assert!(m.colors.len() == 2 && m.colors.iter().all(|c| c.len() == 7));
            assert!(!m.emoji.is_empty() && m.blurb.len() > 20);
        }
        assert_eq!(battle_mode("Chess".into()), None);
        let for_n = |n| modes_for(n).into_iter().map(|m| m.mode).collect::<Vec<_>>();
        assert!(!for_n(2).contains(&BattleMode::BattleRoyale) && for_n(3).contains(&BattleMode::BattleRoyale));
        assert!(!for_n(3).contains(&BattleMode::Team2v2) && for_n(4).contains(&BattleMode::Team2v2));
        assert_eq!(for_n(4).len(), 10);
        assert!(for_n(1).is_empty());
        let royale: Vec<u64> = (0..30).map(|i| BattleMode::BattleRoyale.round_ms(i)).collect();
        assert!(royale.windows(2).all(|w| w[0] >= w[1]) && royale[29] == 2_500);
    }

    #[test]
    fn questions_for_every_mode() {
        for m in battle_modes() {
            for level in [1, 4] {
                let qs = make_questions(m.mode, level, false, 9);
                assert_eq!(qs.len(), m.mode.questions() as usize, "{:?} {level}", m.mode);
                for q in &qs {
                    match q.ask {
                        BattleAsk::Sentence => {
                            assert!((3..=7).contains(&q.tiles.len()));
                            assert!(!q.is_right(&BattleAnswer::Tiles { tiles: vec!["x".into()] }));
                            let mut sorted: Vec<char> = q.tiles.concat().chars().collect();
                            let mut want: Vec<char> = q.solution.chars().collect();
                            sorted.sort();
                            want.sort();
                            assert_eq!(sorted, want);
                        }
                        BattleAsk::Pinyin => {
                            assert!(q.is_right(&BattleAnswer::Text { text: q.solution.clone() }));
                            assert!(q.is_right(&BattleAnswer::Text { text: toneless(q.solution.clone()) }), "{}", q.solution);
                            assert!(!q.is_right(&BattleAnswer::Text { text: "zzz".into() }));
                        }
                        _ => {
                            assert_eq!(q.options.len(), 4);
                            assert!((q.answer as usize) < 4);
                            assert!(q.is_right(&BattleAnswer::Option { index: q.answer }));
                            assert!(!q.is_right(&BattleAnswer::Option { index: (q.answer + 1) % 4 }));
                        }
                    }
                    let json = serde_json::to_string(q).unwrap();
                    assert_eq!(serde_json::from_str::<BattleQuestion>(&json).unwrap(), *q);
                }
            }
        }
    }

    #[test]
    fn swears_only_when_on() {
        let has = |qs: Vec<BattleQuestion>| {
            let street: Vec<String> = swear_words().into_iter().map(|w| w.hanzi).collect();
            qs.iter().any(|q| street.contains(&q.prompt))
        };
        assert!(!has(make_questions(BattleMode::Blitz, 1, false, 1)));
        assert!((0..10).any(|s| has(make_questions(BattleMode::Blitz, 1, true, s))));
    }

    #[test]
    fn tones_and_typing() {
        assert_eq!(with_tone("hao", 3), "hǎo");
        assert_eq!(with_tone("gou", 3), "gǒu");
        assert_eq!(with_tone("gui", 4), "guì");
        assert_eq!(with_tone("liu", 2), "liú");
        assert_eq!(with_tone("nü", 3), "nǚ");
        assert_eq!(with_tone("xue", 2), "xué");
        assert_eq!(bare("nǚ"), "nü");
        for (typed, pinyin, ok) in [
            ("nihao", "nǐ hǎo", true),
            ("NI3 HAO3", "nǐ hǎo", true),
            ("ni'hao ", "nǐ hǎo", true),
            ("lvse", "lǜsè", true),
            ("luse", "lǜsè", true),
            ("nǐhǎo", "nǐ hǎo", true),
            ("niha", "nǐ hǎo", false),
            ("", "nǐ hǎo", false),
        ] {
            assert_eq!(pinyin_typed_ok(typed.into(), pinyin.into()), ok, "{typed}");
        }
    }

    #[test]
    fn matching() {
        assert!(can_match(true, true) && can_match(false, false));
        assert!(!can_match(true, false));
        assert_eq!(sprint_multiplier(0), 1);
        assert_eq!(sprint_multiplier(7), 3);
        assert_eq!(sprint_multiplier(100), 5);
    }
}
