//! In which order a level's words are taught. Every unit of the roadmap ends with a story, so each unit teaches the
//! words one more story needs; the rest of the unit is filled up with the level's most common words.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

use crate::path::path_unit_size;
use crate::stories::{story_needs, story_new_ids, story_version, STORY_MAX_NEW_WORDS};
use crate::vocab::{id_set, known_word_ids, IdSet};
use crate::words::bank;

/// How far down the list of common words a unit may look for words to fill it up with.
const FILL_WINDOW: usize = 150;

#[derive(Clone, Default)]
struct Plan {
    /// The whole level in teaching order, as if nothing of it was learned yet.
    order: Vec<String>,
    /// The story at the end of each unit: a picture story in odd units, an SMS chat in even ones ("" only when there
    /// are no stories of that kind at all).
    stories: Vec<String>,
}

/// A story waiting for its unit.
struct Waiting {
    id: String,
    chat: bool,
    need: Vec<String>,
    /// How many of `need` may stay unlearned.
    spare: usize,
}

impl Waiting {
    fn cost(&self, taught: &HashSet<String>) -> usize {
        self.need.iter().filter(|w| !taught.contains(*w)).count().saturating_sub(self.spare)
    }
}

fn plan(level: u8, unit: usize) -> Plan {
    let (base, below): (Vec<String>, IdSet) = {
        let b = bank();
        (
            b.regular.iter().filter(|w| w.level == level).map(|w| w.id.clone()).collect(),
            b.regular.iter().filter(|w| w.level < level).map(|w| w.id.clone()).collect(),
        )
    };
    let rank: HashMap<&String, usize> = base.iter().enumerate().map(|(i, id)| (id, i)).collect();
    // stories that already end a unit of an easier level
    let used: HashSet<String> = (1..level).flat_map(|l| planned(l, unit).stories).collect();
    let mut readable: Vec<(String, bool)> = vec![];
    let mut stories: Vec<Waiting> = story_needs(level, &below)
        .into_iter()
        .filter(|s| s.harder <= STORY_MAX_NEW_WORDS)
        .map(|s| {
            readable.push((s.id.clone(), s.chat));
            Waiting { id: s.id, chat: s.chat, need: s.need, spare: STORY_MAX_NEW_WORDS - s.harder }
        })
        .filter(|s| !used.contains(&s.id))
        .collect();
    let mut taught: HashSet<String> = HashSet::new();
    let mut plan = Plan::default();
    while plan.order.len() < base.len() {
        let chat = plan.stories.len() % 2 == 1;
        let room = unit.min(base.len() - plan.order.len());
        let mut words: Vec<String> = vec![];
        // the story of the right kind that needs the fewest words, but needs some (ties: by id, so it's the same on
        // every launch); else one that can be read already
        let cost = |s: &Waiting| s.cost(&taught);
        let best = stories
            .iter()
            .enumerate()
            .filter(|(_, s)| s.chat == chat && cost(s) <= room)
            .min_by_key(|(_, s)| (cost(s) == 0, cost(s), std::cmp::Reverse(s.need.len()), s.id.clone()))
            .map(|(i, s)| (i, cost(s)));
        match best {
            Some((i, cost)) => {
                let s = stories.swap_remove(i);
                let mut missing: Vec<String> = s.need.into_iter().filter(|w| !taught.contains(w)).collect();
                // the most common ones; the rarest stay new in the story
                missing.sort_by_key(|w| rank.get(w).copied().unwrap_or(usize::MAX));
                missing.truncate(cost);
                words = missing;
                plan.stories.push(s.id);
            }
            None => {
                // out of fresh ones: one from an easier level or an earlier unit again
                let again: Vec<&String> =
                    readable.iter().filter(|(id, c)| *c == chat && !stories.iter().any(|s| s.id == *id)).map(|(id, _)| id).collect();
                let pick = again.iter().min_by_key(|id| (plan.stories.iter().filter(|s| s == *id).count(), **id));
                plan.stories.push(pick.map(|s| s.to_string()).unwrap_or_default());
            }
        }
        taught.extend(words.iter().cloned());
        // fill up with common words, but leave the ones other stories wait for to those stories' own units
        let wanted: HashSet<&String> = stories.iter().flat_map(|s| &s.need).collect();
        let next: Vec<&String> = base.iter().filter(|w| !taught.contains(*w)).take(FILL_WINDOW.max(room)).collect();
        let (keep, free): (Vec<&String>, Vec<&String>) = next.into_iter().partition(|w| wanted.contains(*w));
        let fill: Vec<String> = free.into_iter().chain(keep).take(room - words.len()).cloned().collect();
        taught.extend(fill.iter().cloned());
        words.extend(fill);
        words.sort_by_key(|w| rank.get(w).copied().unwrap_or(usize::MAX));
        plan.order.extend(words);
    }
    plan
}

type Key = (u8, usize, u64, usize);

/// The plan of a level for units of `unit` words (cached).
fn planned(level: u8, unit: usize) -> Plan {
    static CACHE: OnceLock<Mutex<HashMap<Key, Plan>>> = OnceLock::new();
    let key = (level, unit, story_version(), bank().regular.len());
    let cache = CACHE.get_or_init(Default::default);
    if let Some(p) = cache.lock().unwrap_or_else(|e| e.into_inner()).get(&key) {
        return p.clone();
    }
    let p = plan(level, unit);
    let mut c = cache.lock().unwrap_or_else(|e| e.into_inner());
    c.retain(|k, _| k.2 == key.2 && k.3 == key.3 && k.1 == key.1);
    c.insert(key, p.clone());
    p
}

fn unit_words(lesson_size: u32) -> usize {
    let size = lesson_size.max(1);
    (size * path_unit_size(size)) as usize
}

/// A level's word ids in teaching order for lessons of `lesson_size` words: the learned ones first (so finished
/// lessons can be replayed), then the rest in the order that opens one story per unit.
#[uniffi::export]
pub fn path_words(level: u8, lesson_size: u32, learned_word_ids: Vec<String>) -> Vec<String> {
    let learned = id_set(learned_word_ids);
    let (mut done, rest): (Vec<String>, Vec<String>) =
        planned(level, unit_words(lesson_size)).order.into_iter().partition(|w| learned.contains(w));
    done.extend(rest);
    done
}

/// The story at the end of a unit (1-based), "" when there is none.
#[uniffi::export]
pub fn unit_story(level: u8, lesson_size: u32, unit: u32) -> String {
    planned(level, unit_words(lesson_size)).stories.get((unit as usize).wrapping_sub(1)).cloned().unwrap_or_default()
}

/// The stories of a level's units from `from_unit` on: they're kept for the path.
#[uniffi::export]
pub fn reserved_stories(level: u8, lesson_size: u32, from_unit: u32) -> Vec<String> {
    planned(level, unit_words(lesson_size)).stories.into_iter().skip((from_unit as usize).saturating_sub(1)).filter(|s| !s.is_empty()).collect()
}

/// Can the unit's story be read? (A unit without one has nothing to wait for.)
pub(crate) fn unit_story_ready(level: u8, lesson_size: u32, unit: u32, known: &IdSet) -> bool {
    let id = unit_story(level, lesson_size, unit);
    story_new_ids(&id, known).is_none_or(|new| new.len() <= STORY_MAX_NEW_WORDS)
}

/// The lesson that brings somebody closer to a locked story: the words it still needs, easiest level first and in the
/// path's order, at most `lesson_size`. Empty when it can be read already.
#[uniffi::export]
pub fn story_lesson(story_id: String, level: u8, lesson_size: u32, card_ids: Vec<String>, confirmed_level: u8) -> Vec<String> {
    let known = id_set(known_word_ids(card_ids, confirmed_level));
    let new = story_new_ids(&story_id, &known).unwrap_or_default();
    if new.len() <= STORY_MAX_NEW_WORDS {
        return vec![];
    }
    let order: HashMap<String, usize> = planned(level, unit_words(lesson_size)).order.into_iter().enumerate().map(|(i, w)| (w, i)).collect();
    let b = bank();
    let mut words: Vec<(u8, usize, String)> = new
        .into_iter()
        .map(|id| (b.by_id.get(&id).map_or(u8::MAX, |w| w.level), order.get(&id).copied().unwrap_or(usize::MAX), id))
        .collect();
    words.sort();
    words.into_iter().take(lesson_size.max(1) as usize).map(|w| w.2).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stories::{load_stories, story_by_id, story_unlocked, TEST_LOCK};

    fn story(id: &str, words: &[String], chat: bool) -> String {
        let t: Vec<String> = words.iter().map(|w| format!(r#"["{w}","x"]"#)).collect();
        let style = if chat { r#","style":"chat""# } else { "" };
        format!(r#"{{"id":"{id}","title":"t","level":1{style},"panels":[{{"lines":[{{"zh":"{}","t":[{}]}}]}}]}}"#, words.concat(), t.join(","))
    }

    fn load(stories: &[String]) {
        load_stories(&format!(r#"{{"stories":[{}]}}"#, stories.join(","))).unwrap();
    }

    /// The level-1 words of the bundled list, most common first.
    fn level1() -> Vec<String> {
        bank().regular.iter().filter(|w| w.level == 1).map(|w| w.hanzi.clone()).collect()
    }

    #[test]
    fn every_unit_has_a_story_of_its_kind() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let w = level1();
        let n = w.len();
        assert!(n >= 50, "{n}");
        // a picture story and two chats made of words from the far end of the list
        load(&[
            story("p1", &w[n - 8..], false),
            story("c1", &w[n - 18..n - 8], true),
            story("c2", &w[n - 30..n - 18], true),
        ]);
        let ids = path_words(1, 5, vec![]);
        assert_eq!(ids.len(), n, "every word is taught");
        assert_eq!(ids.iter().collect::<HashSet<_>>().len(), n, "exactly once");
        let units = n.div_ceil(25) as u32;
        let stories: Vec<String> = (1..=units).map(|u| unit_story(1, 5, u)).collect();
        assert_eq!(stories[..2], ["p1".to_string(), "c1".into()], "a picture story, then the chat that needs the fewest words");
        for (i, id) in stories.iter().enumerate() {
            let s = story_by_id(id.clone(), vec![]).unwrap();
            assert_eq!(s.style == "chat", i % 2 == 1, "unit {}", i + 1);
            assert!(story_unlocked(s, ids[..((i + 1) * 25).min(n)].to_vec()), "unit {}'s story can be read at its end", i + 1);
        }
        assert_eq!(unit_story(1, 5, 0), "");
        assert_eq!(unit_story(1, 5, 99), "");
        assert_eq!(reserved_stories(1, 5, 2), stories[1..]);
        assert_eq!(ids, path_words(1, 5, vec![]), "stable");
        // replaying: what's learned comes first, the rest keeps its order
        let learned: Vec<String> = ids[30..33].to_vec();
        let after = path_words(1, 5, learned.clone());
        assert_eq!(after[..3], learned[..]);
        assert_eq!(after[3..].to_vec(), ids.iter().filter(|i| !learned.contains(i)).cloned().collect::<Vec<_>>());
        // learning along the plan doesn't change it
        assert_eq!(path_words(1, 5, ids[..25].to_vec()), ids);
        load(&[]);
        let plain: Vec<String> = bank().regular.iter().filter(|w| w.level == 1).map(|w| w.id.clone()).collect();
        assert_eq!(path_words(1, 5, vec![]), plain, "without stories: the word list's own order");
        assert_eq!(unit_story(1, 5, 1), "");
        assert!(path_words(77, 5, vec![]).is_empty());
    }

    #[test]
    fn learn_words_for_a_locked_story() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let w = level1();
        let n = w.len();
        load(&[story("p1", &w[n - 12..], false)]);
        let mut cards: Vec<String> = vec![];
        let mut lessons = 0;
        loop {
            let lesson = story_lesson("p1".into(), 1, 5, cards.clone(), 0);
            if lesson.is_empty() {
                break;
            }
            assert!(lesson.len() <= 5);
            cards.extend(lesson);
            lessons += 1;
            assert!(lessons < 5);
        }
        assert_eq!(lessons, 2, "twelve words, three may stay new");
        assert!(unit_story_ready(1, 5, 1, &id_set(cards)));
        assert!(!unit_story_ready(1, 5, 1, &id_set(vec![])));
        assert!(story_lesson("nope".into(), 1, 5, vec![], 0).is_empty());
        assert!(story_lesson("p1".into(), 1, 5, vec![], 1).is_empty(), "a confirmed level is known");
        load(&[]);
    }
}
