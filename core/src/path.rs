//! The learning path (Duolingo-style map): an HSK level's words split into lessons, grouped in units,
//! with sentence nodes and a story checkpoint in every unit and the level-up test at the end.

use crate::plan::unit_story_ready;
use crate::vocab::{id_set, known_word_ids};
use crate::words::bank;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PathNodeKind {
    Lesson,
    /// Sentences built only from words learned so far.
    Sentences,
    /// A reading checkpoint after a unit: a story or an SMS chat.
    Story,
    /// The HSK level-up test, always last.
    Test,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PathNodeState {
    Done,
    /// Can be started now. The first open lesson is "next up".
    Open,
    Locked,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PathNode {
    pub kind: PathNodeKind,
    /// Lesson number (1-based) for lessons, the lesson it follows for sentence nodes (unique in the level),
    /// unit number for stories, 0 for the test.
    pub number: u32,
    /// Unit the node belongs to (1-based).
    pub unit: u32,
    pub state: PathNodeState,
    /// The one node the big "start" button points at.
    pub next: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PathUnit {
    pub number: u32,
    /// First and last lesson in the unit.
    pub first_lesson: u32,
    pub last_lesson: u32,
    pub nodes: Vec<PathNode>,
}

/// Words a unit should have, whatever the daily goal.
const UNIT_WORDS: u32 = 25;

/// Lessons per unit, for lessons of `lesson_size` words: units are about the same size for everybody.
#[uniffi::export]
pub fn path_unit_size(lesson_size: u32) -> u32 {
    let size = lesson_size.max(1);
    ((UNIT_WORDS + size / 2) / size).max(1)
}

/// A second sentence node in the middle of a unit, after this many of its lessons (0 = none).
pub const PATH_MID_SENTENCES_AFTER: u32 = 3;

/// XP for finishing a sentence node the first time.
#[uniffi::export]
pub fn path_sentences_xp() -> u32 {
    15
}

/// The path of one level: each unit is lessons → sentences → story (a picture story in odd units, an SMS chat in even
/// ones), and the level-up test comes last. `card_ids` are the learned words, `confirmed_level` the levels below that
/// count as known, `lesson_size` is the daily goal, `stories_done` lists the units whose story is finished,
/// `sentences_done` the numbers of finished sentence nodes.
#[uniffi::export]
pub fn level_path(
    level: u8,
    lesson_size: u32,
    card_ids: Vec<String>,
    confirmed_level: u8,
    stories_done: Vec<u32>,
    sentences_done: Vec<u32>,
) -> Vec<PathUnit> {
    let cards = id_set(card_ids.clone());
    let (learned, total) = {
        let b = bank();
        let words: Vec<_> = b.regular.iter().filter(|w| w.level == level).collect();
        (words.iter().filter(|w| cards.contains(&w.id)).count() as u32, words.len() as u32)
    };
    let known = id_set(known_word_ids(card_ids, confirmed_level));
    learn_path(learned, total, lesson_size, stories_done, sentences_done, |unit| unit_story_ready(level, lesson_size, unit, &known))
}

/// `ready`: is this unit's story readable yet? (Only asked when everything before it is done.)
pub(crate) fn learn_path(
    learned: u32,
    total: u32,
    lesson_size: u32,
    stories_done: Vec<u32>,
    sentences_done: Vec<u32>,
    ready: impl Fn(u32) -> bool,
) -> Vec<PathUnit> {
    let size = lesson_size.max(1);
    let lessons = total.div_ceil(size).max(1);
    let per_unit = path_unit_size(size);
    let units = lessons.div_ceil(per_unit);
    let done_lessons = if learned >= total { lessons } else { learned / size };
    let state = |done: bool, open: bool| match (done, open) {
        (true, _) => PathNodeState::Done,
        (_, true) => PathNodeState::Open,
        _ => PathNodeState::Locked,
    };
    let mut out = Vec::new();
    for u in 1..=units {
        let first = (u - 1) * per_unit + 1;
        let last = (u * per_unit).min(lessons);
        let mut nodes = Vec::new();
        let mut push = |kind, number, state| nodes.push(PathNode { kind, number, unit: u, state, next: false });
        let sentences = |after: u32| state(sentences_done.contains(&after), done_lessons >= after);
        for l in first..=last {
            push(PathNodeKind::Lesson, l, state(l <= done_lessons, l == done_lessons + 1));
            if PATH_MID_SENTENCES_AFTER > 0 && l + 1 == first + PATH_MID_SENTENCES_AFTER && l < last {
                push(PathNodeKind::Sentences, l, sentences(l));
            }
        }
        push(PathNodeKind::Sentences, last, sentences(last));
        // stories finished before sentence nodes existed stay done
        let done = stories_done.contains(&u) && done_lessons >= last;
        let open = !done && sentences(last) == PathNodeState::Done && ready(u);
        push(PathNodeKind::Story, u, state(done, open));
        if u == units {
            push(PathNodeKind::Test, 0, state(false, done_lessons >= lessons));
        }
        out.push(PathUnit { number: u, first_lesson: first, last_lesson: last, nodes });
    }
    mark_next(&mut out);
    out
}

/// "Next up" is the first open lesson (or the test), unless the sentence node right before it is still open.
/// Older unfinished sentence nodes stay optional, so nobody is sent back to the start of the level.
fn mark_next(units: &mut [PathUnit]) {
    let mut flat: Vec<&mut PathNode> = units.iter_mut().flat_map(|u| u.nodes.iter_mut()).collect();
    let main = |n: &PathNode| matches!(n.kind, PathNodeKind::Lesson | PathNodeKind::Test);
    let Some(i) = flat.iter().position(|n| main(n) && n.state == PathNodeState::Open) else { return };
    let before = (0..i)
        .rev()
        .take_while(|&j| !main(flat[j]))
        .find(|&j| flat[j].kind == PathNodeKind::Sentences && flat[j].state == PathNodeState::Open);
    flat[before.unwrap_or(i)].next = true;
}

/// Sideways offset of the n-th node on the winding path, from -1 to 1 (multiply by the swing width).
#[uniffi::export]
pub fn path_swing(index: u32) -> f64 {
    // 0, 0.7, 1, 0.7, 0, -0.7, -1, -0.7, …
    (index as f64 * std::f64::consts::FRAC_PI_4).sin()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flat(p: &[PathUnit]) -> Vec<PathNode> {
        p.iter().flat_map(|u| u.nodes.clone()).collect()
    }

    fn find(n: &[PathNode], kind: PathNodeKind, number: u32) -> PathNode {
        n.iter().find(|x| x.kind == kind && x.number == number).unwrap().clone()
    }

    #[test]
    fn layout() {
        // 60 words, 5 a lesson: 12 lessons, units of 5 → 3 units (5, 5, 2)
        let p = learn_path(0, 60, 5, vec![], vec![], |_| true);
        assert_eq!(p.len(), 3);
        assert_eq!((p[2].first_lesson, p[2].last_lesson), (11, 12));
        use PathNodeKind::*;
        let kinds: Vec<_> = p[0].nodes.iter().map(|n| n.kind).collect();
        assert_eq!(kinds, vec![Lesson, Lesson, Lesson, Sentences, Lesson, Lesson, Sentences, Story]);
        let kinds: Vec<_> = p[2].nodes.iter().map(|n| n.kind).collect();
        assert_eq!(kinds, vec![Lesson, Lesson, Sentences, Story, Test], "a short unit has no middle node, but it has a story");
        let n = flat(&p);
        let mut numbers: Vec<u32> = n.iter().filter(|x| x.kind == Sentences).map(|x| x.number).collect();
        assert_eq!(numbers, vec![3, 5, 8, 10, 12]);
        numbers.dedup();
        assert_eq!(numbers.len(), 5, "unique within the level");
        assert!(n[0].next && n[0].state == PathNodeState::Open);
        assert_eq!(n.iter().filter(|x| x.next).count(), 1);
    }

    #[test]
    fn sentences_then_story() {
        use PathNodeKind::*;
        // 5 lessons done: both sentence nodes open, the story waits for the second one
        let n = flat(&learn_path(27, 60, 5, vec![], vec![], |_| true));
        assert_eq!(find(&n, Lesson, 5).state, PathNodeState::Done);
        assert_eq!(find(&n, Sentences, 3).state, PathNodeState::Open);
        assert_eq!(find(&n, Sentences, 5).state, PathNodeState::Open);
        assert_eq!(find(&n, Story, 1).state, PathNodeState::Locked);
        assert_eq!(find(&n, Sentences, 8).state, PathNodeState::Locked);
        assert!(find(&n, Sentences, 5).next, "the node before lesson 6 comes first");
        assert_eq!(find(&n, Lesson, 6).state, PathNodeState::Open, "but lesson 6 isn't blocked");
        assert_eq!(n.iter().filter(|x| x.next).count(), 1);

        let n = flat(&learn_path(27, 60, 5, vec![], vec![5], |_| true));
        assert_eq!(find(&n, Story, 1).state, PathNodeState::Open);
        assert!(find(&n, Lesson, 6).next, "older open sentence nodes are optional");
        let n = flat(&learn_path(27, 60, 5, vec![1], vec![], |_| true));
        assert_eq!(find(&n, Story, 1).state, PathNodeState::Done, "old saves keep finished stories");

        // the middle node
        let n = flat(&learn_path(15, 60, 5, vec![], vec![], |_| true));
        assert!(find(&n, Sentences, 3).next);
        assert!(flat(&learn_path(16, 60, 5, vec![], vec![3], |_| true)).iter().any(|x| x.next && x.number == 4));
    }

    #[test]
    fn test_comes_last() {
        // everything learned → the last sentence node, then the test
        let n = flat(&learn_path(60, 60, 5, vec![1, 2], vec![], |_| true));
        let t = n.last().unwrap();
        assert!(!t.next && t.state == PathNodeState::Open, "sentences never block the test");
        let n = flat(&learn_path(60, 60, 5, vec![1, 2], vec![12], |_| true));
        assert!(n.last().unwrap().next);
        // partial last lesson counts once every word is in
        let n = flat(&learn_path(58, 58, 5, vec![], vec![12], |_| true));
        assert!(n.last().unwrap().next);
    }

    #[test]
    fn units_are_the_same_size_for_everybody() {
        assert_eq!((path_unit_size(3), path_unit_size(5), path_unit_size(8), path_unit_size(1)), (8, 5, 3, 25));
        for size in 1..=15 {
            let words = size * path_unit_size(size);
            assert!((22..=30).contains(&words), "{size} a day: {words} words a unit");
        }
        assert!(path_unit_size(0) > 0 && path_unit_size(99) == 1);
    }

    #[test]
    fn stories_wait_for_their_words() {
        use PathNodeKind::*;
        let n = flat(&learn_path(27, 60, 5, vec![], vec![5], |_| false));
        assert_eq!(find(&n, Story, 1).state, PathNodeState::Locked);
        // a story marked done in a unit that isn't reached yet (the daily goal changed)
        let n = flat(&learn_path(27, 60, 5, vec![1, 2], vec![5], |_| true));
        assert_eq!((find(&n, Story, 1).state, find(&n, Story, 2).state), (PathNodeState::Done, PathNodeState::Locked));
    }

    #[test]
    fn swing() {
        assert!(path_swing(0).abs() < 1e-9);
        assert!((path_swing(2) - 1.0).abs() < 1e-9);
        assert!((path_swing(6) + 1.0).abs() < 1e-9);
    }
}
