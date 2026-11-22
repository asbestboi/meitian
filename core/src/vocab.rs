//! What the learner knows: new / seen / learned words, and which tokens count as words at all.

use std::collections::HashSet;

use crate::content::Token;
use crate::words::bank;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum WordStatus {
    /// Never shown to the learner.
    New,
    /// Shown (tagged as new) but not learned yet.
    Seen,
    /// In spaced repetition, or at a level the learner has confirmed.
    Learned,
}

pub(crate) type IdSet = HashSet<String>;

pub(crate) fn id_set(ids: Vec<String>) -> IdSet {
    ids.into_iter().collect()
}

fn status(id: &str, known: &IdSet, seen: &IdSet) -> WordStatus {
    if known.contains(id) {
        WordStatus::Learned
    } else if seen.contains(id) {
        WordStatus::Seen
    } else {
        WordStatus::New
    }
}

#[uniffi::export]
pub fn word_status(word_id: String, known_word_ids: Vec<String>, seen_word_ids: Vec<String>) -> WordStatus {
    status(&word_id, &id_set(known_word_ids), &id_set(seen_word_ids))
}

/// `word_status` for several words at once (a whole lesson), in the same order.
#[uniffi::export]
pub fn word_statuses(word_ids: Vec<String>, known_word_ids: Vec<String>, seen_word_ids: Vec<String>) -> Vec<WordStatus> {
    let (known, seen) = (id_set(known_word_ids), id_set(seen_word_ids));
    word_ids.iter().map(|id| status(id, &known, &seen)).collect()
}

/// Every word the learner knows: their learned cards plus the words of the levels they confirmed (placement
/// or level-up test), which the app never teaches them. `confirmed_level` 0 = cards only.
#[uniffi::export]
pub fn known_word_ids(card_ids: Vec<String>, confirmed_level: u8) -> Vec<String> {
    let mut out = card_ids;
    let have: IdSet = out.iter().cloned().collect();
    let b = bank();
    out.extend(b.regular.iter().filter(|w| w.level <= confirmed_level && !have.contains(&w.id)).map(|w| w.id.clone()));
    out
}

/// People and places in the content packs that aren't vocabulary. (Any other token the word bank doesn't have
/// and whose pinyin is capitalised counts as a name too.)
const NAMES: &[&str] = &["小明", "丽丽", "安娜", "张伟", "米米", "老王", "王阿姨", "老李", "汤姆", "玛丽"];

const NUMERALS: &str = "零〇一二两三四五六七八九十百千万亿";
/// Ordinary words written with numerals only.
const NOT_NUMBERS: &[&str] = &["万一", "千万"];

fn is_hanzi(c: char) -> bool {
    matches!(c, '\u{4e00}'..='\u{9fff}' | '\u{3400}'..='\u{4dbf}' | '〇')
}

pub(crate) fn is_number(text: &str) -> bool {
    !text.is_empty() && !NOT_NUMBERS.contains(&text) && text.chars().all(|c| c.is_numeric() || NUMERALS.contains(c))
}

/// A name: on the list, or capitalised pinyin on something that isn't in the word bank.
pub(crate) fn is_name(t: &Token) -> bool {
    NAMES.contains(&t.text.as_str()) || (t.word_id.is_none() && t.pinyin.chars().next().is_some_and(char::is_uppercase))
}

/// Does the token count as vocabulary? Punctuation, emoji, Latin text, numbers and names don't.
pub(crate) fn is_vocab(t: &Token) -> bool {
    !t.pinyin.is_empty() && t.text.chars().any(is_hanzi) && !is_number(&t.text) && !is_name(t)
}

/// A dictionary word the learner hasn't learned yet. Fragments the word bank doesn't have can't be taught,
/// so they are never "new".
pub(crate) fn is_new(t: &Token, known: &IdSet) -> bool {
    is_vocab(t) && t.word_id.as_ref().is_some_and(|id| !known.contains(id))
}

/// Fills in `is_new` (the tokens' word ids must be resolved already).
pub(crate) fn mark_new(tokens: &mut [Token], known: &IdSet) {
    for t in tokens.iter_mut() {
        t.is_new = is_new(t, known);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tok(text: &str, pinyin: &str, id: Option<&str>) -> Token {
        Token { text: text.into(), pinyin: pinyin.into(), word_id: id.map(Into::into), is_new: false }
    }

    #[test]
    fn statuses() {
        let known = vec!["a".to_string()];
        let seen = vec!["a".to_string(), "b".to_string()];
        assert_eq!(word_status("a".into(), known.clone(), seen.clone()), WordStatus::Learned, "learned beats seen");
        assert_eq!(word_status("b".into(), known.clone(), seen.clone()), WordStatus::Seen);
        assert_eq!(word_status("c".into(), known.clone(), seen.clone()), WordStatus::New);
        assert_eq!(
            word_statuses(vec!["c".into(), "a".into(), "b".into()], known, seen),
            vec![WordStatus::New, WordStatus::Learned, WordStatus::Seen]
        );
    }

    #[test]
    fn confirmed_levels_are_known() {
        let cards = vec!["x".to_string()];
        assert_eq!(known_word_ids(cards.clone(), 0), cards);
        let ids = known_word_ids(vec!["1-你好".into()], 1);
        assert_eq!(ids.iter().filter(|i| *i == "1-你好").count(), 1, "no duplicates");
        assert!(ids.contains(&"1-谢谢".to_string()));
        assert!(ids.iter().all(|i| crate::words::word_by_id(i.clone()).is_some_and(|w| w.level == 1)));
    }

    #[test]
    fn what_counts_as_a_word() {
        assert!(is_vocab(&tok("喜欢", "xǐhuan", Some("1-喜欢"))));
        assert!(is_vocab(&tok("北京", "Běijīng", Some("h1-北京"))), "places in the word bank are vocabulary");
        for t in [
            tok("。", "", None),
            tok("KTV", "KTV", None),
            tok("三十", "sānshí", None),
            tok("三", "sān", Some("h1-三")),
            tok("2026", "èr", None),
            tok("小明", "Xiǎomíng", None),
            tok("安娜", "ānnà", None),
            tok("成都", "Chéngdū", None),
        ] {
            assert!(!is_vocab(&t), "{}", t.text);
        }
        assert!(is_vocab(&tok("万一", "wànyī", Some("h4-万一"))));
        let known = id_set(vec!["1-喜欢".into()]);
        assert!(!is_new(&tok("喜欢", "xǐhuan", Some("1-喜欢")), &known));
        assert!(is_new(&tok("朋友", "péngyou", Some("1-朋友")), &known));
        assert!(!is_new(&tok("们", "men", None), &known), "not in the bank: can't be learned");
        let mut line = vec![tok("朋友", "péngyou", Some("1-朋友")), tok("。", "", None)];
        mark_new(&mut line, &known);
        assert_eq!(line.iter().map(|t| t.is_new).collect::<Vec<_>>(), vec![true, false]);
    }
}
