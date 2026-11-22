//! In which order a level's words are taught. Every unit of the roadmap ends with a story, so each unit teaches the
//! words one more story needs; the rest of the unit is filled up with the level's most common words.

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};

use crate::path::path_unit_size;
use crate::stories::{story_needs, story_version, STORY_MAX_NEW_WORDS};
use crate::vocab::{id_set, IdSet};
use crate::words::bank;

/// How far down the list of common words a unit may look for words to fill it up with.
const FILL_WINDOW: usize = 150;

/// The whole level in teaching order, as if nothing of it was learned yet.
fn plan(level: u8, unit: usize) -> Vec<String> {
    let (base, below): (Vec<String>, IdSet) = {
        let b = bank();
        (
            b.regular.iter().filter(|w| w.level == level).map(|w| w.id.clone()).collect(),
            b.regular.iter().filter(|w| w.level < level).map(|w| w.id.clone()).collect(),
        )
    };
    let rank: HashMap<&String, usize> = base.iter().enumerate().map(|(i, id)| (id, i)).collect();
    // per story: the words of this level it needs, and how many of them may stay unlearned
    let mut stories: Vec<(String, Vec<String>, usize)> = story_needs(level, &below)
        .into_iter()
        .filter(|(_, need, harder)| *harder <= STORY_MAX_NEW_WORDS && need.len() + harder > STORY_MAX_NEW_WORDS)
        .map(|(id, need, harder)| (id, need, STORY_MAX_NEW_WORDS - harder))
        .collect();
    let mut taught: HashSet<String> = HashSet::new();
    let mut out = Vec::with_capacity(base.len());
    while out.len() < base.len() {
        let room = unit.min(base.len() - out.len());
        let mut words: Vec<String> = vec![];
        // the story that needs the fewest words (ties: by id, so it's the same on every launch)
        let best = stories
            .iter()
            .enumerate()
            .map(|(i, (id, need, spare))| (need.iter().filter(|w| !taught.contains(*w)).count().saturating_sub(*spare), id, i))
            .filter(|(cost, _, _)| (1..=room).contains(cost))
            .min();
        if let Some((cost, _, i)) = best {
            let (_, need, _) = stories.swap_remove(i);
            let mut missing: Vec<String> = need.into_iter().filter(|w| !taught.contains(w)).collect();
            // the most common ones; the rarest stay new in the story
            missing.sort_by_key(|w| rank.get(w).copied().unwrap_or(usize::MAX));
            missing.truncate(cost);
            words = missing;
        }
        taught.extend(words.iter().cloned());
        // fill up with common words, but leave the ones other stories wait for to those stories' own units
        let wanted: HashSet<&String> = stories.iter().flat_map(|(_, need, _)| need).collect();
        let next: Vec<&String> = base.iter().filter(|w| !taught.contains(*w)).take(FILL_WINDOW.max(room)).collect();
        let (keep, free): (Vec<&String>, Vec<&String>) = next.into_iter().partition(|w| wanted.contains(*w));
        let fill: Vec<String> = free.into_iter().chain(keep).take(room - words.len()).cloned().collect();
        taught.extend(fill.iter().cloned());
        words.extend(fill);
        words.sort_by_key(|w| rank.get(w).copied().unwrap_or(usize::MAX));
        out.extend(words);
        // stories that just became readable don't need a unit of their own
        stories.retain(|(_, need, spare)| need.iter().filter(|w| !taught.contains(*w)).count() > *spare);
    }
    out
}

type Key = (u8, usize, u64, usize);

/// A level's word ids in teaching order for lessons of `lesson_size` words: the learned ones first (so finished
/// lessons can be replayed), then the rest in the order that opens one story per unit.
#[uniffi::export]
pub fn path_words(level: u8, lesson_size: u32, learned_word_ids: Vec<String>) -> Vec<String> {
    static CACHE: OnceLock<Mutex<HashMap<Key, Vec<String>>>> = OnceLock::new();
    let unit = (lesson_size.max(1) * path_unit_size()) as usize;
    let words = bank().regular.len();
    let key = (level, unit, story_version(), words);
    let cache = CACHE.get_or_init(Default::default);
    let cached = cache.lock().unwrap_or_else(|e| e.into_inner()).get(&key).cloned();
    let order = cached.unwrap_or_else(|| {
        let order = plan(level, unit);
        let mut c = cache.lock().unwrap_or_else(|e| e.into_inner());
        if c.len() > 24 {
            c.clear();
        }
        c.insert(key, order.clone());
        order
    });
    let learned = id_set(learned_word_ids);
    let (mut done, rest): (Vec<String>, Vec<String>) = order.into_iter().partition(|w| learned.contains(w));
    done.extend(rest);
    done
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::stories::{load_stories, story_by_id, story_unlocked, TEST_LOCK};

    fn story(id: &str, words: &[&str]) -> String {
        let t: Vec<String> = words.iter().map(|w| format!(r#"["{w}","x"]"#)).collect();
        format!(r#"{{"id":"{id}","title":"t","level":1,"panels":[{{"lines":[{{"zh":"{}","t":[{}]}}]}}]}}"#, words.concat(), t.join(","))
    }

    /// The level-1 words, rarest (last) first.
    fn level1() -> Vec<String> {
        bank().regular.iter().filter(|w| w.level == 1).map(|w| w.hanzi.clone()).collect()
    }

    #[test]
    fn every_unit_opens_a_story() {
        let _guard = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let w = level1();
        let n = w.len();
        // two stories made of words from the far end of the list
        let late: Vec<&str> = w[n - 8..].iter().map(String::as_str).collect();
        let later: Vec<&str> = w[n - 18..n - 8].iter().map(String::as_str).collect();
        load_stories(&format!(r#"{{"stories":[{},{}]}}"#, story("a", &late), story("b", &later))).unwrap();
        let ids = path_words(1, 2, vec![]);
        assert_eq!(ids.len(), n, "every word is taught");
        assert_eq!(ids.iter().collect::<HashSet<_>>().len(), n, "exactly once");
        let open = |id: &str, known: usize| story_unlocked(story_by_id(id.into(), vec![]).unwrap(), ids[..known].to_vec());
        // units of ten words: the first opens the story that needs the fewest
        assert!(open("a", 10) && !open("b", 10));
        assert!(open("b", 20));
        assert_eq!(ids, path_words(1, 2, vec![]), "stable");
        // replaying: what's learned comes first, the rest keeps its order
        let learned: Vec<String> = ids[30..33].to_vec();
        let after = path_words(1, 2, learned.clone());
        assert_eq!(after[..3], learned[..]);
        assert_eq!(after[3..].to_vec(), ids.iter().filter(|i| !learned.contains(i)).cloned().collect::<Vec<_>>());
        // learning along the plan doesn't change it
        assert_eq!(path_words(1, 2, ids[..25].to_vec()), ids);
        load_stories(r#"{"stories":[]}"#).unwrap();
        let plain: Vec<String> = bank().regular.iter().filter(|w| w.level == 1).map(|w| w.id.clone()).collect();
        assert_eq!(path_words(1, 5, vec![]), plain, "without stories: the word list's own order");
        assert!(path_words(77, 5, vec![]).is_empty());
    }
}
