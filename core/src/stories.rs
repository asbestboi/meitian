//! Graded illustrated stories (Duolingo-style), downloaded as the "stories" content pack.

use crate::wechat::render_wechat;
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
    /// A picture sent with the message (chat stories).
    pub image: Option<StoryImage>,
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

/// Chat stories: a message the learner can choose to send.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ReplyOption {
    pub zh: String,
    pub pinyin: String,
    pub en: String,
    pub tokens: Vec<Token>,
    /// Does this reply fit the conversation?
    pub correct: bool,
    /// What the other person answers to it.
    pub reaction: Option<StoryLine>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryPanel {
    pub image: Option<StoryImage>,
    pub lines: Vec<StoryLine>,
    pub question: Option<StoryQuestion>,
    /// Chat stories: after the lines, pick what to send (empty = no choice).
    pub reply: Vec<ReplyOption>,
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
    /// "YYYY-MM-DD" for a daily story (shown on Today that day, on the shelf from then on); empty otherwise.
    pub date: String,
    /// "chat" for an SMS thread, empty for a picture story.
    pub style: String,
    /// Chat stories: whose messages are "mine" (right-hand bubbles).
    pub me: String,
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
    #[serde(default)]
    image: Option<RawImage>,
}

#[derive(Deserialize)]
struct RawQuestion {
    q: String,
    options: Vec<String>,
    answer: u32,
}

#[derive(Deserialize)]
struct RawOption {
    zh: String,
    #[serde(default)]
    py: String,
    #[serde(default)]
    en: String,
    #[serde(default)]
    t: Vec<(String, String)>,
    #[serde(default)]
    ok: bool,
    #[serde(default)]
    then: Option<RawLine>,
}

#[derive(Deserialize)]
struct RawReply {
    #[serde(default)]
    options: Vec<RawOption>,
}

#[derive(Deserialize)]
struct RawPanel {
    #[serde(default)]
    reply: Option<RawReply>,
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
    #[serde(default)]
    date: String,
    #[serde(default)]
    style: String,
    #[serde(default)]
    me: String,
}

#[derive(Deserialize)]
struct StoryPack {
    stories: Vec<RawStory>,
}

fn image(r: RawImage) -> StoryImage {
    StoryImage {
        url: r.url,
        artist: r.artist,
        source: r.source,
    }
}

fn tokens(t: Vec<(String, String)>, zh: &str, py: &str) -> Vec<Token> {
    if t.is_empty() {
        // No tokenization in the pack: one tappable chunk.
        vec![Token {
            text: zh.to_string(),
            pinyin: py.to_string(),
            word_id: None,
        }]
    } else {
        t.into_iter()
            .map(|(text, pinyin)| Token {
                // WeChat emoji codes ("[捂脸]") become the emoji itself
                text: render_wechat(&text),
                pinyin,
                word_id: None,
            })
            .collect()
    }
}

fn line(l: RawLine) -> StoryLine {
    StoryLine {
        speaker: l.who,
        image: l.image.map(image),
        tokens: tokens(l.t, &render_wechat(&l.zh), &render_wechat(&l.py)),
        zh: render_wechat(&l.zh),
        pinyin: render_wechat(&l.py),
        en: render_wechat(&l.en),
    }
}

/// Packs list the fitting reply first; mix the order so the answer isn't always in the same place.
/// Seeded by story id + panel, so the order is the same on every launch and on both platforms.
fn shuffle_replies(
    mut options: Vec<ReplyOption>,
    story_id: &str,
    panel: usize,
) -> Vec<ReplyOption> {
    if options.len() < 2 {
        return options;
    }
    let seed = story_id.bytes().fold(0xcbf2_9ce4_8422_2325u64, |h, b| {
        (h ^ b as u64).wrapping_mul(0x100_0000_01b3)
    });
    let mut rng =
        fastrand::Rng::with_seed(seed ^ (panel as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15));
    rng.shuffle(&mut options);
    options
}

fn store() -> &'static RwLock<Vec<Story>> {
    static S: OnceLock<RwLock<Vec<Story>>> = OnceLock::new();
    S.get_or_init(|| RwLock::new(Vec::new()))
}

pub(crate) fn load_stories(json: &str) -> Result<u32, ContentError> {
    let pack: StoryPack = serde_json::from_str(json).map_err(|e| ContentError::Invalid {
        reason: e.to_string(),
    })?;
    let mut stories: Vec<Story> = pack
        .stories
        .into_iter()
        .filter(|s| !s.panels.is_empty())
        .map(|s| {
            let story_id = s.id.clone();
            Story {
                id: s.id,
                title: s.title,
                title_en: s.title_en,
                level: s.level,
                emoji: if s.emoji.is_empty() {
                    "📖".into()
                } else {
                    s.emoji
                },
                cover: s.cover.map(image),
                date: s.date,
                style: s.style,
                me: s.me,
                panels: s
                    .panels
                    .into_iter()
                    .enumerate()
                    .map(|(pi, p)| StoryPanel {
                        image: p.image.map(image),
                        lines: p.lines.into_iter().map(line).collect(),
                        reply: shuffle_replies(
                            p.reply
                                .map(|r| r.options)
                                .unwrap_or_default()
                                .into_iter()
                                .map(|o| ReplyOption {
                                    tokens: tokens(o.t, &render_wechat(&o.zh), &render_wechat(&o.py)),
                                    zh: render_wechat(&o.zh),
                                    pinyin: render_wechat(&o.py),
                                    en: render_wechat(&o.en),
                                    correct: o.ok,
                                    reaction: o.then.map(line),
                                })
                                .collect(),
                            &story_id,
                            pi,
                        ),
                        question: p
                            .question
                            .filter(|q| (q.answer as usize) < q.options.len())
                            .map(|q| StoryQuestion {
                                prompt: q.q,
                                options: q.options,
                                answer: q.answer,
                            }),
                    })
                    .collect(),
            }
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
    let fill = |tokens: &mut Vec<Token>| {
        for t in tokens.iter_mut() {
            if !t.pinyin.is_empty() {
                t.word_id = b.by_hanzi.get(&t.text).cloned();
            }
        }
    };
    for p in s.panels.iter_mut() {
        for l in p.lines.iter_mut() {
            fill(&mut l.tokens);
        }
        for o in p.reply.iter_mut() {
            fill(&mut o.tokens);
            if let Some(r) = o.reaction.as_mut() {
                fill(&mut r.tokens);
            }
        }
    }
    s
}

/// All stories, easiest first (tokens resolved to word ids for tap-to-lookup).
#[uniffi::export]
pub fn all_stories() -> Vec<Story> {
    store()
        .read()
        .map(|s| s.clone())
        .unwrap_or_default()
        .into_iter()
        .map(resolve)
        .collect()
}

#[uniffi::export]
pub fn story_by_id(id: String) -> Option<Story> {
    store()
        .read()
        .ok()?
        .iter()
        .find(|s| s.id == id)
        .cloned()
        .map(resolve)
}

/// The learner's HSK level as a story cap (0 = beginner still reads HSK 1).
fn cap(max_level: u8) -> u8 {
    max_level.max(1)
}

/// Can a learner at `max_level` read this story? Stories are graded by HSK level, and a learner never
/// gets one above their own level (it'd be full of words they haven't met yet).
#[uniffi::export]
pub fn story_fits_level(story: Story, max_level: u8) -> bool {
    story.level <= cap(max_level)
}

/// The day's story: the daily story dated today if it's at or below the learner's level, otherwise a
/// pick at or below the learner's level from the undated stories (same on every launch that day).
/// `None` when nothing fits.
#[uniffi::export]
pub fn story_of_the_day(day_key: String, max_level: u8) -> Option<Story> {
    let all = store().read().ok()?.clone();
    let cap = cap(max_level);
    if let Some(s) = all.iter().find(|s| s.date == day_key && s.level <= cap) {
        return Some(resolve(s.clone()));
    }
    let pool: Vec<Story> = all
        .iter()
        .filter(|s| s.date.is_empty() && s.level <= cap)
        .cloned()
        .collect();
    if pool.is_empty() {
        return None;
    }
    let i = day_seed(day_key) as usize % pool.len();
    Some(resolve(pool[i].clone()))
}

/// Stories for the shelf: everything except daily stories whose day hasn't come yet.
#[uniffi::export]
pub fn shelf_stories(day_key: String) -> Vec<Story> {
    all_stories()
        .into_iter()
        .filter(|s| s.date.is_empty() || s.date <= day_key)
        .collect()
}

/// The next unread story (or chat) for a learner, picked at random so it's a surprise. Never repeats a
/// story in `read` and never goes above the learner's HSK level; stories at the learner's own level
/// come first, then easier ones. `None` when every story they can read has been read.
/// Daily stories whose day hasn't come yet are skipped.
#[uniffi::export]
pub fn next_story(
    chat: bool,
    day_key: String,
    max_level: u8,
    read: Vec<String>,
    seed: u64,
) -> Option<Story> {
    let cap = cap(max_level);
    let unread: Vec<Story> = shelf_stories(day_key)
        .into_iter()
        .filter(|s| (s.style == "chat") == chat && !read.contains(&s.id) && s.level <= cap)
        .collect();
    let top = unread.iter().map(|s| s.level).max()?;
    let pool: Vec<Story> = unread.into_iter().filter(|s| s.level == top).collect();
    let mut rng = fastrand::Rng::with_seed(seed);
    Some(pool[rng.usize(..pool.len())].clone())
}

/// How many stories (or chats) are available right now, read or not.
#[uniffi::export]
pub fn story_count_for(chat: bool, day_key: String) -> u32 {
    shelf_stories(day_key)
        .iter()
        .filter(|s| (s.style == "chat") == chat)
        .count() as u32
}

/// How many stories (or chats) a learner at `max_level` can read right now, and how many more are
/// waiting at higher levels.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryAvailability {
    pub at_level: u32,
    pub above_level: u32,
}

#[uniffi::export]
pub fn story_availability(chat: bool, day_key: String, max_level: u8) -> StoryAvailability {
    let cap = cap(max_level);
    let kind: Vec<Story> = shelf_stories(day_key)
        .into_iter()
        .filter(|s| (s.style == "chat") == chat)
        .collect();
    let at_level = kind.iter().filter(|s| s.level <= cap).count() as u32;
    StoryAvailability {
        at_level,
        above_level: kind.len() as u32 - at_level,
    }
}

/// Every picture a story uses (cover, panels, sent pictures), to preload when it opens.
#[uniffi::export]
pub fn story_image_urls(story: Story) -> Vec<String> {
    let mut urls: Vec<String> = story.cover.iter().map(|c| c.url.clone()).collect();
    for p in &story.panels {
        urls.extend(p.image.iter().map(|i| i.url.clone()));
        urls.extend(
            p.lines
                .iter()
                .filter_map(|l| l.image.as_ref().map(|i| i.url.clone())),
        );
    }
    urls.dedup();
    urls
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
pub(crate) static TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stories_parse() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let json = r#"{"kind":"stories","stories":[{"id":"tea","title":"喝茶","title_en":"Tea","level":1,
          "panels":[{"image":{"url":"https://x/1.jpg","artist":"a","source":"https://s"},
            "lines":[{"who":"小明","zh":"你好！","py":"Nǐ hǎo!","en":"Hi!","t":[["你好","nǐhǎo"],["！",""]]}],
            "question":{"q":"?","options":["a","b"],"answer":1}},
           {"lines":[{"zh":"再见。"}],"question":{"q":"bad","options":["a"],"answer":5}}]}]}"#;
        assert_eq!(load_stories(json).unwrap(), 1);
        let s = story_by_id("tea".into()).unwrap();
        assert_eq!(
            s.panels[0].lines[0].tokens[0].word_id.as_deref(),
            Some("1-你好")
        );
        assert!(
            s.panels[1].question.is_none(),
            "out-of-range answers are dropped"
        );
        assert_eq!(story_of_the_day("2026-11-19".into(), 1).unwrap().id, "tea");
        assert_eq!(story_word_ids(s.clone()), vec!["1-你好".to_string()]);
        assert_eq!(story_image_urls(s), vec!["https://x/1.jpg".to_string()]);
    }
}

#[cfg(test)]
mod daily_tests {
    use super::*;

    #[test]
    fn daily_and_chat_stories() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let json = r#"{"stories":[
          {"id":"a","title":"A","level":1,"panels":[{"lines":[{"zh":"你好"}]}]},
          {"id":"d1","title":"D1","level":3,"date":"2026-11-20","style":"chat","me":"我",
           "panels":[{"lines":[{"who":"丽丽","zh":"看！","image":{"url":"https://x/p.jpg"}}]}]},
          {"id":"d2","title":"D2","level":1,"date":"2026-11-21","panels":[{"lines":[{"zh":"好"}]}]}]}"#;
        // note: other tests replace the global store, so load + check in one go
        load_stories(json).unwrap();
        let today = story_of_the_day("2026-11-20".into(), 1).unwrap();
        assert_eq!(
            today.id, "a",
            "a daily story above the learner's level is skipped"
        );
        let today = story_of_the_day("2026-11-20".into(), 3).unwrap();
        assert_eq!(
            today.id, "d1",
            "the dated story wins at the learner's level"
        );
        assert_eq!(today.style, "chat");
        assert_eq!(
            today.panels[0].lines[0].image.as_ref().unwrap().url,
            "https://x/p.jpg"
        );
        assert_eq!(
            story_of_the_day("2026-12-01".into(), 1).unwrap().id,
            "a",
            "no daily: undated pick"
        );
        // next_story: chats only, never something already read, nothing from the future
        assert!(
            next_story(true, "2026-11-20".into(), 1, vec![], 1).is_none(),
            "the only chat is HSK 3"
        );
        assert!(
            next_story(true, "2026-11-20".into(), 2, vec![], 1).is_none(),
            "HSK 2 can't read HSK 3 either"
        );
        assert_eq!(
            next_story(true, "2026-11-20".into(), 3, vec![], 1)
                .unwrap()
                .id,
            "d1"
        );
        assert!(
            next_story(true, "2026-11-20".into(), 3, vec!["d1".into()], 1).is_none(),
            "all chats read"
        );
        assert_eq!(
            story_availability(true, "2026-11-20".into(), 1),
            StoryAvailability {
                at_level: 0,
                above_level: 1
            }
        );
        assert_eq!(
            next_story(false, "2026-11-20".into(), 1, vec![], 9)
                .unwrap()
                .id,
            "a",
            "d2 is still in the future"
        );
        assert_eq!(story_count_for(false, "2026-11-21".into()), 2);
        let shelf: Vec<String> = shelf_stories("2026-11-20".into())
            .into_iter()
            .map(|s| s.id)
            .collect();
        assert!(
            shelf.contains(&"d1".to_string()) && !shelf.contains(&"d2".to_string()),
            "future dailies hidden"
        );
        let json2 = r#"{"stories":[{"id":"r","title":"R","level":1,"style":"chat","me":"我","panels":[{"lines":[{"who":"丽丽","zh":"你好吗？"}],
          "reply":{"options":[{"zh":"我很好！","ok":true,"t":[["我","wǒ"],["很","hěn"],["好","hǎo"],["！",""]],"then":{"who":"丽丽","zh":"太好了！"}},
                              {"zh":"再见。","ok":false}]}}]}]}"#;
        load_stories(json2).unwrap();
        let r = story_by_id("r".into()).unwrap();
        let opts = &r.panels[0].reply;
        assert!(story_fits_level(r.clone(), 0) && story_fits_level(r.clone(), 1));
        assert_eq!(opts.len(), 2);
        assert_eq!(opts.iter().filter(|o| o.correct).count(), 1);
        let ok = opts.iter().find(|o| o.correct).unwrap();
        assert_eq!(ok.reaction.as_ref().unwrap().zh, "太好了！");
        assert_eq!(ok.tokens.len(), 4);
    }
}

#[cfg(test)]
mod level_tests {
    use super::*;

    #[test]
    fn never_above_the_learners_level() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let json = r#"{"stories":[
          {"id":"h1a","title":"1a","level":1,"panels":[{"lines":[{"zh":"好"}]}]},
          {"id":"h1b","title":"1b","level":1,"panels":[{"lines":[{"zh":"好"}]}]},
          {"id":"h2","title":"2","level":2,"panels":[{"lines":[{"zh":"好"}]}]},
          {"id":"h3","title":"3","level":3,"panels":[{"lines":[{"zh":"好"}]}]}]}"#;
        load_stories(json).unwrap();
        let day = "2026-11-19".to_string();
        for seed in 0..50 {
            let s = next_story(false, day.clone(), 1, vec![], seed).unwrap();
            assert_eq!(s.level, 1, "HSK 1 learners only get HSK 1 stories");
            // an HSK 2 learner gets the HSK 2 story first, then HSK 1 ones
            assert_eq!(
                next_story(false, day.clone(), 2, vec![], seed).unwrap().id,
                "h2"
            );
            assert_eq!(
                next_story(false, day.clone(), 2, vec!["h2".into()], seed)
                    .unwrap()
                    .level,
                1
            );
            assert!(
                story_of_the_day(format!("2026-11-{:02}", seed % 28 + 1), 1)
                    .unwrap()
                    .level
                    == 1
            );
        }
        assert!(
            next_story(false, day.clone(), 1, vec!["h1a".into(), "h1b".into()], 1).is_none(),
            "no fallback to HSK 2"
        );
        assert_eq!(
            next_story(false, day.clone(), 0, vec!["h1a".into()], 1)
                .unwrap()
                .id,
            "h1b",
            "beginners read HSK 1"
        );
        assert_eq!(
            story_availability(false, day, 2),
            StoryAvailability {
                at_level: 3,
                above_level: 1
            }
        );
    }
}

#[cfg(test)]
mod reply_tests {
    use super::*;

    #[test]
    fn right_reply_moves_around() {
        let opt = |zh: &str, ok| ReplyOption {
            zh: zh.into(),
            pinyin: String::new(),
            en: String::new(),
            tokens: vec![],
            correct: ok,
            reaction: None,
        };
        let mut positions = std::collections::HashSet::new();
        for i in 0..40 {
            let id = format!("chat-{i}");
            let opts = shuffle_replies(
                vec![opt("a", true), opt("b", false), opt("c", false)],
                &id,
                0,
            );
            let again = shuffle_replies(
                vec![opt("a", true), opt("b", false), opt("c", false)],
                &id,
                0,
            );
            assert_eq!(opts, again, "same story + panel, same order");
            positions.insert(opts.iter().position(|o| o.correct).unwrap());
        }
        assert_eq!(
            positions.len(),
            3,
            "the right answer shows up in every slot"
        );
    }
}
