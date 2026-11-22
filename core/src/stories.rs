//! Graded illustrated stories (Duolingo-style), downloaded as the "stories" content pack.

use crate::wechat::render_wechat;
use std::sync::{OnceLock, RwLock};

use serde::Deserialize;

use crate::challenge::day_seed;
use crate::content::{ContentError, Token};
use crate::vocab::{id_set, is_new, is_vocab, IdSet};
use crate::words::bank;

/// A story opens once it has at most this many words the learner hasn't learned.
pub const STORY_MAX_NEW_WORDS: usize = 3;

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
            is_new: false,
        }]
    } else {
        t.into_iter()
            .map(|(text, pinyin)| Token {
                // WeChat emoji codes ("[捂脸]") become the emoji itself
                text: render_wechat(&text),
                pinyin,
                word_id: None,
                is_new: false,
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

fn tokens_mut(s: &mut Story) -> impl Iterator<Item = &mut Token> {
    s.panels.iter_mut().flat_map(|p| {
        let lines = p.lines.iter_mut().flat_map(|l| l.tokens.iter_mut());
        let replies = p.reply.iter_mut().flat_map(|o| {
            o.tokens.iter_mut().chain(o.reaction.iter_mut().flat_map(|r| r.tokens.iter_mut()))
        });
        lines.chain(replies)
    })
}

/// Every token in reading order: lines, reply options and the reactions to them.
fn tokens_of(s: &Story) -> impl Iterator<Item = &Token> {
    s.panels.iter().flat_map(|p| {
        let lines = p.lines.iter().flat_map(|l| l.tokens.iter());
        let replies = p.reply.iter().flat_map(|o| {
            o.tokens.iter().chain(o.reaction.iter().flat_map(|r| r.tokens.iter()))
        });
        lines.chain(replies)
    })
}

/// Fills in word ids, and which words are new to a learner who knows `known` (None: marks nothing).
fn resolve(mut s: Story, known: Option<&IdSet>) -> Story {
    let b = bank();
    for t in tokens_mut(&mut s) {
        if !t.pinyin.is_empty() {
            t.word_id = b.by_hanzi.get(&t.text).cloned();
        }
        t.is_new = known.is_some_and(|k| is_new(t, k));
    }
    s
}

fn all_for(known: Option<&IdSet>) -> Vec<Story> {
    let all = store().read().map(|s| s.clone()).unwrap_or_default();
    all.into_iter().map(|s| resolve(s, known)).collect()
}

/// All stories, easiest first (tokens resolved to word ids for tap-to-lookup).
#[uniffi::export]
pub fn all_stories() -> Vec<Story> {
    all_for(None)
}

/// One story, with the words missing from `known_word_ids` marked as new.
#[uniffi::export]
pub fn story_by_id(id: String, known_word_ids: Vec<String>) -> Option<Story> {
    let s = store().read().ok()?.iter().find(|s| s.id == id).cloned()?;
    Some(resolve(s, Some(&id_set(known_word_ids))))
}

/// Unlearned words in the order they appear.
fn new_words(s: &Story, known: &IdSet) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    tokens_of(s)
        .filter(|t| is_new(t, known))
        .filter_map(|t| t.word_id.clone())
        .filter(|id| seen.insert(id.clone()))
        .collect()
}

fn missing(s: &Story, known: &IdSet) -> usize {
    new_words(s, known).len().saturating_sub(STORY_MAX_NEW_WORDS)
}

/// Can the learner read this story? At most `STORY_MAX_NEW_WORDS` of its words are unlearned, so it can be
/// followed from context.
#[uniffi::export]
pub fn story_unlocked(story: Story, known_word_ids: Vec<String>) -> bool {
    missing(&story, &id_set(known_word_ids)) == 0
}

/// The unlearned words in a story, in the order they appear.
#[uniffi::export]
pub fn story_new_words(story: Story, known_word_ids: Vec<String>) -> Vec<String> {
    new_words(&story, &id_set(known_word_ids))
}

/// How many more words have to be learned before the story unlocks (0 = unlocked).
#[uniffi::export]
pub fn story_missing_words(story: Story, known_word_ids: Vec<String>) -> u32 {
    missing(&story, &id_set(known_word_ids)) as u32
}

/// The day's story: the daily story dated today if it's unlocked, otherwise a pick from the unlocked undated
/// stories (same on every launch that day). `None` when nothing is unlocked.
#[uniffi::export]
pub fn story_of_the_day(day_key: String, known_word_ids: Vec<String>) -> Option<Story> {
    let known = id_set(known_word_ids);
    let open: Vec<Story> = all_for(Some(&known))
        .into_iter()
        .filter(|s| s.date == day_key || s.date.is_empty())
        .filter(|s| missing(s, &known) == 0)
        .collect();
    if let Some(s) = open.iter().find(|s| s.date == day_key) {
        return Some(s.clone());
    }
    if open.is_empty() {
        return None;
    }
    let i = day_seed(day_key) as usize % open.len();
    Some(open[i].clone())
}

/// A story on the shelf, locked or not.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ShelfStory {
    pub story: Story,
    pub unlocked: bool,
    /// Words still to learn before it unlocks (0 when unlocked).
    pub missing_words: u32,
}

fn shelf(day_key: &str, known: &IdSet) -> Vec<ShelfStory> {
    let mut out: Vec<ShelfStory> = all_for(Some(known))
        .into_iter()
        .filter(|s| s.date.is_empty() || s.date.as_str() <= day_key)
        .map(|story| {
            let missing_words = missing(&story, known) as u32;
            ShelfStory { story, unlocked: missing_words == 0, missing_words }
        })
        .collect();
    // stable: unlocked ones keep the easiest-first order, locked ones go by how soon they open
    out.sort_by_key(|s| s.missing_words);
    out
}

/// Stories for the shelf: everything except daily stories whose day hasn't come yet. Unlocked stories come
/// first, then the locked ones, the soonest to unlock first.
#[uniffi::export]
pub fn shelf_stories(day_key: String, known_word_ids: Vec<String>) -> Vec<ShelfStory> {
    shelf(&day_key, &id_set(known_word_ids))
}

/// The next unread story (or chat) for a learner: an unlocked one that isn't in `read`. Stories are ranked by
/// how well they fit: words of the `recent` unit count most, then new words that the `upcoming` lesson will
/// teach (so the story previews it), then known words; other new words count against it. A random one of the
/// best three is picked so it's still a surprise. `None` when every unlocked story has been read. Daily
/// stories whose day hasn't come yet are skipped.
#[uniffi::export]
pub fn next_story(
    chat: bool,
    day_key: String,
    read: Vec<String>,
    known_word_ids: Vec<String>,
    recent: Vec<String>,
    upcoming: Vec<String>,
    seed: u64,
) -> Option<Story> {
    let known = id_set(known_word_ids);
    let recent = id_set(recent);
    let upcoming = id_set(upcoming);
    let mut scored: Vec<(i64, Story)> = shelf(&day_key, &known)
        .into_iter()
        .filter(|s| s.unlocked)
        .map(|s| s.story)
        .filter(|s| (s.style == "chat") == chat && !read.contains(&s.id))
        .map(|s| (lesson_fit(&s, &known, &recent, &upcoming), s))
        .collect();
    if scored.is_empty() {
        return None;
    }
    let mut rng = fastrand::Rng::with_seed(seed);
    // shuffle first so equal scores don't always favour the same (alphabetically first) story
    rng.shuffle(&mut scored);
    scored.sort_by_key(|(score, _)| std::cmp::Reverse(*score));
    let best = scored[0].0;
    // the top three, as long as they're close to the best fit
    let pool: Vec<Story> = scored
        .into_iter()
        .take(3)
        .filter(|(score, _)| best - score <= 4)
        .map(|(_, s)| s)
        .collect();
    Some(pool[rng.usize(..pool.len())].clone())
}

/// How well a story fits where the learner is.
fn lesson_fit(story: &Story, known: &IdSet, recent: &IdSet, upcoming: &IdSet) -> i64 {
    let mut ids: Vec<&String> = tokens_of(story).filter(|t| is_vocab(t)).filter_map(|t| t.word_id.as_ref()).collect();
    ids.sort();
    ids.dedup();
    ids.into_iter()
        .map(|id| match (known.contains(id), recent.contains(id), upcoming.contains(id)) {
            (true, true, _) => 4,
            (true, false, _) => 1,
            (false, _, true) => 3,
            (false, true, _) => 2,
            _ => -2,
        })
        .sum()
}

/// Mix the order of every reply choice with a fresh seed (call it each time a story opens), so the
/// fitting reply moves around between reads and is never in the same spot twice in a row.
#[uniffi::export]
pub fn shuffle_story_replies(mut story: Story, seed: u64) -> Story {
    let mut rng = fastrand::Rng::with_seed(seed);
    let mut last: Option<usize> = None;
    for p in story.panels.iter_mut() {
        let n = p.reply.len();
        if n < 2 {
            continue;
        }
        rng.shuffle(&mut p.reply);
        if let Some(i) = p.reply.iter().position(|o| o.correct) {
            if Some(i) == last {
                let j = (i + 1 + rng.usize(..n - 1)) % n;
                p.reply.swap(i, j);
            }
            last = p.reply.iter().position(|o| o.correct);
        }
    }
    story
}

/// How many stories (or chats) a learner can read right now, read before or not, and how many are still locked.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StoryAvailability {
    pub unlocked: u32,
    pub locked: u32,
}

#[uniffi::export]
pub fn story_availability(chat: bool, day_key: String, known_word_ids: Vec<String>) -> StoryAvailability {
    let kind: Vec<ShelfStory> = shelf(&day_key, &id_set(known_word_ids))
        .into_iter()
        .filter(|s| (s.story.style == "chat") == chat)
        .collect();
    let unlocked = kind.iter().filter(|s| s.unlocked).count() as u32;
    StoryAvailability { unlocked, locked: kind.len() as u32 - unlocked }
}

/// What revealing one more English line costs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TranslationCost {
    /// The story's free peek.
    Free,
    /// Takes the story's XP away: ask first.
    Xp,
    /// The XP is already gone, so more reveals change nothing.
    Nothing,
}

/// Free translation reveals per story.
pub const STORY_FREE_PEEKS: u32 = 1;

/// The cost of the next reveal, after `translations_revealed` so far.
#[uniffi::export]
pub fn translation_cost(translations_revealed: u32) -> TranslationCost {
    match translations_revealed {
        n if n < STORY_FREE_PEEKS => TranslationCost::Free,
        STORY_FREE_PEEKS => TranslationCost::Xp,
        _ => TranslationCost::Nothing,
    }
}

/// XP a story pays: `base` with the free peek or none, nothing once more lines were translated.
#[uniffi::export]
pub fn story_xp(base: u32, translations_revealed: u32) -> u32 {
    if translations_revealed <= STORY_FREE_PEEKS {
        base
    } else {
        0
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

/// The vocabulary a story uses (lines, replies and reactions; names and numbers don't count), sorted.
#[uniffi::export]
pub fn story_word_ids(story: Story) -> Vec<String> {
    let mut ids: Vec<String> = tokens_of(&story)
        .filter(|t| is_vocab(t))
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
        let s = story_by_id("tea".into(), vec![]).unwrap();
        assert_eq!(
            s.panels[0].lines[0].tokens[0].word_id.as_deref(),
            Some("1-你好")
        );
        assert!(
            s.panels[1].question.is_none(),
            "out-of-range answers are dropped"
        );
        assert_eq!(story_of_the_day("2026-11-19".into(), vec![]).unwrap().id, "tea");
        assert_eq!(story_word_ids(s.clone()), vec!["1-你好".to_string()]);
        assert_eq!(story_image_urls(s), vec!["https://x/1.jpg".to_string()]);
    }
}

#[cfg(test)]
mod daily_tests {
    use super::*;

    fn none() -> Vec<String> {
        vec![]
    }

    #[test]
    fn daily_and_chat_stories() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // d1 has four words, so it takes one learned word to open it
        let json = r#"{"stories":[
          {"id":"a","title":"A","level":1,"panels":[{"lines":[{"zh":"你好"}]}]},
          {"id":"d1","title":"D1","level":3,"date":"2026-11-20","style":"chat","me":"我",
           "panels":[{"lines":[{"who":"丽丽","zh":"看猫喝茶！","image":{"url":"https://x/p.jpg"},
             "t":[["看","kàn"],["猫","māo"],["喝","hē"],["茶","chá"],["！",""]]}]}]},
          {"id":"d2","title":"D2","level":1,"date":"2026-11-21","panels":[{"lines":[{"zh":"好"}]}]}]}"#;
        // note: other tests replace the global store, so load + check in one go
        load_stories(json).unwrap();
        let cat = vec!["1-猫".to_string()];
        let day = || "2026-11-20".to_string();
        assert_eq!(story_of_the_day(day(), none()).unwrap().id, "a", "a locked daily story is skipped");
        let today = story_of_the_day(day(), cat.clone()).unwrap();
        assert_eq!(today.id, "d1", "the dated story wins once it's unlocked");
        assert_eq!(today.style, "chat");
        assert_eq!(today.panels[0].lines[0].image.as_ref().unwrap().url, "https://x/p.jpg");
        assert_eq!(story_of_the_day("2026-12-01".into(), none()).unwrap().id, "a", "no daily: undated pick");
        // next_story: chats only, never something already read, nothing from the future
        let next = |chat, read: Vec<String>, known| next_story(chat, "2026-11-20".into(), read, known, vec![], vec![], 1);
        assert!(next(true, vec![], none()).is_none(), "the only chat is locked");
        assert_eq!(next(true, vec![], cat.clone()).unwrap().id, "d1");
        assert!(next(true, vec!["d1".into()], cat.clone()).is_none(), "all chats read");
        assert_eq!(story_availability(true, day(), none()), StoryAvailability { unlocked: 0, locked: 1 });
        assert_eq!(story_availability(true, day(), cat.clone()), StoryAvailability { unlocked: 1, locked: 0 });
        assert_eq!(next(false, vec![], none()).unwrap().id, "a", "d2 is still in the future");
        let shelf = shelf_stories(day(), none());
        let ids: Vec<&str> = shelf.iter().map(|s| s.story.id.as_str()).collect();
        assert_eq!(ids, vec!["a", "d1"], "future dailies hidden, locked stories shown last");
        assert_eq!((shelf[1].unlocked, shelf[1].missing_words), (false, 1));
        let json2 = r#"{"stories":[{"id":"r","title":"R","level":1,"style":"chat","me":"我","panels":[{"lines":[{"who":"丽丽","zh":"你好吗？"}],
          "reply":{"options":[{"zh":"我很好！","ok":true,"t":[["我","wǒ"],["很","hěn"],["好","hǎo"],["！",""]],"then":{"who":"丽丽","zh":"太好了！"}},
                              {"zh":"再见。","ok":false}]}}]}]}"#;
        load_stories(json2).unwrap();
        let r = story_by_id("r".into(), vec![]).unwrap();
        let opts = &r.panels[0].reply;
        assert_eq!(opts.len(), 2);
        assert_eq!(opts.iter().filter(|o| o.correct).count(), 1);
        let ok = opts.iter().find(|o| o.correct).unwrap();
        assert_eq!(ok.reaction.as_ref().unwrap().zh, "太好了！");
        assert_eq!(ok.tokens.len(), 4);
        assert_eq!(story_word_ids(r.clone()).len(), 3, "reply words count too");
        assert!(ok.tokens[0].is_new && !ok.tokens[3].is_new, "reply options are marked");
        let r = story_by_id("r".into(), vec!["1-我".into()]).unwrap();
        let ok = r.panels[0].reply.iter().find(|o| o.correct).unwrap();
        assert!(!ok.tokens[0].is_new && ok.tokens[1].is_new);
    }
}

#[cfg(test)]
mod unlock_tests {
    use super::*;

    #[test]
    fn opens_with_at_most_three_new_words() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // six words: 我 喜欢 喝 茶 猫 狗 (plus a name, a number and punctuation, which don't count)
        let json = r#"{"stories":[{"id":"s","title":"s","level":1,"panels":[
          {"lines":[{"zh":"x","t":[["小明","Xiǎomíng"],["：",""],["我","wǒ"],["喜欢","xǐhuan"],["喝","hē"],["茶","chá"],["。",""]]},
                    {"zh":"x","t":[["三","sān"],["猫","māo"],["喝","hē"],["茶","chá"]]},
                    {"zh":"x","t":[["狗","gǒu"],["。",""]]}]}]}]}"#;
        load_stories(json).unwrap();
        let ids = |h: &[&str]| -> Vec<String> { h.iter().map(|h| format!("1-{h}")).collect() };
        let s = story_by_id("s".into(), vec![]).unwrap();
        assert_eq!(story_word_ids(s.clone()).len(), 6);
        assert_eq!(story_new_words(s.clone(), vec![]), ids(&["我", "喜欢", "喝", "茶", "猫", "狗"]), "reading order, once each");
        assert!(!story_unlocked(s.clone(), vec![]));
        assert_eq!(story_missing_words(s.clone(), vec![]), 3);
        assert_eq!(story_missing_words(s.clone(), ids(&["我", "喜欢"])), 1);
        assert!(!story_unlocked(s.clone(), ids(&["我", "喜欢"])));
        let known = ids(&["我", "喜欢", "喝"]);
        assert!(story_unlocked(s.clone(), known.clone()), "three new words are fine");
        assert_eq!(story_missing_words(s.clone(), known.clone()), 0);
        assert_eq!(story_new_words(s, known.clone()), ids(&["茶", "猫", "狗"]));
        // the story handed to the app is marked
        let s = story_by_id("s".into(), known).unwrap();
        let new: Vec<&str> = s.panels[0].lines.iter().flat_map(|l| &l.tokens).filter(|t| t.is_new).map(|t| t.text.as_str()).collect();
        assert_eq!(new, vec!["茶", "猫", "茶", "狗"]);
    }

    #[test]
    fn translations() {
        assert_eq!(story_xp(35, 0), 35);
        assert_eq!(story_xp(35, 1), 35);
        assert_eq!(story_xp(35, 2), 0);
        assert_eq!(story_xp(35, 9), 0);
        assert_eq!(translation_cost(0), TranslationCost::Free);
        assert_eq!(translation_cost(1), TranslationCost::Xp);
        assert_eq!(translation_cost(2), TranslationCost::Nothing);
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

#[cfg(test)]
mod lesson_tests {
    use super::*;

    #[test]
    fn picks_the_story_with_this_units_words() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let json = r#"{"stories":[
          {"id":"tea","title":"t","level":1,"panels":[{"lines":[{"zh":"喝茶","t":[["喝","hē"],["茶","chá"]]}]}]},
          {"id":"cat","title":"c","level":1,"panels":[{"lines":[{"zh":"猫","t":[["猫","māo"]]}]}]},
          {"id":"dog","title":"d","level":1,"panels":[{"lines":[{"zh":"狗","t":[["狗","gǒu"]]}]}]},
          {"id":"sun","title":"s","level":1,"panels":[{"lines":[{"zh":"太阳","t":[["太阳","tàiyáng"]]}]}]},
          {"id":"car","title":"r","level":1,"panels":[{"lines":[{"zh":"车","t":[["车","chē"]]}]}]}]}"#;
        load_stories(json).unwrap();
        let tea = story_by_id("tea".into(), vec![]).unwrap();
        let ids = story_word_ids(tea);
        assert!(!ids.is_empty(), "bundled words resolve");
        for seed in 0..40 {
            let s = next_story(false, "2026-11-19".into(), vec![], ids.clone(), ids.clone(), vec![], seed).unwrap();
            assert_eq!(s.id, "tea", "the story using this unit's words wins");
            let s = next_story(false, "2026-11-19".into(), vec![], vec![], vec![], ids.clone(), seed).unwrap();
            assert_eq!(s.id, "tea", "new words from the next lesson beat other new words");
        }
    }

    #[test]
    fn replies_move_around() {
        let opt = |ok: bool| ReplyOption {
            zh: if ok { "对".into() } else { "错".into() },
            pinyin: String::new(),
            en: String::new(),
            tokens: vec![],
            correct: ok,
            reaction: None,
        };
        let panel = StoryPanel {
            image: None,
            lines: vec![],
            question: None,
            reply: vec![opt(true), opt(false), opt(false)],
        };
        let story = Story {
            id: "r".into(),
            title: String::new(),
            title_en: String::new(),
            level: 1,
            emoji: String::new(),
            cover: None,
            panels: vec![panel.clone(), panel.clone(), panel],
            date: String::new(),
            style: "chat".into(),
            me: String::new(),
        };
        let mut firsts = std::collections::HashSet::new();
        for seed in 0..60 {
            let s = shuffle_story_replies(story.clone(), seed);
            let pos: Vec<usize> = s.panels.iter().map(|p| p.reply.iter().position(|o| o.correct).unwrap()).collect();
            assert!(pos.windows(2).all(|w| w[0] != w[1]), "never the same spot twice in a row");
            firsts.insert(pos[0]);
        }
        assert_eq!(firsts.len(), 3, "the first answer can be anywhere");
    }
}
