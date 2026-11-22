//! Downloadable content packs (words, sentences, stories) from the meitian-content site.
//! The apps download the JSON; the core parses it, merges it with the bundled words and serves it.

use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

use serde::Deserialize;

use crate::words::{bank, bank_mut, CoreWord};

/// Manifest schema this build understands. Newer manifests are ignored until the app updates.
pub const CONTENT_SCHEMA: u32 = 1;

#[derive(Debug, uniffi::Error)]
pub enum ContentError {
    Invalid { reason: String },
}

impl std::error::Error for ContentError {}

impl std::fmt::Display for ContentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ContentError::Invalid { reason } => write!(f, "invalid content: {reason}"),
        }
    }
}

fn invalid(e: impl std::fmt::Display) -> ContentError {
    ContentError::Invalid { reason: e.to_string() }
}

// ---------- manifest ----------

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PackInfo {
    pub id: String,
    /// "words", "sentences" or "stories".
    pub kind: String,
    /// HSK band (0 for packs that span levels).
    pub level: u8,
    pub url: String,
    pub bytes: u64,
    pub sha256: String,
    pub count: u32,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Manifest {
    pub schema: u32,
    pub version: String,
    pub credits: Vec<String>,
    pub packs: Vec<PackInfo>,
}

#[derive(Deserialize)]
struct RawManifest {
    schema: u32,
    version: String,
    #[serde(default)]
    credits: Vec<String>,
    packs: Vec<RawPack>,
}

#[derive(Deserialize)]
struct RawPack {
    id: String,
    kind: String,
    #[serde(default)]
    level: u8,
    url: String,
    #[serde(default)]
    bytes: u64,
    #[serde(default)]
    sha256: String,
    #[serde(default)]
    count: u32,
}

#[uniffi::export]
pub fn parse_manifest(json: String) -> Result<Manifest, ContentError> {
    let m: RawManifest = serde_json::from_str(&json).map_err(invalid)?;
    if m.schema > CONTENT_SCHEMA {
        return Err(invalid(format!("schema {} is newer than this app ({CONTENT_SCHEMA})", m.schema)));
    }
    Ok(Manifest {
        schema: m.schema,
        version: m.version,
        credits: m.credits,
        packs: m
            .packs
            .into_iter()
            .map(|p| PackInfo { id: p.id, kind: p.kind, level: p.level, url: p.url, bytes: p.bytes, sha256: p.sha256, count: p.count })
            .collect(),
    })
}

/// Packs worth downloading for a learner at `level`: every word list (stories use words of all bands, and each
/// must be known to be tagged, explained and counted as new), sentences for their band ±1, and the stories.
/// `all` = every pack.
#[uniffi::export]
pub fn packs_for_level(manifest: Manifest, level: u8, all: bool) -> Vec<PackInfo> {
    let lo = level.saturating_sub(1).max(1);
    let hi = (level + 1).max(2);
    manifest.packs.into_iter().filter(|p| all || p.level == 0 || p.kind == "words" || (lo..=hi).contains(&p.level)).collect()
}

// ---------- sentences ----------

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Token {
    pub text: String,
    /// Empty for punctuation.
    pub pinyin: String,
    /// The bank word these characters are, if any.
    pub word_id: Option<String>,
    /// A word the learner hasn't learned yet (filled in by the story and sentence functions that are given
    /// the learner's known words; false elsewhere).
    pub is_new: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Sentence {
    pub id: u64,
    pub zh: String,
    pub pinyin: String,
    pub en: String,
    pub tokens: Vec<Token>,
    /// Tatoeba contributor (credited in the app).
    pub author: String,
    pub level: u8,
}

impl Sentence {
    pub fn words(&self) -> impl Iterator<Item = &Token> {
        self.tokens.iter().filter(|t| !t.pinyin.is_empty())
    }
}

#[derive(Deserialize)]
struct RawSentence {
    id: u64,
    zh: String,
    py: String,
    en: String,
    t: Vec<(String, String)>,
    #[serde(default)]
    by: String,
}

#[derive(Deserialize)]
struct SentencePack {
    level: u8,
    sentences: Vec<RawSentence>,
}

#[derive(Deserialize)]
struct RawWord {
    h: String,
    p: String,
    m: Vec<String>,
    #[serde(default)]
    e: Option<(String, String, String)>,
}

#[derive(Deserialize)]
struct WordPack {
    level: u8,
    words: Vec<RawWord>,
}

#[derive(Default)]
pub(crate) struct SentenceStore {
    pub all: Vec<Sentence>,
    ids: HashMap<u64, usize>,
    /// characters → indices of sentences containing that word token
    by_hanzi: HashMap<String, Vec<usize>>,
}

impl SentenceStore {
    fn add(&mut self, s: Sentence) -> bool {
        if self.ids.contains_key(&s.id) {
            return false;
        }
        let i = self.all.len();
        for t in s.words() {
            self.by_hanzi.entry(t.text.clone()).or_default().push(i);
        }
        self.ids.insert(s.id, i);
        self.all.push(s);
        true
    }
}

pub(crate) fn sentences() -> &'static RwLock<SentenceStore> {
    static S: OnceLock<RwLock<SentenceStore>> = OnceLock::new();
    S.get_or_init(|| RwLock::new(SentenceStore::default()))
}

/// Fills in word ids for a sentence's tokens from the current bank.
pub(crate) fn resolved(mut s: Sentence) -> Sentence {
    let b = bank();
    for t in s.tokens.iter_mut() {
        if !t.pinyin.is_empty() {
            t.word_id = b.by_hanzi.get(&t.text).cloned();
        }
    }
    s
}

fn word_from_pack(level: u8, w: RawWord) -> CoreWord {
    let meaning = w.m.iter().map(|m| m.replace(';', ",")).collect::<Vec<_>>().join(", ");
    let (example, example_pinyin, example_meaning) = w.e.unwrap_or_default();
    CoreWord {
        id: format!("h{level}-{}", w.h),
        level,
        hanzi: w.h,
        pinyin: w.p,
        meaning,
        example,
        example_pinyin,
        example_meaning,
        intensity: 0,
    }
}

/// Loads one downloaded pack (`kind` = "words" | "sentences" | "stories"). Returns how many new items it added.
/// Loading the same pack twice is harmless.
#[uniffi::export]
pub fn content_load(kind: String, json: String) -> Result<u32, ContentError> {
    match kind.as_str() {
        "words" => {
            let pack: WordPack = serde_json::from_str(&json).map_err(invalid)?;
            let level = pack.level;
            if !(1..=9).contains(&level) {
                return Err(invalid(format!("bad level {level}")));
            }
            let words = pack.words.into_iter().filter(|w| !w.h.is_empty() && !w.m.is_empty()).map(|w| word_from_pack(level, w)).collect();
            Ok(bank_mut().add(words))
        }
        "sentences" => {
            let pack: SentencePack = serde_json::from_str(&json).map_err(invalid)?;
            let mut store = sentences().write().unwrap_or_else(|e| e.into_inner());
            let mut added = 0;
            for r in pack.sentences {
                let tokens = r.t.into_iter().map(|(text, pinyin)| Token { text, pinyin, word_id: None, is_new: false }).collect();
                let s = Sentence { id: r.id, zh: r.zh, pinyin: r.py, en: r.en, tokens, author: r.by, level: pack.level };
                if store.add(s) {
                    added += 1;
                }
            }
            Ok(added)
        }
        "stories" => crate::stories::load_stories(&json),
        other => Err(invalid(format!("unknown pack kind {other}"))),
    }
}

/// Forgets all downloaded content (back to the bundled words).
#[uniffi::export]
pub fn content_clear() {
    bank_mut().reset();
    *sentences().write().unwrap_or_else(|e| e.into_inner()) = SentenceStore::default();
    crate::stories::clear_stories();
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ContentStats {
    pub words: u32,
    pub bundled_words: u32,
    pub sentences: u32,
    pub stories: u32,
}

#[uniffi::export]
pub fn content_stats() -> ContentStats {
    let b = bank();
    ContentStats {
        words: b.regular.len() as u32,
        bundled_words: b.bundled as u32,
        sentences: sentences().read().map(|s| s.all.len()).unwrap_or(0) as u32,
        stories: crate::stories::story_count(),
    }
}

/// Up to `limit` example sentences that use the word, easiest (shortest, lowest level) first.
#[uniffi::export]
pub fn sentences_for_word(word_id: String, limit: u32) -> Vec<Sentence> {
    let Some(word) = bank().by_id.get(&word_id).cloned() else { return vec![] };
    let store = sentences().read().unwrap_or_else(|e| e.into_inner());
    let mut found: Vec<&Sentence> = store.by_hanzi.get(&word.hanzi).into_iter().flatten().map(|&i| &store.all[i]).collect();
    found.sort_by_key(|s| (s.level, s.zh.chars().count()));
    found.into_iter().take(limit as usize).cloned().map(resolved).collect()
}

/// Tap-a-word lookup: the bank word for a token's characters.
#[uniffi::export]
pub fn lookup_token(text: String) -> Option<CoreWord> {
    let b = bank();
    b.by_hanzi.get(&text).and_then(|id| b.by_id.get(id)).cloned()
}

#[cfg(test)]
pub(crate) const TEST_WORDS: &str = r#"{"kind":"words","level":2,"words":[
 {"h":"测试","p":"cèshì","m":["test; exam","to test"],"e":["这是测试。","Zhè shì cèshì.","This is a test."]},
 {"h":"你好","p":"nǐ hǎo","m":["hello"]}]}"#;

#[cfg(test)]
pub(crate) const TEST_SENTENCES: &str = r#"{"kind":"sentences","level":2,"sentences":[
 {"id":1,"zh":"这是测试。","py":"Zhè shì cèshì.","en":"This is a test.","t":[["这","zhè"],["是","shì"],["测试","cèshì"],["。",""]],"by":"a"},
 {"id":2,"zh":"我喜欢你。","py":"Wǒ xǐhuan nǐ.","en":"I like you.","t":[["我","wǒ"],["喜欢","xǐhuan"],["你","nǐ"],["。",""]],"by":"b"},
 {"id":3,"zh":"你好吗？","py":"Nǐ hǎo ma?","en":"How are you?","t":[["你好","nǐhǎo"],["吗","ma"],["？",""]],"by":"c"},
 {"id":4,"zh":"我很好。","py":"Wǒ hěn hǎo.","en":"I'm fine.","t":[["我","wǒ"],["很","hěn"],["好","hǎo"],["。",""]],"by":"d"},
 {"id":5,"zh":"他是老师。","py":"Tā shì lǎoshī.","en":"He is a teacher.","t":[["他","tā"],["是","shì"],["老师","lǎoshī"],["。",""]],"by":"e"}]}"#;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::words::*;

    #[test]
    fn manifest_parses_and_filters() {
        let m = parse_manifest(
            r#"{"schema":1,"version":"x","packs":[
            {"id":"words-1","kind":"words","level":1,"url":"words-1.json"},
            {"id":"words-4","kind":"words","level":4,"url":"words-4.json"},
            {"id":"sentences-4","kind":"sentences","level":4,"url":"sentences-4.json"},
            {"id":"stories","kind":"stories","level":0,"url":"stories.json"}]}"#
                .into(),
        )
        .unwrap();
        let ids: Vec<_> = packs_for_level(m.clone(), 1, false).into_iter().map(|p| p.id).collect();
        assert_eq!(ids, vec!["words-1", "words-4", "stories"], "every word list, near sentences only");
        assert_eq!(packs_for_level(m, 1, true).len(), 4);
        assert!(parse_manifest(r#"{"schema":99,"version":"x","packs":[]}"#.into()).is_err());
        assert!(parse_manifest("nope".into()).is_err());
    }

    #[test]
    fn packs_merge_into_the_bank() {
        // Other tests load the same pack concurrently, so only check the end state.
        assert!(content_load("words".into(), TEST_WORDS.into()).unwrap() <= 1, "你好 is bundled already");
        assert_eq!(content_load("words".into(), TEST_WORDS.into()).unwrap(), 0, "idempotent");
        assert_eq!(all_words().len(), bundled_words().len() + 1);
        assert_eq!(all_words().iter().filter(|w| w.hanzi == "你好").count(), 1);
        let w = word_by_id("h2-测试".into()).unwrap();
        assert_eq!(w.short_meaning(), "test");
        assert_eq!(w.example, "这是测试。");
        assert!(content_load("words".into(), "{}".into()).is_err());

        content_load("sentences".into(), TEST_SENTENCES.into()).unwrap();
        let s = sentences_for_word("h2-测试".into(), 3);
        assert_eq!(s[0].id, 1);
        assert_eq!(s[0].tokens[2].word_id.as_deref(), Some("h2-测试"));
        assert_eq!(lookup_token("测试".into()).unwrap().id, "h2-测试");
    }
}

/// Parses the real packs from a local meitian-content build:
/// `MEITIAN_CONTENT_DIST=../../meitian-content/dist cargo test --release real_packs -- --ignored`
#[cfg(test)]
mod real_packs {
    use super::*;

    #[test]
    #[ignore]
    fn real_packs() {
        let dir = std::path::PathBuf::from(std::env::var("MEITIAN_CONTENT_DIST").expect("set MEITIAN_CONTENT_DIST"));
        let m = parse_manifest(std::fs::read_to_string(dir.join("manifest.json")).unwrap()).unwrap();
        for p in &m.packs {
            let n = content_load(p.kind.clone(), std::fs::read_to_string(dir.join(&p.url)).unwrap()).unwrap();
            println!("{} +{n}", p.id);
        }
        let stats = content_stats();
        println!("{stats:?}");
        assert!(stats.words > 4000 && stats.sentences > 5000);
        let lesson = crate::exercises::sentence_lesson(3, vec![], 10, 7, true);
        for ex in lesson {
            println!("{:?} {} {:?} {:?} -> {}", ex.kind, ex.sentence.zh, ex.tiles, ex.options, ex.answer);
        }
        let w = crate::words::word_id_for_hanzi("喜欢".into()).unwrap();
        for s in sentences_for_word(w, 3) {
            println!("{} {}", s.zh, s.en);
        }
        // a beginner two units in: only learned words in sentence nodes, and what the shelf looks like
        let level1: Vec<String> = crate::words::all_words().into_iter().filter(|w| w.level == 1).map(|w| w.id).collect();
        for n in [15, 25, 50, 100, 200, 478] {
            let known: Vec<String> = level1.iter().take(n).cloned().collect();
            let t = std::time::Instant::now();
            let lesson = crate::exercises::sentence_node_lesson(1, 5, "2026-11-22".into(), known.clone(), known.clone(), true);
            let (lesson_ms, t) = (t.elapsed().as_millis(), std::time::Instant::now());
            let shelf = crate::stories::story_availability(false, "2026-11-22".into(), known.clone());
            println!("{n} words: {:?} | {shelf:?} | {lesson_ms} ms, {} ms", lesson.iter().map(|e| e.sentence.zh.as_str()).collect::<Vec<_>>(), t.elapsed().as_millis());
            assert_eq!(lesson.len(), crate::exercises::SENTENCE_NODE_COUNT);
            let set: std::collections::HashSet<&String> = known.iter().collect();
            for t in lesson.iter().flat_map(|e| &e.sentence.tokens).filter(|t| crate::vocab::is_vocab(t)) {
                assert!(t.word_id.as_ref().is_some_and(|id| set.contains(id)), "{} isn't learned", t.text);
            }
        }
    }
}
