//! Daily friend challenges and the phrase of the day. Picked from the date, so the same day gives the
//! same challenge on every launch (and on both platforms).

use crate::words::CoreWord;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Friend {
    Chinese,
    NonChinese,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct CoreChallenge {
    pub word: CoreWord,
    pub title: String,
    pub mission: String,
    pub steps: Vec<String>,
    pub bonus: String,
}

/// Stable number for a day key like "2026-11-19".
#[uniffi::export]
pub fn day_seed(day_key: String) -> u32 {
    let v = day_key.chars().fold(7i64, |acc, c| (acc.wrapping_mul(31).wrapping_add(c as i64)) & 0x7fff_ffff);
    v as u32
}

#[uniffi::export]
pub fn daily_challenge(day_key: String, words: Vec<CoreWord>, friend: Friend) -> Option<CoreChallenge> {
    // Challenges are built around the word's example sentence, so prefer words that have one.
    let with_example: Vec<CoreWord> = words.iter().filter(|w| !w.example.is_empty()).cloned().collect();
    let words = if with_example.is_empty() { words } else { with_example };
    if words.is_empty() {
        return None;
    }
    let s = day_seed(day_key) as usize;
    let word = words[s % words.len()].clone();
    let w = format!("{} ({})", word.hanzi, word.pinyin);
    let (h, p) = (&word.hanzi, &word.pinyin);
    let options: Vec<(String, String, Vec<String>, String)> = match friend {
        Friend::Chinese => vec![
            (
                "Ask, don't tell".into(),
                format!("Ask your Chinese friend a question that uses {w}."),
                vec![
                    "Say the example sentence out loud three times.".into(),
                    "Turn it into a question: add 吗 (ma) or use 什么 (shénme, what) / 为什么 (wèishénme, why).".into(),
                    "Ask your friend and listen to the full answer.".into(),
                ],
                "Bonus: ask them to correct your tones.".into(),
            ),
            (
                "Sneak it in".into(),
                format!("Slip {w} into a normal conversation with a Chinese speaker without announcing it."),
                vec![
                    "Practice the example sentence until it feels natural.".into(),
                    "Wait for the right moment in your chat.".into(),
                    "Use it! Did they react or reply naturally?".into(),
                ],
                "Bonus: get them to use the word back to you.".into(),
            ),
            (
                "Native remix".into(),
                format!("Ask a Chinese friend to make their own sentence with {w}, then repeat it back."),
                vec![
                    format!("Say: “你能用「{h}」造个句子吗？” (Nǐ néng yòng “{p}” zào ge jùzi ma? Can you make a sentence with it?)"),
                    "Listen, then repeat their sentence exactly.".into(),
                    "Ask what it means if you're unsure: “这是什么意思？” (Zhè shì shénme yìsi? What does it mean?)".into(),
                ],
                "Bonus: write their sentence down in the notes.".into(),
            ),
            (
                "Voice message".into(),
                format!("Send a Chinese friend a voice message that uses {w}."),
                vec![
                    "Listen to the pronunciation in the app (tap the speaker).".into(),
                    "Record a short voice message using the word.".into(),
                    "Ask them to reply in Chinese.".into(),
                ],
                "Bonus: understand their reply without a translator.".into(),
            ),
        ],
        Friend::NonChinese => vec![
            (
                "Be the teacher".into(),
                format!("Teach a friend who doesn't speak Chinese how to say {w}."),
                vec![
                    "Say the word slowly and show the tone with your hand.".into(),
                    "Have them repeat it until they get it.".into(),
                    "Tell them what it means and use it in the example sentence.".into(),
                ],
                "Bonus: they still remember it tomorrow.".into(),
            ),
            (
                "Charades".into(),
                format!("Say {w} to a friend and act it out until they guess the meaning."),
                vec![
                    "Say the word out loud, no English allowed.".into(),
                    "Mime, point, draw, whatever it takes.".into(),
                    "Reveal the meaning and say the full example sentence.".into(),
                ],
                "Bonus: they guess in under 30 seconds.".into(),
            ),
            (
                "Secret code".into(),
                format!("Agree with a friend to use {w} as your secret word for today."),
                vec![
                    "Teach them the word and its meaning.".into(),
                    "Use it at least twice during the day instead of the English word.".into(),
                    "Say the example sentence to them once.".into(),
                ],
                "Bonus: they use it on you first.".into(),
            ),
            (
                "Language swap".into(),
                format!("Use {w} in a sentence with a friend, then learn a word from their language in return."),
                vec![
                    "Say the example sentence and translate it.".into(),
                    "Ask them for the same word in their language.".into(),
                    "Note down their word in the notes field.".into(),
                ],
                "Bonus: make a mixed-language sentence together.".into(),
            ),
        ],
    };
    let (title, mission, steps, bonus) = options[(s / 7) % options.len()].clone();
    Some(CoreChallenge { word, title, mission, steps, bonus })
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Phrase {
    pub hanzi: String,
    pub pinyin: String,
    pub meaning: String,
}

#[uniffi::export]
pub fn phrase_of_the_day(day_key: String) -> Phrase {
    const PHRASES: [(&str, &str, &str); 10] = [
        ("慢慢来", "màn man lái", "Take your time."),
        ("没关系", "méi guānxi", "It doesn't matter / no worries."),
        ("加油", "jiāyóu", "You can do it!"),
        ("一路平安", "yí lù píng'ān", "Have a safe trip."),
        ("好久不见", "hǎo jiǔ bú jiàn", "Long time no see."),
        ("马马虎虎", "mǎma hūhū", "So-so (literally: horse horse tiger tiger)."),
        ("吃了吗？", "chī le ma?", "Have you eaten? (a friendly hello)"),
        ("小菜一碟", "xiǎo cài yì dié", "Piece of cake (a small dish)."),
        ("入乡随俗", "rù xiāng suí sú", "When in Rome, do as the Romans do."),
        ("一言为定", "yì yán wéi dìng", "It's a deal!"),
    ];
    let (h, p, m) = PHRASES[day_seed(day_key) as usize % PHRASES.len()];
    Phrase { hanzi: h.into(), pinyin: p.into(), meaning: m.into() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::words::all_words;

    #[test]
    fn stable_per_day() {
        let words: Vec<_> = all_words().into_iter().take(5).collect();
        let a = daily_challenge("2026-11-19".into(), words.clone(), Friend::Chinese).unwrap();
        let b = daily_challenge("2026-11-19".into(), words.clone(), Friend::Chinese).unwrap();
        assert_eq!(a, b);
        assert_eq!(a.steps.len(), 3);
        assert!(daily_challenge("x".into(), vec![], Friend::NonChinese).is_none());
        // matches the original Swift seed so existing users keep the same challenge
        assert_eq!(day_seed("a".into()), 7 * 31 + 97);
    }

    #[test]
    fn phrases_line_up() {
        for d in 1..=31 {
            let p = phrase_of_the_day(format!("2026-12-{d:02}"));
            assert!(crate::pinyin::ruby_units(p.hanzi.clone(), p.pinyin.clone()).is_some(), "{}", p.hanzi);
        }
    }
}
