//! The built-in vocabulary (compiled into the library) and quiz option building.

use std::collections::HashMap;
use std::sync::OnceLock;

/// Street words (swears) live on this level.
pub const STREET_LEVEL: u8 = 5;

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

fn parse(text: &str) -> Vec<CoreWord> {
    text.lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .filter_map(|line| {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() < 7 {
                return None;
            }
            let level: u8 = f[0].parse().ok()?;
            Some(CoreWord {
                id: format!("{}-{}", level, f[1]),
                level,
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

struct Bank {
    regular: Vec<CoreWord>,
    swears: Vec<CoreWord>,
    by_id: HashMap<String, CoreWord>,
}

fn bank() -> &'static Bank {
    static BANK: OnceLock<Bank> = OnceLock::new();
    BANK.get_or_init(|| {
        let regular = parse(include_str!("../data/words.tsv"));
        let swears = parse(include_str!("../data/swears.tsv"));
        let by_id = regular.iter().chain(swears.iter()).map(|w| (w.id.clone(), w.clone())).collect();
        Bank { regular, swears, by_id }
    })
}

/// Regular vocabulary (HSK 1–4).
#[uniffi::export]
pub fn all_words() -> Vec<CoreWord> {
    bank().regular.clone()
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
}
