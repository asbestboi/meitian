//! The slot machine: every finished unit of the learning path is a free spin, never paid, and spins stack up. The core
//! decides the prize, seeded from the player and how often they have spun, so restarting the app can't reroll it.

use crate::content::{resolved, sentences, Sentence};
use crate::vocab::{id_set, is_new, is_vocab, mark_new};

/// Spins waiting: one for every finished unit (`finished_units` are "level-unit" keys, each counts once) that wasn't
/// used yet.
#[uniffi::export]
pub fn spins_left(finished_units: Vec<String>, used: u32) -> u32 {
    (id_set(finished_units).len() as u32).saturating_sub(used)
}

/// What the reels can show.
const SYMBOLS: [&str; 7] = ["🪙", "💰", "💎", "🎨", "📝", "🍀", "福"];

#[uniffi::export]
pub fn slot_symbols() -> Vec<String> {
    SYMBOLS.iter().map(|s| s.to_string()).collect()
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum SlotPrize {
    Coins { amount: u32, jackpot: bool },
    /// A cosmetic the player doesn't own yet.
    Cosmetic { id: String },
    /// A bonus sentence: learned words plus at most one new one.
    Sentence { sentence: Sentence },
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SpinResult {
    /// Where the three reels stop.
    pub reels: Vec<String>,
    pub prize: SlotPrize,
}

/// XP for finishing the bonus sentence.
#[uniffi::export]
pub fn spin_sentence_xp() -> u32 {
    20
}

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Coins(u32),
    Jackpot,
    Cosmetic,
    Sentence,
}

/// Weights out of 100.
const ODDS: [(Kind, u32); 6] = [
    (Kind::Coins(20), 27),
    (Kind::Coins(50), 20),
    (Kind::Coins(100), 10),
    (Kind::Jackpot, 2),
    (Kind::Cosmetic, 13),
    (Kind::Sentence, 28),
];

const JACKPOT: u32 = 500;

/// Spins. `cosmetic_ids` are the cosmetics the player could win (not owned, and allowed by their settings): when
/// there are none, or no sentence fits (or the last one is still waiting: `sentence_waiting`), the spin pays coins.
#[uniffi::export]
pub fn spin_slots(player_id: String, spin_count: u32, cosmetic_ids: Vec<String>, known_word_ids: Vec<String>, sentence_waiting: bool) -> SpinResult {
    let player = player_id.bytes().fold(0xcbf2_9ce4_8422_2325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100_0000_01b3));
    let seed = player ^ (spin_count as u64 + 1).wrapping_mul(0x9e37_79b9_7f4a_7c15);
    let mut rng = fastrand::Rng::with_seed(seed);
    let mut roll = rng.u32(..ODDS.iter().map(|o| o.1).sum::<u32>());
    let kind = ODDS
        .iter()
        .find(|(_, w)| {
            let hit = roll < *w;
            roll = roll.saturating_sub(*w);
            hit
        })
        .map_or(Kind::Coins(20), |o| o.0);
    let coins = |amount| SlotPrize::Coins { amount, jackpot: false };
    let prize = match kind {
        Kind::Coins(n) => coins(n),
        Kind::Jackpot => SlotPrize::Coins { amount: JACKPOT, jackpot: true },
        Kind::Cosmetic => {
            let mut ids = cosmetic_ids;
            ids.sort();
            if ids.is_empty() {
                coins(100)
            } else {
                SlotPrize::Cosmetic { id: ids.swap_remove(rng.usize(..ids.len())) }
            }
        }
        Kind::Sentence if sentence_waiting => coins(50),
        Kind::Sentence => bonus_sentence(&mut rng, known_word_ids).map_or(coins(50), |sentence| SlotPrize::Sentence { sentence }),
    };
    let symbol = match &prize {
        SlotPrize::Coins { jackpot: true, .. } => "福",
        SlotPrize::Coins { amount: 100.., .. } => "💎",
        SlotPrize::Coins { amount: 50.., .. } => "💰",
        SlotPrize::Coins { .. } => "🪙",
        SlotPrize::Cosmetic { .. } => "🎨",
        SlotPrize::Sentence { .. } => "📝",
    };
    let mut reels = vec![symbol.to_string(); 3];
    if prize == coins(20) {
        // the small prize: two coins and something else
        let others: Vec<&str> = SYMBOLS.iter().copied().filter(|s| *s != symbol).collect();
        reels[rng.usize(..3)] = others[rng.usize(..others.len())].to_string();
    }
    SpinResult { reels, prize }
}

/// A sentence of 3–8 words, all learned except at most one (which the word bank can explain). One with exactly one
/// new word is preferred.
fn bonus_sentence(rng: &mut fastrand::Rng, known_word_ids: Vec<String>) -> Option<Sentence> {
    let known = id_set(known_word_ids);
    if known.is_empty() {
        return None;
    }
    let pool: Vec<Sentence> = sentences().read().unwrap_or_else(|e| e.into_inner()).all.clone();
    let (mut with_new, mut without) = (vec![], vec![]);
    for s in pool.into_iter().filter(|s| (3..=8).contains(&s.words().count())) {
        let s = resolved(s);
        let mut new: Vec<&str> = s.tokens.iter().filter(|t| is_new(t, &known)).map(|t| t.text.as_str()).collect();
        new.sort_unstable();
        new.dedup();
        // a word the bank doesn't have can't be explained
        let unknown = s.tokens.iter().any(|t| is_vocab(t) && t.word_id.is_none());
        match (unknown, new.len()) {
            (false, 1) => with_new.push(s),
            (false, 0) => without.push(s),
            _ => {}
        }
    }
    let from = if with_new.is_empty() { without } else { with_new };
    if from.is_empty() {
        return None;
    }
    let mut s = from[rng.usize(..from.len())].clone();
    mark_new(&mut s.tokens, &known);
    Some(s)
}

/// The pinned sentence by its id, with new words marked. `None` when its pack isn't loaded.
#[uniffi::export]
pub fn sentence_by_id(id: u64, known_word_ids: Vec<String>) -> Option<Sentence> {
    let s = sentences().read().ok()?.all.iter().find(|s| s.id == id).cloned()?;
    let mut s = resolved(s);
    mark_new(&mut s.tokens, &id_set(known_word_ids));
    Some(s)
}

/// A sentence's tiles, shuffled (never in the right order if there's another one).
#[uniffi::export]
pub fn shuffled_tiles(sentence: Sentence, seed: u64) -> Vec<String> {
    let right = crate::exercises::sentence_tiles(sentence);
    let mut rng = fastrand::Rng::with_seed(seed);
    let mut tiles = right.clone();
    for _ in 0..8 {
        rng.shuffle(&mut tiles);
        if tiles.concat() != right.concat() {
            break;
        }
    }
    tiles
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::content::*;

    fn known(h: &[&str]) -> Vec<String> {
        h.iter().filter_map(|h| crate::words::word_id_for_hanzi(h.to_string())).collect()
    }

    fn spin(count: u32, cosmetics: &[&str]) -> SpinResult {
        let ids = cosmetics.iter().map(|s| s.to_string()).collect();
        spin_slots("p1".into(), count, ids, known(&["我", "很", "好", "他", "是"]), false)
    }

    #[test]
    fn a_spin_for_every_unit() {
        let keys = |k: &[&str]| k.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(spins_left(vec![], 0), 0);
        assert_eq!(spins_left(keys(&["1-1", "1-2", "2-1"]), 0), 3, "they stack up");
        assert_eq!(spins_left(keys(&["1-1", "1-2", "2-1"]), 2), 1);
        assert_eq!(spins_left(keys(&["1-1", "1-1"]), 0), 1, "a unit counts once");
        assert_eq!(spins_left(keys(&["1-1"]), 5), 0, "progress was reset");
    }

    #[test]
    fn the_same_spin_gives_the_same_prize() {
        content_load("sentences".into(), TEST_SENTENCES.into()).unwrap();
        assert_eq!(spin(3, &["fx.fire", "fr.jade"]), spin(3, &["fr.jade", "fx.fire"]), "restarting can't reroll it");
        let first: Vec<Vec<String>> = (0..30).map(|i| spin(i, &["fx.fire"]).reels).collect();
        assert!(first.iter().any(|r| *r != first[0]), "spins differ");
        let a = spin_slots("p1".into(), 1, vec![], vec![], false);
        assert!((0..20).any(|i| spin_slots(format!("q{i}"), 1, vec![], vec![], false) != a), "players differ");
    }

    #[test]
    fn prizes() {
        content_load("words".into(), TEST_WORDS.into()).unwrap();
        content_load("sentences".into(), TEST_SENTENCES.into()).unwrap();
        let symbols = slot_symbols();
        let (mut coins, mut jackpots, mut cosmetics, mut sentences) = (0, 0, 0, 0);
        for i in 0..4000 {
            let r = spin(i, &["fx.fire", "fr.jade"]);
            assert!(r.reels.len() == 3 && r.reels.iter().all(|s| symbols.contains(s)));
            let same = r.reels.iter().all(|s| *s == r.reels[0]);
            match r.prize {
                SlotPrize::Coins { amount, jackpot } => {
                    assert!([20, 50, 100, 500].contains(&amount));
                    assert_eq!(jackpot, amount == 500);
                    assert_eq!(same, amount != 20, "{amount}: {:?}", r.reels);
                    coins += 1;
                    jackpots += jackpot as u32;
                }
                SlotPrize::Cosmetic { id } => {
                    assert!(same && ["fx.fire", "fr.jade"].contains(&id.as_str()));
                    cosmetics += 1;
                }
                SlotPrize::Sentence { sentence } => {
                    assert!(same);
                    let mut new: Vec<&str> = sentence.tokens.iter().filter(|t| t.is_new).map(|t| t.text.as_str()).collect();
                    new.dedup();
                    assert!(new.len() <= 1, "{}", sentence.zh);
                    sentences += 1;
                }
            }
        }
        assert!(jackpots > 20 && jackpots < 200, "{jackpots} jackpots");
        assert!(coins > 2000 && cosmetics > 300 && sentences > 700, "{coins} {cosmetics} {sentences}");
        // a sentence is still waiting: none is won on top of it
        for i in 0..400 {
            let r = spin_slots("p1".into(), i, vec![], known(&["我", "很", "好", "他", "是"]), true);
            assert!(!matches!(r.prize, SlotPrize::Sentence { .. }));
        }
        // owns everything, knows nothing: always coins
        for i in 0..200 {
            let r = spin_slots("p1".into(), i, vec![], vec![], false);
            assert!(matches!(r.prize, SlotPrize::Coins { .. }));
        }
    }

    #[test]
    fn the_pinned_sentence() {
        content_load("sentences".into(), TEST_SENTENCES.into()).unwrap();
        let s = sentence_by_id(4, known(&["我", "很"])).unwrap();
        assert_eq!(s.zh, "我很好。");
        assert_eq!(s.tokens.iter().filter(|t| t.is_new).map(|t| t.text.as_str()).collect::<Vec<_>>(), vec!["好"]);
        assert!(sentence_by_id(999_999, vec![]).is_none());
        let t = shuffled_tiles(s.clone(), 5);
        assert_ne!(t.concat(), "我很好");
        assert!(crate::game::pinyin_typed_ok("wo hen hao".into(), s.pinyin));
    }
}
