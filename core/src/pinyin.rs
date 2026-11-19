//! Pinyin: tone detection, splitting words like "xièxie" into syllables, and lining syllables up
//! with characters for ruby display (pinyin above each character).

const INITIALS: [&str; 23] = [
    "zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w",
];

const FINALS: [&str; 37] = [
    "a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "er", "i", "ia", "ie", "iao", "iu", "ian", "in",
    "iang", "ing", "iong", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang", "ueng", "ue", "ü", "üe", "üan", "ün",
];

/// Toneless base letter and tone (1–4) of a marked vowel.
fn mark(c: char) -> Option<(char, u8)> {
    Some(match c {
        'ā' => ('a', 1), 'á' => ('a', 2), 'ǎ' => ('a', 3), 'à' => ('a', 4),
        'ē' => ('e', 1), 'é' => ('e', 2), 'ě' => ('e', 3), 'è' => ('e', 4),
        'ī' => ('i', 1), 'í' => ('i', 2), 'ǐ' => ('i', 3), 'ì' => ('i', 4),
        'ō' => ('o', 1), 'ó' => ('o', 2), 'ǒ' => ('o', 3), 'ò' => ('o', 4),
        'ū' => ('u', 1), 'ú' => ('u', 2), 'ǔ' => ('u', 3), 'ù' => ('u', 4),
        'ǖ' => ('ü', 1), 'ǘ' => ('ü', 2), 'ǚ' => ('ü', 3), 'ǜ' => ('ü', 4),
        _ => return None,
    })
}

fn base(c: char) -> char {
    let lower = c.to_lowercase().next().unwrap_or(c);
    mark(lower).map(|m| m.0).unwrap_or(lower)
}

fn is_final(s: &[char]) -> bool {
    let s: String = s.iter().collect();
    FINALS.contains(&s.as_str())
}

/// Tone 1–4, or 5 for the neutral tone.
#[uniffi::export]
pub fn pinyin_tone(syllable: String) -> u8 {
    syllable.to_lowercase().chars().find_map(|c| mark(c).map(|m| m.1)).unwrap_or(5)
}

/// Splits one pinyin word ("Zhōngguó") into syllables, or None if it can't.
#[uniffi::export]
pub fn pinyin_syllables(word: String) -> Option<Vec<String>> {
    let chars: Vec<char> = word.chars().collect();
    let b: Vec<char> = chars.iter().map(|&c| base(c)).collect();
    let n = chars.len();
    let mut i = 0;
    let mut out: Vec<String> = Vec::new();
    while i < n {
        let init_len = INITIALS
            .iter()
            .find(|ini| {
                let ic: Vec<char> = ini.chars().collect();
                i + ic.len() <= n && b[i..i + ic.len()] == ic[..]
            })
            .map(|ini| ini.chars().count())
            .unwrap_or(0);
        // erhua: the final "r" in "nǎr" belongs to 儿
        if b[i] == 'r' && i == n - 1 && !out.is_empty() {
            out.push(chars[i].to_string());
            break;
        }
        let start = i + init_len;
        let mut len = 0;
        if start < n {
            for l in (1..=4.min(n - start)).rev() {
                let f = &b[start..start + l];
                // "er" only stands alone (儿, 二); after an initial it's erhua ("zhèr")
                let erhua = f == ['e', 'r'] && init_len > 0;
                if is_final(f) && !erhua {
                    len = l;
                    break;
                }
            }
        }
        if len == 0 {
            return None;
        }
        // "dàngāo" is dàn‑gāo, not dàng‑āo: a trailing n/g goes to the next syllable if that starts with a vowel
        let end = start + len;
        if end < n && len > 1 && "aeo".contains(b[end]) && "ng".contains(b[end - 1]) && is_final(&b[start..end - 1]) {
            len -= 1;
        }
        out.push(chars[i..start + len].iter().collect());
        i = start + len;
    }
    Some(out)
}

/// All syllables of a phrase or sentence ("Nǐ hǎo, wǒ jiào Xiǎomíng.").
#[uniffi::export]
pub fn pinyin_all_syllables(text: String) -> Option<Vec<String>> {
    let mut result = Vec::new();
    for token in text.split(|c: char| !c.is_alphabetic()).filter(|t| !t.is_empty()) {
        result.extend(pinyin_syllables(token.to_string())?);
    }
    Some(result)
}

pub fn is_hanzi_char(c: char) -> bool {
    matches!(c as u32, 0x4E00..=0x9FFF | 0x3400..=0x4DBF)
}

#[uniffi::export]
pub fn is_hanzi(text: String) -> bool {
    text.chars().next().map(is_hanzi_char).unwrap_or(false)
}

/// One character with the syllable that sits above it (None for punctuation).
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RubyUnit {
    pub character: String,
    pub syllable: Option<String>,
    pub tone: u8,
}

/// Pairs each character with its syllable, or None if they don't line up (then show a pinyin line instead).
#[uniffi::export]
pub fn ruby_units(hanzi: String, pinyin: String) -> Option<Vec<RubyUnit>> {
    let syl = pinyin_all_syllables(pinyin)?;
    let chars: Vec<char> = hanzi.chars().collect();
    if chars.iter().filter(|c| is_hanzi_char(**c)).count() != syl.len() {
        return None;
    }
    let mut k = 0;
    Some(
        chars
            .into_iter()
            .map(|c| {
                if is_hanzi_char(c) {
                    let s = syl[k].clone();
                    k += 1;
                    RubyUnit { character: c.to_string(), tone: pinyin_tone(s.clone()), syllable: Some(s) }
                } else {
                    RubyUnit { character: c.to_string(), syllable: None, tone: 0 }
                }
            })
            .collect(),
    )
}

/// Lowercase letters only, tone marks removed ("Nǐ hǎo!" → "nihao").
#[uniffi::export]
pub fn toneless(text: String) -> String {
    text.chars()
        .map(base)
        .map(|c| if c == 'ü' { 'u' } else { c })
        .filter(|c| c.is_alphabetic() && c.is_ascii())
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

fn edit_distance(a: &str, b: &str) -> usize {
    let b: Vec<char> = b.chars().collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.chars().enumerate() {
        let mut cur = vec![i + 1];
        for (j, cb) in b.iter().enumerate() {
            cur.push((prev[j] + usize::from(ca != *cb)).min(prev[j + 1] + 1).min(cur[j] + 1));
        }
        prev = cur;
    }
    prev[b.len()]
}

/// Did the learner say the word? `heard_hanzi` is the recognizer's text, `heard_latin` the same text
/// transliterated to pinyin by the platform. Exact characters win; otherwise matching syllables
/// (tones ignored) count, so homophones the recognizer picked are accepted.
#[uniffi::export]
pub fn speech_matches(heard_hanzi: String, heard_latin: String, target_hanzi: String, target_pinyin: String) -> bool {
    let hanzi: String = heard_hanzi.chars().filter(|c| is_hanzi_char(*c)).collect();
    if !target_hanzi.is_empty() && hanzi.contains(&target_hanzi) {
        return true;
    }
    let want = toneless(target_pinyin);
    if want.is_empty() {
        return false;
    }
    let got = toneless(heard_latin);
    if got.contains(&want) {
        return true;
    }
    // Longer words: one sound off still counts (zh/z, ing/in… learners and recognizers both slip).
    let n = want.chars().count();
    if n >= 5 {
        let g: Vec<char> = got.chars().collect();
        for len in n.saturating_sub(1)..=n + 1 {
            for start in 0..=g.len().saturating_sub(len) {
                if start + len <= g.len() && edit_distance(&g[start..start + len].iter().collect::<String>(), &want) <= 1 {
                    return true;
                }
            }
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::words::*;

    fn s(v: &[&str]) -> Option<Vec<String>> {
        Some(v.iter().map(|x| x.to_string()).collect())
    }

    #[test]
    fn splits_tricky_words() {
        assert_eq!(pinyin_syllables("dàngāo".into()), s(&["dàn", "gāo"]));
        assert_eq!(pinyin_syllables("rènao".into()), s(&["rè", "nao"]));
        assert_eq!(pinyin_syllables("Zhōngguó".into()), s(&["Zhōng", "guó"]));
        assert_eq!(pinyin_syllables("zhèr".into()), s(&["zhè", "r"]));
        assert_eq!(pinyin_syllables("ér".into()), s(&["ér"]));
        assert_eq!(pinyin_tone("mǎ".into()), 3);
        assert_eq!(pinyin_tone("ma".into()), 5);
    }

    #[test]
    fn every_word_and_example_lines_up() {
        for w in visible_words(true) {
            assert!(ruby_units(w.hanzi.clone(), w.pinyin.clone()).is_some(), "word {} {}", w.hanzi, w.pinyin);
            assert!(ruby_units(w.example.clone(), w.example_pinyin.clone()).is_some(), "example {} {}", w.example, w.example_pinyin);
        }
    }

    #[test]
    fn speech() {
        assert!(speech_matches("你好".into(), "nǐ hǎo".into(), "你好".into(), "nǐ hǎo".into()));
        assert!(speech_matches("拟好".into(), "nǐ hǎo".into(), "你好".into(), "nǐ hǎo".into()));
        assert!(!speech_matches("再见".into(), "zài jiàn".into(), "你好".into(), "nǐ hǎo".into()));
        assert!(speech_matches("".into(), "Nǐ Hǎo".into(), "你好".into(), "nǐ hǎo".into()), "case-insensitive");
        assert!(speech_matches("".into(), "xi huang".into(), "喜欢".into(), "xǐhuan".into()), "one sound off");
        assert!(!speech_matches("".into(), "ma".into(), "妈".into(), "bā".into()));
    }
}
