//! The learning path (Duolingo-style map): an HSK level's words split into lessons, grouped in units,
//! with a story checkpoint after every unit and the level-up test at the end.

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PathNodeKind {
    Lesson,
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
    /// Lesson number (1-based) for lessons, unit number for stories, 0 for the test.
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

/// Lessons per unit.
#[uniffi::export]
pub fn path_unit_size() -> u32 {
    5
}

/// Builds the path for one level. `learned`/`total` count the level's words, `lesson_size` is the
/// daily goal, `stories_done` lists the units whose story checkpoint is finished.
#[uniffi::export]
pub fn learn_path(learned: u32, total: u32, lesson_size: u32, stories_done: Vec<u32>) -> Vec<PathUnit> {
    let size = lesson_size.max(1);
    let lessons = total.div_ceil(size).max(1);
    let per_unit = path_unit_size();
    let units = lessons.div_ceil(per_unit);
    let done_lessons = if learned >= total { lessons } else { learned / size };
    let all_done = done_lessons >= lessons;
    let mut next_set = false;
    let mut out = Vec::new();
    for u in 1..=units {
        let first = (u - 1) * per_unit + 1;
        let last = (u * per_unit).min(lessons);
        let mut nodes = Vec::new();
        for l in first..=last {
            let state = if l <= done_lessons {
                PathNodeState::Done
            } else if l == done_lessons + 1 {
                PathNodeState::Open
            } else {
                PathNodeState::Locked
            };
            let next = state == PathNodeState::Open && !next_set;
            next_set |= next;
            nodes.push(PathNode { kind: PathNodeKind::Lesson, number: l, unit: u, state, next });
        }
        if u < units {
            let state = if stories_done.contains(&u) {
                PathNodeState::Done
            } else if done_lessons >= last {
                PathNodeState::Open
            } else {
                PathNodeState::Locked
            };
            nodes.push(PathNode { kind: PathNodeKind::Story, number: u, unit: u, state, next: false });
        } else {
            let state = if all_done { PathNodeState::Open } else { PathNodeState::Locked };
            let next = state == PathNodeState::Open && !next_set;
            next_set |= next;
            nodes.push(PathNode { kind: PathNodeKind::Test, number: 0, unit: u, state, next });
        }
        out.push(PathUnit { number: u, first_lesson: first, last_lesson: last, nodes });
    }
    out
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

    #[test]
    fn layout() {
        // 60 words, 5 a lesson: 12 lessons, units of 5 → 3 units (5, 5, 2)
        let p = learn_path(0, 60, 5, vec![]);
        assert_eq!(p.len(), 3);
        assert_eq!((p[2].first_lesson, p[2].last_lesson), (11, 12));
        let n = flat(&p);
        assert_eq!(n.len(), 12 + 2 + 1, "12 lessons, 2 stories, 1 test");
        assert_eq!(n.last().unwrap().kind, PathNodeKind::Test);
        assert_eq!(n[5].kind, PathNodeKind::Story);
        assert!(n[0].next && n[0].state == PathNodeState::Open);
        assert_eq!(n.iter().filter(|x| x.next).count(), 1);
    }

    #[test]
    fn progress() {
        let n = flat(&learn_path(27, 60, 5, vec![]));
        // 5 lessons done → unit 1 story open, lesson 6 next
        assert_eq!(n[4].state, PathNodeState::Done);
        assert_eq!(n[5].state, PathNodeState::Open);
        assert!(!n[5].next);
        assert!(n[6].next && n[6].number == 6);
        let n = flat(&learn_path(27, 60, 5, vec![1]));
        assert_eq!(n[5].state, PathNodeState::Done);
        // everything learned → test is next
        let n = flat(&learn_path(60, 60, 5, vec![1, 2]));
        let t = n.last().unwrap();
        assert!(t.next && t.state == PathNodeState::Open);
        // partial last lesson counts once every word is in
        let n = flat(&learn_path(58, 58, 5, vec![]));
        assert!(n.last().unwrap().next);
    }

    #[test]
    fn swing() {
        assert!(path_swing(0).abs() < 1e-9);
        assert!((path_swing(2) - 1.0).abs() < 1e-9);
        assert!((path_swing(6) + 1.0).abs() < 1e-9);
    }
}
