//! Sentence exercises built from the downloaded sentence packs.

use std::collections::HashSet;

use crate::challenge::day_seed;
use crate::content::{resolved, sentences, Sentence, Token};
use crate::vocab::{id_set, is_vocab, mark_new, IdSet};
use crate::words::{bank, CoreWord};

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

/// The letters of a pinyin line: two sentences that sound the same can't be told apart by ear or by pinyin.
fn sound(s: &Sentence) -> String {
    s.pinyin.chars().filter(|c| c.is_alphabetic()).flat_map(char::to_lowercase).collect()
}

/// Up to three other sentences' field values as distractors, nearest in length first (never a homophone).
fn distractors(rng: &mut fastrand::Rng, s: &Sentence, pool: &[Sentence], field: fn(&Sentence) -> &str) -> Vec<String> {
    let mine = field(s);
    let my_sound = sound(s);
    let mut cands: Vec<&Sentence> =
        pool.iter().filter(|o| o.id != s.id && field(o) != mine && sound(o) != my_sound).collect();
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

/// Where wrong options come from.
struct Options<'a> {
    /// English distractors.
    english: &'a [Sentence],
    /// Chinese distractors (shown as characters).
    chinese: &'a [Sentence],
    /// Only these words may fill a gap (None = any word of a close level).
    gap_words: Option<&'a HashSet<String>>,
}

fn build(rng: &mut fastrand::Rng, s: Sentence, from: &Options, kind: ExerciseKind) -> Exercise {
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
            let allowed = |w: &&CoreWord| w.hanzi != answer && from.gap_words.is_none_or(|k| k.contains(&w.hanzi));
            let b = bank();
            let mut cands: Vec<String> = b
                .regular
                .iter()
                .filter(allowed)
                .filter(|w| w.hanzi.chars().count() == len && w.level.abs_diff(s.level) <= 1)
                .map(|w| w.hanzi.clone())
                .collect();
            if cands.len() < 3 {
                cands = b.regular.iter().filter(allowed).map(|w| w.hanzi.clone()).collect();
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
            let others = distractors(rng, &s, from.english, |o| o.en.as_str());
            let (options, i) = with_answer(rng, s.en.clone(), others);
            ex.options = options;
            ex.answer = i;
        }
        ExerciseKind::PinyinPick => {
            let others = distractors(rng, &s, from.chinese, |o| o.zh.as_str());
            let (options, i) = with_answer(rng, s.zh.clone(), others);
            ex.options = options;
            ex.answer = i;
        }
    }
    ex
}

fn hanzi_of(ids: &IdSet) -> HashSet<String> {
    let b = bank();
    ids.iter().filter_map(|id| b.by_id.get(id)).map(|w| w.hanzi.clone()).collect()
}

/// A sentence lesson for practice: `count` exercises from sentences at or below `max_level`, preferring
/// sentences built from words the learner knows (`known_word_ids`) plus at most one or two new ones (their
/// tokens are marked `is_new`). The same `seed` gives the same lesson.
#[uniffi::export]
pub fn sentence_lesson(max_level: u8, known_word_ids: Vec<String>, count: u32, seed: u64, can_listen: bool) -> Vec<Exercise> {
    let mut rng = fastrand::Rng::with_seed(seed);
    let known_ids = id_set(known_word_ids);
    let known = hanzi_of(&known_ids);
    let store = sentences().read().unwrap_or_else(|e| e.into_inner());
    let max_level = max_level.max(1);
    let pool: Vec<&Sentence> = store.all.iter().filter(|s| s.level <= max_level).collect();
    if pool.is_empty() {
        return vec![];
    }
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
    let from = Options { english: &all_pool, chinese: &all_pool, gap_words: None };
    chosen
        .into_iter()
        .map(|s| {
            let mut s = resolved(s);
            mark_new(&mut s.tokens, &known_ids);
            let kind = pick_kind(&mut rng, &s, can_listen);
            build(&mut rng, s, &from, kind)
        })
        .collect()
}

/// Exercises in a sentence node on the learning path.
pub const SENTENCE_NODE_COUNT: usize = 8;

/// A one-word "sentence", so word questions can fill up a sentence lesson.
fn word_sentence(w: &CoreWord) -> Sentence {
    // ids far above any Tatoeba sentence, stable per word
    let id = w.hanzi.chars().fold(1u64 << 48, |h, c| h.wrapping_mul(131).wrapping_add(c as u64)) | 1 << 63;
    Sentence {
        id,
        zh: w.hanzi.clone(),
        pinyin: w.pinyin.clone(),
        en: w.short_meaning().to_string(),
        tokens: vec![Token { text: w.hanzi.clone(), pinyin: w.pinyin.clone(), word_id: Some(w.id.clone()), is_new: false }],
        author: String::new(),
        level: w.level,
    }
}

/// The lesson behind a sentence node: only words in `known_word_ids` appear, anywhere (sentences, gap options
/// and Chinese choices). Sentences that use the unit's words come first; when there aren't enough sentences,
/// the rest are questions about the unit's own (known) words. Seeded from the node and the day, so a retry
/// gives the same lesson.
#[uniffi::export]
pub fn sentence_node_lesson(unit: u32, number: u32, day_key: String, known_word_ids: Vec<String>, unit_word_ids: Vec<String>, can_listen: bool) -> Vec<Exercise> {
    let seed = (day_seed(day_key) as u64) ^ ((unit as u64) << 40) ^ ((number as u64) << 52);
    let mut rng = fastrand::Rng::with_seed(seed);
    let known_ids = id_set(known_word_ids);
    let known = hanzi_of(&known_ids);
    let (unit_words, known_words): (Vec<CoreWord>, Vec<CoreWord>) = {
        let b = bank();
        (
            unit_word_ids.iter().filter(|id| known_ids.contains(*id)).filter_map(|id| b.by_id.get(id)).cloned().collect(),
            b.regular.iter().filter(|w| known_ids.contains(&w.id)).cloned().collect(),
        )
    };
    let unit_hanzi: HashSet<&str> = unit_words.iter().map(|w| w.hanzi.as_str()).collect();

    let (readable, english): (Vec<Sentence>, Vec<Sentence>) = {
        let store = sentences().read().unwrap_or_else(|e| e.into_inner());
        let readable = store
            .all
            .iter()
            .filter(|s| s.words().count() >= 2)
            .filter(|s| s.words().all(|t| known.contains(&t.text) || !is_vocab(t)))
            .cloned()
            .collect();
        (readable, store.all.iter().take(2000).cloned().collect())
    };
    // the unit's words first, then about seven characters long
    let mut scored: Vec<(i64, &Sentence)> = readable
        .iter()
        .map(|s| {
            let unit = s.words().filter(|t| unit_hanzi.contains(t.text.as_str())).count().min(3) as i64;
            let len = s.zh.chars().count() as i64;
            (rng.i64(0..4) + (len - 7).abs() / 2 - unit * 4, s)
        })
        .collect();
    scored.sort_by_key(|(c, _)| *c);
    let chosen: Vec<Sentence> = scored.into_iter().take(SENTENCE_NODE_COUNT).map(|(_, s)| s.clone()).collect();

    let from = Options { english: &english, chinese: &readable, gap_words: Some(&known) };
    let mut out: Vec<Exercise> = chosen
        .into_iter()
        .map(|s| {
            let mut s = resolved(s);
            mark_new(&mut s.tokens, &known_ids);
            let mut kind = pick_kind(&mut rng, &s, can_listen);
            // too little known Chinese for wrong choices: ask for the meaning instead
            if (kind == ExerciseKind::PinyinPick && readable.len() < 4) || (kind == ExerciseKind::FillGap && known.len() < 4) {
                kind = ExerciseKind::TranslatePick;
            }
            build(&mut rng, s, &from, kind)
        })
        .collect();

    // Not enough sentences: questions about single words, the unit's first.
    let known_pool: Vec<Sentence> = known_words.iter().map(word_sentence).collect();
    let meanings: Vec<Sentence> = {
        let b = bank();
        b.regular.iter().take(400).map(word_sentence).collect()
    };
    let words = Options { english: if known_pool.len() >= 8 { &known_pool } else { &meanings }, chinese: &known_pool, gap_words: Some(&known) };
    let mut fill: Vec<CoreWord> = unit_words.clone();
    rng.shuffle(&mut fill);
    let mut rest: Vec<CoreWord> = known_words.into_iter().filter(|w| !unit_hanzi.contains(w.hanzi.as_str())).collect();
    rng.shuffle(&mut rest);
    fill.extend(rest);
    for w in fill.into_iter().take(SENTENCE_NODE_COUNT - out.len().min(SENTENCE_NODE_COUNT)) {
        let mut kinds = vec![ExerciseKind::TranslatePick];
        if known_pool.len() >= 4 {
            kinds.push(ExerciseKind::PinyinPick);
        }
        if can_listen {
            kinds.push(ExerciseKind::ListenPick);
        }
        let kind = kinds[rng.usize(..kinds.len())];
        out.push(build(&mut rng, word_sentence(&w), &words, kind));
    }
    out
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
            let from = Options { english: &pool, chinese: &pool, gap_words: None };
            let ex = build(&mut rng, s.clone(), &from, kind);
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
    #[test]
    fn homophones_are_never_wrong_options() {
        let s = |id, zh: &str, py: &str, en: &str| Sentence { id, zh: zh.into(), pinyin: py.into(), en: en.into(), tokens: vec![], author: String::new(), level: 1 };
        let he = s(1, "他很好。", "Tā hěn hǎo.", "He is well.");
        let pool = vec![he.clone(), s(2, "她很好！", "Tā hěn hǎo!", "She is well."), s(3, "我很好。", "Wǒ hěn hǎo.", "I'm well.")];
        let mut rng = fastrand::Rng::with_seed(1);
        assert_eq!(distractors(&mut rng, &he, &pool, |o| o.zh.as_str()), vec!["我很好。".to_string()]);
    }

    #[test]
    fn practice_marks_new_words() {
        load();
        let known: Vec<String> = ["我", "你", "他", "是"].iter().filter_map(|h| crate::words::word_id_for_hanzi(h.to_string())).collect();
        let lesson = sentence_lesson(2, known.clone(), 5, 1, false);
        assert!(lesson.iter().flat_map(|e| &e.sentence.tokens).any(|t| t.is_new));
        for t in lesson.iter().flat_map(|e| &e.sentence.tokens) {
            let expect = t.word_id.as_ref().is_some_and(|id| !known.contains(id));
            assert_eq!(t.is_new, expect, "{}", t.text);
        }
    }

    /// Every Chinese word the lesson shows, options and tiles included.
    fn unknown_words(lesson: &[Exercise], known: &HashSet<String>) -> Vec<String> {
        let mut bad = vec![];
        for ex in lesson {
            bad.extend(ex.sentence.tokens.iter().filter(|t| is_vocab(t) && !known.contains(&t.text)).map(|t| t.text.clone()));
            bad.extend(ex.tiles.iter().filter(|t| !known.contains(*t)).cloned());
            if ex.kind == ExerciseKind::FillGap {
                bad.extend(ex.options.iter().filter(|o| !known.contains(*o)).cloned());
            }
            if ex.kind == ExerciseKind::PinyinPick {
                let store = sentences().read().unwrap();
                let readable = |o: &String| {
                    known.contains(o) || store.all.iter().any(|s| s.zh == *o && s.words().all(|t| known.contains(&t.text)))
                };
                bad.extend(ex.options.iter().filter(|o| !readable(o)).cloned());
            }
            assert!(ex.sentence.tokens.iter().all(|t| !t.is_new));
        }
        bad
    }

    #[test]
    fn node_lessons_use_only_learned_words() {
        load();
        let words: Vec<CoreWord> = crate::words::bundled_words().into_iter().filter(|w| w.level == 1).collect();
        for n in [5, 15, 25, 50] {
            let known: Vec<String> = words.iter().take(n).map(|w| w.id.clone()).collect();
            let hanzi: HashSet<String> = words.iter().take(n).map(|w| w.hanzi.clone()).collect();
            // the unit also has words that aren't learned yet: they must not appear
            let unit: Vec<String> = words.iter().take(n + 10).map(|w| w.id.clone()).collect();
            for day in ["2026-11-22", "2026-11-23", "2026-11-24"] {
                for number in [3, 5, 8] {
                    let lesson = sentence_node_lesson(1, number, day.into(), known.clone(), unit.clone(), true);
                    assert!(lesson.len() >= n.min(SENTENCE_NODE_COUNT), "word questions fill the gap");
                    assert!(unknown_words(&lesson, &hanzi).is_empty(), "{:?}", unknown_words(&lesson, &hanzi));
                    for ex in &lesson {
                        if ex.kind != ExerciseKind::WordOrder {
                            assert!(ex.options.len() >= 2, "{ex:?}");
                            let uniq: HashSet<_> = ex.options.iter().collect();
                            assert_eq!(uniq.len(), ex.options.len());
                        }
                    }
                }
            }
        }
        assert!(sentence_node_lesson(1, 3, "2026-11-22".into(), vec![], vec![], true).is_empty(), "nothing learned, nothing to ask");
    }

    #[test]
    fn node_retry_is_the_same_lesson() {
        load();
        let mut known: Vec<String> = crate::words::bundled_words().into_iter().take(40).map(|w| w.id).collect();
        let unit = known[..15].to_vec();
        let make = |known: &Vec<String>, number, day: &str| sentence_node_lesson(1, number, day.into(), known.clone(), unit.clone(), true);
        let a = make(&known, 3, "2026-11-22");
        known.reverse();
        assert_eq!(a, make(&known, 3, "2026-11-22"), "the order the app lists known words in doesn't matter");
        assert_ne!(a, make(&known, 5, "2026-11-22"));
        assert_ne!(a, make(&known, 3, "2026-11-23"));
    }
}
