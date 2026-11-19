//! Sentence exercises built from the downloaded sentence packs.

use std::collections::HashSet;

use crate::content::{resolved, sentences, Sentence};
use crate::words::bank;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ExerciseKind {
    /// Tap the shuffled word tiles into the right order.
    WordOrder,
    /// One word is blanked out; pick it from four.
    FillGap,
    /// Hear the sentence, pick what it means.
    ListenPick,
    /// Read the characters, pick the English.
    TranslatePick,
    /// Read the pinyin, pick the characters.
    PinyinPick,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Exercise {
    pub kind: ExerciseKind,
    pub sentence: Sentence,
    /// WordOrder: shuffled tiles (token texts, punctuation removed).
    pub tiles: Vec<String>,
    /// FillGap: index into `sentence.tokens` that is blanked.
    pub gap: u32,
    /// Pick kinds: the choices (English, characters or the missing word).
    pub options: Vec<String>,
    /// Index of the right option.
    pub answer: u32,
}

/// The tiles of a sentence in the right order (punctuation dropped).
#[uniffi::export]
pub fn sentence_tiles(sentence: Sentence) -> Vec<String> {
    sentence.words().map(|t| t.text.clone()).collect()
}

/// WordOrder check. Compares the joined characters, so two identical tiles can swap freely.
#[uniffi::export]
pub fn word_order_correct(sentence: Sentence, attempt: Vec<String>) -> bool {
    sentence_tiles(sentence).concat() == attempt.concat()
}

fn pick_kind(rng: &mut fastrand::Rng, s: &Sentence, can_listen: bool) -> ExerciseKind {
    let tiles = s.words().count();
    let mut kinds = vec![ExerciseKind::TranslatePick, ExerciseKind::PinyinPick];
    if (3..=9).contains(&tiles) {
        kinds.push(ExerciseKind::WordOrder);
        kinds.push(ExerciseKind::WordOrder);
    }
    if tiles >= 3 {
        kinds.push(ExerciseKind::FillGap);
    }
    if can_listen {
        kinds.push(ExerciseKind::ListenPick);
    }
    kinds[rng.usize(..kinds.len())]
}

/// Up to three other sentences' field values as distractors, nearest in length first.
fn distractors(rng: &mut fastrand::Rng, s: &Sentence, pool: &[Sentence], field: fn(&Sentence) -> &str) -> Vec<String> {
    let mine = field(s);
    let mut cands: Vec<&Sentence> = pool.iter().filter(|o| o.id != s.id && field(o) != mine).collect();
    rng.shuffle(&mut cands);
    let len = mine.chars().count() as i64;
    cands.truncate(24);
    cands.sort_by_key(|o| (field(o).chars().count() as i64 - len).abs());
    let mut out: Vec<String> = Vec::new();
    for c in cands {
        let v = field(c).to_string();
        if !out.contains(&v) {
            out.push(v);
        }
        if out.len() == 3 {
            break;
        }
    }
    out
}

fn with_answer(rng: &mut fastrand::Rng, answer: String, mut others: Vec<String>) -> (Vec<String>, u32) {
    others.push(answer.clone());
    rng.shuffle(&mut others);
    let i = others.iter().position(|o| *o == answer).unwrap_or(0) as u32;
    (others, i)
}

pub(crate) fn build(rng: &mut fastrand::Rng, s: Sentence, pool: &[Sentence], kind: ExerciseKind) -> Exercise {
    let mut ex = Exercise { kind, sentence: s.clone(), tiles: vec![], gap: 0, options: vec![], answer: 0 };
    match kind {
        ExerciseKind::WordOrder => {
            let right = sentence_tiles(s.clone());
            let mut tiles = right.clone();
            for _ in 0..8 {
                rng.shuffle(&mut tiles);
                if tiles.concat() != right.concat() {
                    break;
                }
            }
            ex.tiles = tiles;
        }
        ExerciseKind::FillGap => {
            // Blank the content word with the most characters (ties: random), never punctuation.
            let mut idx: Vec<usize> = (0..s.tokens.len()).filter(|&i| !s.tokens[i].pinyin.is_empty()).collect();
            rng.shuffle(&mut idx);
            idx.sort_by_key(|&i| std::cmp::Reverse(s.tokens[i].text.chars().count()));
            let gap = idx.first().copied().unwrap_or(0);
            let answer = s.tokens[gap].text.clone();
            let len = answer.chars().count();
            // Distractors: bank words of the same length and close level.
            let b = bank();
            let mut cands: Vec<String> = b
                .regular
                .iter()
                .filter(|w| w.hanzi.chars().count() == len && w.hanzi != answer && w.level.abs_diff(s.level) <= 1)
                .map(|w| w.hanzi.clone())
                .collect();
            if cands.len() < 3 {
                cands = b.regular.iter().filter(|w| w.hanzi != answer).map(|w| w.hanzi.clone()).collect();
            }
            rng.shuffle(&mut cands);
            cands.dedup();
            cands.truncate(3);
            let (options, i) = with_answer(rng, answer, cands);
            ex.gap = gap as u32;
            ex.options = options;
            ex.answer = i;
        }
        ExerciseKind::ListenPick | ExerciseKind::TranslatePick => {
            let others = distractors(rng, &s, pool, |o| o.en.as_str());
            let (options, i) = with_answer(rng, s.en.clone(), others);
            ex.options = options;
            ex.answer = i;
        }
        ExerciseKind::PinyinPick => {
            let others = distractors(rng, &s, pool, |o| o.zh.as_str());
            let (options, i) = with_answer(rng, s.zh.clone(), others);
            ex.options = options;
            ex.answer = i;
        }
    }
    ex
}

/// A sentence lesson: `count` exercises from sentences at or below `max_level`, preferring sentences
/// built from words the learner knows (`known_word_ids`) plus at most one or two new ones.
/// The same `seed` gives the same lesson.
#[uniffi::export]
pub fn sentence_lesson(max_level: u8, known_word_ids: Vec<String>, count: u32, seed: u64, can_listen: bool) -> Vec<Exercise> {
    let mut rng = fastrand::Rng::with_seed(seed);
    let store = sentences().read().unwrap_or_else(|e| e.into_inner());
    let max_level = max_level.max(1);
    let pool: Vec<&Sentence> = store.all.iter().filter(|s| s.level <= max_level).collect();
    if pool.is_empty() {
        return vec![];
    }
    let known: HashSet<String> = {
        let b = bank();
        known_word_ids.iter().filter_map(|id| b.by_id.get(id)).map(|w| w.hanzi.clone()).collect()
    };
    // Score: unknown words cost a lot; sentences with 1 unknown word are the sweet spot.
    let mut scored: Vec<(i64, &Sentence)> = pool
        .iter()
        .map(|s| {
            let unknown = s.words().filter(|t| !known.contains(&t.text)).count() as i64;
            let fresh = rng.i64(0..4);
            let len = s.zh.chars().count() as i64;
            // Sweet spot ~7 characters; with known words, exactly one new word per sentence.
            let cost = if known.is_empty() { (len - 7).abs() } else { (unknown - 1).abs() * 10 + (len - 7).abs() / 2 };
            (cost + fresh, *s)
        })
        .collect();
    scored.sort_by_key(|(c, _)| *c);
    let chosen: Vec<Sentence> = scored.iter().take(count as usize).map(|(_, s)| (*s).clone()).collect();
    let all_pool: Vec<Sentence> = pool.iter().take(2000).map(|s| (*s).clone()).collect();
    drop(store);
    chosen
        .into_iter()
        .map(|s| {
            let s = resolved(s);
            let kind = pick_kind(&mut rng, &s, can_listen);
            build(&mut rng, s, &all_pool, kind)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::content::*;

    fn load() {
        content_load("words".into(), TEST_WORDS.into()).unwrap();
        content_load("sentences".into(), TEST_SENTENCES.into()).unwrap();
    }

    #[test]
    fn lessons_are_deterministic_and_valid() {
        load();
        let a = sentence_lesson(2, vec!["1-你好".into()], 5, 42, true);
        let b = sentence_lesson(2, vec!["1-你好".into()], 5, 42, true);
        assert_eq!(a, b);
        assert!(!a.is_empty());
        for ex in &a {
            match ex.kind {
                ExerciseKind::WordOrder => {
                    assert!(word_order_correct(ex.sentence.clone(), sentence_tiles(ex.sentence.clone())));
                    let mut sorted = ex.tiles.clone();
                    sorted.sort();
                    let mut right = sentence_tiles(ex.sentence.clone());
                    right.sort();
                    assert_eq!(sorted, right, "tiles are a permutation");
                }
                _ => {
                    assert!((ex.answer as usize) < ex.options.len());
                    let uniq: HashSet<_> = ex.options.iter().collect();
                    assert_eq!(uniq.len(), ex.options.len(), "no duplicate options");
                }
            }
        }
    }

    #[test]
    fn every_kind_builds() {
        load();
        let store = sentences().read().unwrap();
        let pool: Vec<Sentence> = store.all.clone();
        drop(store);
        let s = resolved(pool.iter().find(|s| s.id == 1).unwrap().clone());
        let mut rng = fastrand::Rng::with_seed(1);
        for kind in [ExerciseKind::WordOrder, ExerciseKind::FillGap, ExerciseKind::ListenPick, ExerciseKind::TranslatePick, ExerciseKind::PinyinPick] {
            let ex = build(&mut rng, s.clone(), &pool, kind);
            match kind {
                ExerciseKind::WordOrder => assert_eq!(ex.tiles.len(), 3),
                ExerciseKind::FillGap => {
                    assert_eq!(ex.sentence.tokens[ex.gap as usize].text, ex.options[ex.answer as usize]);
                    assert_eq!(ex.options[ex.answer as usize], "测试");
                }
                ExerciseKind::PinyinPick => assert_eq!(ex.options[ex.answer as usize], s.zh),
                _ => assert_eq!(ex.options[ex.answer as usize], s.en),
            }
        }
        assert!(!word_order_correct(s.clone(), vec!["是".into(), "这".into(), "测试".into()]));
    }
}
