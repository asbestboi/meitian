//! The built-in vocabulary (compiled into the library) and quiz option building.

use std::collections::HashMap;
use std::sync::{OnceLock, RwLock, RwLockReadGuard, RwLockWriteGuard};

/// Street words (swears) use this level so they never collide with HSK bands 1–6.
/// (Their ids keep the historical "5-" prefix so saved progress still matches.)
pub const STREET_LEVEL: u8 = 99;

/// The UI filter value for the street deck.
#[uniffi::export]
pub fn street_level() -> u8 {
    STREET_LEVEL
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, uniffi::Record)]
pub struct CoreWord {
    pub id: String,
    pub level: u8,
    pub hanzi: String,
    pub pinyin: String,
    pub meaning: String,
    pub example: String,
    pub example_pinyin: String,
    pub example_meaning: String,
    /// Street words only: 1 = mild, 2 = rude, 3 = very strong. 0 otherwise.
    pub intensity: u8,
}

impl CoreWord {
    pub fn short_meaning(&self) -> &str {
        self.meaning.split(',').next().unwrap_or(&self.meaning).trim()
    }
    pub fn is_swear(&self) -> bool {
        self.level == STREET_LEVEL
    }
}

fn parse(text: &str, street: bool) -> Vec<CoreWord> {
    text.lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .filter_map(|line| {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() < 7 {
                return None;
            }
            let file_level: u8 = f[0].parse().ok()?;
            Some(CoreWord {
                id: format!("{}-{}", file_level, f[1]),
                level: if street { STREET_LEVEL } else { file_level },
                hanzi: f[1].into(),
                pinyin: f[2].into(),
                meaning: f[3].into(),
                example: f[4].into(),
                example_pinyin: f[5].into(),
                example_meaning: f[6].into(),
                intensity: f.get(7).and_then(|s| s.parse().ok()).unwrap_or(0),
            })
        })
        .collect()
}

/// Built-in words plus whatever content packs were loaded at runtime.
pub(crate) struct Bank {
    /// Regular vocabulary: the bundled words first, then downloaded ones.
    pub regular: Vec<CoreWord>,
    /// How many of `regular` are bundled (identical on every install, so battles use only these).
    pub bundled: usize,
    pub swears: Vec<CoreWord>,
    pub by_id: HashMap<String, CoreWord>,
    pub by_hanzi: HashMap<String, String>,
}

impl Bank {
    fn bundled() -> Bank {
        let regular = parse(include_str!("../data/words.tsv"), false);
        let swears = parse(include_str!("../data/swears.tsv"), true);
        let mut b = Bank { bundled: regular.len(), regular, swears, by_id: HashMap::new(), by_hanzi: HashMap::new() };
        b.reindex();
        b
    }

    fn reindex(&mut self) {
        self.by_id = self.regular.iter().chain(self.swears.iter()).map(|w| (w.id.clone(), w.clone())).collect();
        self.by_hanzi = self.regular.iter().map(|w| (w.hanzi.clone(), w.id.clone())).collect();
    }

    /// Adds downloaded words, skipping characters the bank already has. Returns how many were new.
    pub(crate) fn add(&mut self, words: Vec<CoreWord>) -> u32 {
        let mut added = 0;
        for w in words {
            if self.by_hanzi.contains_key(&w.hanzi) || self.by_id.contains_key(&w.id) {
                continue;
            }
            self.by_hanzi.insert(w.hanzi.clone(), w.id.clone());
            self.by_id.insert(w.id.clone(), w.clone());
            self.regular.push(w);
            added += 1;
        }
        added
    }

    pub(crate) fn reset(&mut self) {
        self.regular.truncate(self.bundled);
        self.reindex();
    }
}

fn lock() -> &'static RwLock<Bank> {
    static BANK: OnceLock<RwLock<Bank>> = OnceLock::new();
    BANK.get_or_init(|| RwLock::new(Bank::bundled()))
}

pub(crate) fn bank() -> RwLockReadGuard<'static, Bank> {
    lock().read().unwrap_or_else(|e| e.into_inner())
}

pub(crate) fn bank_mut() -> RwLockWriteGuard<'static, Bank> {
    lock().write().unwrap_or_else(|e| e.into_inner())
}

/// Regular vocabulary: bundled HSK 1–4 basics plus downloaded HSK 1–6 packs.
#[uniffi::export]
pub fn all_words() -> Vec<CoreWord> {
    bank().regular.clone()
}

/// Only the words compiled into the app — the same on every phone (used for battles).
#[uniffi::export]
pub fn bundled_words() -> Vec<CoreWord> {
    let b = bank();
    b.regular[..b.bundled].to_vec()
}

/// The opt-in street deck.
#[uniffi::export]
pub fn swear_words() -> Vec<CoreWord> {
    bank().swears.clone()
}

#[uniffi::export]
pub fn word_by_id(id: String) -> Option<CoreWord> {
    bank().by_id.get(&id).cloned()
}

/// The word id for some characters, if they're in the bank.
#[uniffi::export]
pub fn word_id_for_hanzi(hanzi: String) -> Option<String> {
    bank().by_hanzi.get(&hanzi).cloned()
}

/// HSK levels that currently have words, ascending.
#[uniffi::export]
pub fn word_levels() -> Vec<u8> {
    let mut l: Vec<u8> = bank().regular.iter().map(|w| w.level).collect();
    l.sort_unstable();
    l.dedup();
    l
}

/// Words visible with the given swear setting.
#[uniffi::export]
pub fn visible_words(swears: bool) -> Vec<CoreWord> {
    let b = bank();
    if swears {
        b.regular.iter().chain(b.swears.iter()).cloned().collect()
    } else {
        b.regular.clone()
    }
}

/// Four shuffled option ids for a multiple-choice question: the answer plus three distractors,
/// preferring `pool` and never repeating a meaning or the same characters.
#[uniffi::export]
pub fn quiz_options(answer_id: String, pool_ids: Vec<String>) -> Vec<String> {
    let b = bank();
    let Some(answer) = b.by_id.get(&answer_id) else { return vec![answer_id] };
    let ok = |w: &CoreWord| w.id != answer.id && w.short_meaning() != answer.short_meaning() && w.hanzi != answer.hanzi;
    let mut distractors: Vec<&CoreWord> = pool_ids.iter().filter_map(|id| b.by_id.get(id)).filter(|w| ok(w)).collect();
    fastrand::shuffle(&mut distractors);
    distractors.dedup_by(|a, b| a.short_meaning() == b.short_meaning());
    if distractors.len() < 3 {
        let mut extra: Vec<&CoreWord> = b.regular.iter().filter(|w| ok(w) && !distractors.iter().any(|d| d.id == w.id)).collect();
        fastrand::shuffle(&mut extra);
        distractors.extend(extra);
    }
    let mut ids: Vec<String> = std::iter::once(answer.id.clone())
        .chain(distractors.into_iter().take(3).map(|w| w.id.clone()))
        .collect();
    fastrand::shuffle(&mut ids);
    ids
}

/// One learned word's review record, for picking weak words.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CardStat {
    pub id: String,
    pub box_level: u8,
    pub correct: u32,
    pub wrong: u32,
}

/// How weak a word is: 0 = solid. Wrong-answer rate (smoothed so one slip doesn't dominate) plus a
/// little extra for words still in the low Leitner boxes.
#[uniffi::export]
pub fn weakness(stat: CardStat) -> f64 {
    let answered = stat.correct + stat.wrong;
    if answered < 2 || stat.wrong == 0 {
        return 0.0;
    }
    let rate = (stat.wrong as f64 + 0.5) / (answered as f64 + 2.0);
    let low_box = (4.0 - stat.box_level.min(4) as f64).max(0.0) * 0.05;
    rate + low_box
}

/// The learner's weakest words, weakest first (only words they've got wrong at least once and answered
/// at least twice).
#[uniffi::export]
pub fn weak_word_ids(stats: Vec<CardStat>, limit: u32) -> Vec<String> {
    let mut scored: Vec<(f64, String)> =
        stats.into_iter().map(|s| (weakness(s.clone()), s.id)).filter(|(w, _)| *w > 0.0).collect();
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.1.cmp(&b.1)));
    scored.into_iter().take(limit as usize).map(|(_, id)| id).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_both_decks() {
        assert!(all_words().len() >= 190);
        assert!(swear_words().len() >= 30);
        assert!(swear_words().iter().all(|w| w.is_swear() && w.intensity > 0));
        let ids: std::collections::HashSet<_> = visible_words(true).into_iter().map(|w| w.id).collect();
        assert_eq!(ids.len(), all_words().len() + swear_words().len(), "ids must be unique");
    }

    #[test]
    fn options_contain_answer_once() {
        let pool: Vec<String> = all_words().iter().take(20).map(|w| w.id.clone()).collect();
        for id in pool.iter().take(10) {
            let opts = quiz_options(id.clone(), pool.clone());
            assert_eq!(opts.len(), 4);
            assert_eq!(opts.iter().filter(|o| *o == id).count(), 1);
        }
    }

    #[test]
    fn weak_words() {
        let st = |id: &str, b, c, w| CardStat { id: id.into(), box_level: b, correct: c, wrong: w };
        let ids = weak_word_ids(
            vec![st("solid", 5, 10, 0), st("once", 2, 0, 1), st("bad", 1, 1, 5), st("meh", 3, 6, 2), st("slip", 5, 9, 1)],
            10,
        );
        assert_eq!(ids, vec!["bad", "meh", "slip"]);
        assert_eq!(weak_word_ids(vec![st("bad", 1, 1, 5), st("meh", 3, 6, 2)], 1), vec!["bad"]);
    }
}
