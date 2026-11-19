//! Graded illustrated stories (Duolingo-style), downloaded as the "stories" content pack.

use std::sync::{OnceLock, RwLock};

use serde::Deserialize;

use crate::challenge::day_seed;
use crate::content::{ContentError, Token};
use crate::words::bank;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryImage {
    pub url: String,
    pub artist: String,
    /// Where the picture comes from (credited and linked in the app).
    pub source: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryLine {
    /// Who says it; empty for narration.
    pub speaker: String,
    pub zh: String,
    pub pinyin: String,
    pub en: String,
    pub tokens: Vec<Token>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryQuestion {
    pub prompt: String,
    pub options: Vec<String>,
    pub answer: u32,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryPanel {
    pub image: Option<StoryImage>,
    pub lines: Vec<StoryLine>,
    pub question: Option<StoryQuestion>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Story {
    pub id: String,
    pub title: String,
    pub title_en: String,
    pub level: u8,
    pub emoji: String,
    pub cover: Option<StoryImage>,
    pub panels: Vec<StoryPanel>,
}

#[derive(Deserialize)]
struct RawImage {
    url: String,
    #[serde(default)]
    artist: String,
    #[serde(default)]
    source: String,
}

#[derive(Deserialize)]
struct RawLine {
    #[serde(default)]
    who: String,
    zh: String,
    #[serde(default)]
    py: String,
    #[serde(default)]
    en: String,
    #[serde(default)]
    t: Vec<(String, String)>,
}

#[derive(Deserialize)]
struct RawQuestion {
    q: String,
    options: Vec<String>,
    answer: u32,
}

#[derive(Deserialize)]
struct RawPanel {
    #[serde(default)]
    image: Option<RawImage>,
    #[serde(default)]
    lines: Vec<RawLine>,
    #[serde(default)]
    question: Option<RawQuestion>,
}

#[derive(Deserialize)]
struct RawStory {
    id: String,
    title: String,
    #[serde(default)]
    title_en: String,
    level: u8,
    #[serde(default)]
    emoji: String,
    #[serde(default)]
    cover: Option<RawImage>,
    panels: Vec<RawPanel>,
}

#[derive(Deserialize)]
struct StoryPack {
    stories: Vec<RawStory>,
}

fn image(r: RawImage) -> StoryImage {
    StoryImage { url: r.url, artist: r.artist, source: r.source }
}

fn store() -> &'static RwLock<Vec<Story>> {
    static S: OnceLock<RwLock<Vec<Story>>> = OnceLock::new();
    S.get_or_init(|| RwLock::new(Vec::new()))
}

pub(crate) fn load_stories(json: &str) -> Result<u32, ContentError> {
    let pack: StoryPack = serde_json::from_str(json).map_err(|e| ContentError::Invalid { reason: e.to_string() })?;
    let mut stories: Vec<Story> = pack
        .stories
        .into_iter()
        .filter(|s| !s.panels.is_empty())
        .map(|s| Story {
            id: s.id,
            title: s.title,
            title_en: s.title_en,
            level: s.level,
            emoji: if s.emoji.is_empty() { "📖".into() } else { s.emoji },
            cover: s.cover.map(image),
            panels: s
                .panels
                .into_iter()
                .map(|p| StoryPanel {
                    image: p.image.map(image),
                    lines: p
                        .lines
                        .into_iter()
                        .map(|l| {
                            let tokens = if l.t.is_empty() {
                                // No tokenization in the pack: one tappable chunk per line.
                                vec![Token { text: l.zh.clone(), pinyin: l.py.clone(), word_id: None }]
                            } else {
                                l.t.into_iter().map(|(text, pinyin)| Token { text, pinyin, word_id: None }).collect()
                            };
                            StoryLine { speaker: l.who, zh: l.zh, pinyin: l.py, en: l.en, tokens }
                        })
                        .collect(),
                    question: p
                        .question
                        .filter(|q| (q.answer as usize) < q.options.len())
                        .map(|q| StoryQuestion { prompt: q.q, options: q.options, answer: q.answer }),
                })
                .collect(),
        })
        .collect();
    stories.sort_by(|a, b| (a.level, &a.id).cmp(&(b.level, &b.id)));
    let n = stories.len() as u32;
    *store().write().unwrap_or_else(|e| e.into_inner()) = stories;
    Ok(n)
}

pub(crate) fn clear_stories() {
    store().write().unwrap_or_else(|e| e.into_inner()).clear();
}

pub(crate) fn story_count() -> u32 {
    store().read().map(|s| s.len()).unwrap_or(0) as u32
}

fn resolve(mut s: Story) -> Story {
    let b = bank();
    for line in s.panels.iter_mut().flat_map(|p| p.lines.iter_mut()) {
        for t in line.tokens.iter_mut() {
            if !t.pinyin.is_empty() {
                t.word_id = b.by_hanzi.get(&t.text).cloned();
            }
        }
    }
    s
}

/// All stories, easiest first (tokens resolved to word ids for tap-to-lookup).
#[uniffi::export]
pub fn all_stories() -> Vec<Story> {
    store().read().map(|s| s.clone()).unwrap_or_default().into_iter().map(resolve).collect()
}

#[uniffi::export]
pub fn story_by_id(id: String) -> Option<Story> {
    store().read().ok()?.iter().find(|s| s.id == id).cloned().map(resolve)
}

/// The day's featured story at or below the learner's level (same on every launch that day).
#[uniffi::export]
pub fn story_of_the_day(day_key: String, max_level: u8) -> Option<Story> {
    let all = store().read().ok()?.clone();
    let fits: Vec<Story> = all.iter().filter(|s| s.level <= max_level.max(1)).cloned().collect();
    let pool = if fits.is_empty() { all } else { fits };
    if pool.is_empty() {
        return None;
    }
    let i = day_seed(day_key) as usize % pool.len();
    Some(resolve(pool[i].clone()))
}

/// Word ids a story teaches (for adding to review after reading).
#[uniffi::export]
pub fn story_word_ids(story: Story) -> Vec<String> {
    let mut ids: Vec<String> = story
        .panels
        .iter()
        .flat_map(|p| p.lines.iter())
        .flat_map(|l| l.tokens.iter())
        .filter_map(|t| t.word_id.clone())
        .collect();
    ids.sort();
    ids.dedup();
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stories_parse() {
        let json = r#"{"kind":"stories","stories":[{"id":"tea","title":"喝茶","title_en":"Tea","level":1,
          "panels":[{"image":{"url":"https://x/1.jpg","artist":"a","source":"https://s"},
            "lines":[{"who":"小明","zh":"你好！","py":"Nǐ hǎo!","en":"Hi!","t":[["你好","nǐhǎo"],["！",""]]}],
            "question":{"q":"?","options":["a","b"],"answer":1}},
           {"lines":[{"zh":"再见。"}],"question":{"q":"bad","options":["a"],"answer":5}}]}]}"#;
        assert_eq!(load_stories(json).unwrap(), 1);
        let s = story_by_id("tea".into()).unwrap();
        assert_eq!(s.panels[0].lines[0].tokens[0].word_id.as_deref(), Some("1-你好"));
        assert!(s.panels[1].question.is_none(), "out-of-range answers are dropped");
        assert_eq!(story_of_the_day("2026-11-19".into(), 1).unwrap().id, "tea");
        assert_eq!(story_word_ids(s), vec!["1-你好".to_string()]);
    }
}
