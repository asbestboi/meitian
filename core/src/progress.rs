//! Spaced repetition, streaks, player levels and the placement test.
//! Days are passed as "day numbers" (days since 1970-01-01 in the user's time zone), so the
//! platforms keep owning calendars and time zones.

/// Leitner box intervals in days, indexed by box.
pub const INTERVALS: [u32; 7] = [0, 1, 2, 4, 8, 16, 32];

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SrsStep {
    /// New box (1–6).
    pub box_level: u8,
    /// Days from today until the card is due again.
    pub days_until_due: u32,
}

/// Grades a review: right moves the card up a box, wrong sends it back to box 1.
#[uniffi::export]
pub fn srs_grade(box_level: u8, right: bool) -> SrsStep {
    let max = (INTERVALS.len() - 1) as u8;
    let b = if right { (box_level + 1).min(max) } else { 1 };
    SrsStep { box_level: b, days_until_due: INTERVALS[b as usize] }
}

#[uniffi::export]
pub fn srs_is_mastered(box_level: u8) -> bool {
    box_level >= 4
}

/// Day number (days since 1970-01-01) for a "YYYY-MM-DD" key. Civil-calendar math, no time zones.
#[uniffi::export]
pub fn day_number(day_key: String) -> Option<i64> {
    let mut it = day_key.split('-').map(|p| p.parse::<i64>());
    let (y, m, d) = (it.next()?.ok()?, it.next()?.ok()?, it.next()?.ok()?);
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    // Howard Hinnant's days_from_civil
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146097 + doe - 719468)
}

/// Current streak: consecutive active days ending today, or yesterday if today isn't done yet.
#[uniffi::export]
pub fn current_streak(active_days: Vec<i64>, today: i64) -> u32 {
    let set: std::collections::HashSet<i64> = active_days.into_iter().collect();
    let mut day = if set.contains(&today) { today } else { today - 1 };
    let mut n = 0;
    while set.contains(&day) {
        n += 1;
        day -= 1;
    }
    n
}

#[uniffi::export]
pub fn best_streak(active_days: Vec<i64>) -> u32 {
    let mut days = active_days;
    days.sort_unstable();
    days.dedup();
    let (mut best, mut run, mut prev) = (0u32, 0u32, i64::MIN);
    for d in days {
        run = if prev != i64::MIN && d == prev + 1 { run + 1 } else { 1 };
        best = best.max(run);
        prev = d;
    }
    best
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PlayerLevel {
    pub level: u32,
    /// 0.0–1.0 through the current level.
    pub progress: f64,
    pub xp_to_next: u32,
}

/// XP needed per level grows gently: level n starts at (n-1)² × 100 XP.
#[uniffi::export]
pub fn player_level(xp: u32) -> PlayerLevel {
    let level = ((xp as f64) / 100.0).sqrt() as u32 + 1;
    let lo = (level - 1).pow(2) * 100;
    let hi = level.pow(2) * 100;
    PlayerLevel { level, progress: (xp - lo) as f64 / (hi - lo) as f64, xp_to_next: hi - xp }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PlacementAnswer {
    pub level: u8,
    pub right: bool,
}

/// Highest level whose questions (and all below) were mostly right (2 of 3). 0 = beginner.
#[uniffi::export]
pub fn placement_level(answers: Vec<PlacementAnswer>) -> u8 {
    let mut confirmed = 0;
    for level in 1..=6u8 {
        let right = answers.iter().filter(|a| a.level == level && a.right).count();
        if right >= 2 {
            confirmed = level;
        } else {
            break;
        }
    }
    confirmed
}

/// The adaptive placement test stops after a block of 3 questions if that level wasn't passed.
#[uniffi::export]
pub fn placement_should_continue(answers: Vec<PlacementAnswer>) -> bool {
    if !answers.len().is_multiple_of(3) || answers.is_empty() {
        return true;
    }
    let level = answers[answers.len() - 1].level;
    answers.iter().filter(|a| a.level == level && a.right).count() >= 2
}

/// Questions in an HSK level-up test.
#[uniffi::export]
pub fn level_test_size() -> u32 {
    20
}

/// A level-up test is passed with 80% or more right.
#[uniffi::export]
pub fn level_test_passed(right: u32, total: u32) -> bool {
    total > 0 && right * 5 >= total * 4
}

/// Words for an HSK level-up test: the level's words the learner has learned come first (shuffled),
/// topped up with the rest of the level when they're testing out early. Never repeats a word.
#[uniffi::export]
pub fn level_test_word_ids(level_ids: Vec<String>, learned_ids: Vec<String>, seed: u64) -> Vec<String> {
    let learned: std::collections::HashSet<&String> = learned_ids.iter().collect();
    let mut rng = fastrand::Rng::with_seed(seed);
    let (mut known, mut rest): (Vec<String>, Vec<String>) = level_ids.into_iter().partition(|id| learned.contains(id));
    known.dedup();
    rest.dedup();
    rng.shuffle(&mut known);
    rng.shuffle(&mut rest);
    known.into_iter().chain(rest).take(level_test_size() as usize).collect()
}

/// Levels the learner already knows: the placement result, raised through every following level whose
/// words have all been learned (so nobody loses a level when level-up tests arrive).
/// `learned_per_level` and `total_per_level` are indexed by level − 1.
#[uniffi::export]
pub fn known_level(confirmed: u8, learned_per_level: Vec<u32>, total_per_level: Vec<u32>) -> u8 {
    let mut level = confirmed;
    while let (Some(&l), Some(&t)) = (learned_per_level.get(level as usize), total_per_level.get(level as usize)) {
        if t == 0 || l < t {
            break;
        }
        level += 1;
    }
    level
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn srs() {
        assert_eq!(srs_grade(1, true), SrsStep { box_level: 2, days_until_due: 2 });
        assert_eq!(srs_grade(6, true).box_level, 6);
        assert_eq!(srs_grade(5, false), SrsStep { box_level: 1, days_until_due: 1 });
    }

    #[test]
    fn streaks() {
        assert_eq!(current_streak(vec![10, 11, 12], 12), 3);
        assert_eq!(current_streak(vec![10, 11, 12], 13), 3); // today not done yet
        assert_eq!(current_streak(vec![10, 11], 13), 0);
        assert_eq!(best_streak(vec![1, 2, 3, 7, 8, 3]), 3);
    }

    #[test]
    fn day_numbers() {
        assert_eq!(day_number("1970-01-01".into()), Some(0));
        assert_eq!(day_number("2026-11-19".into()), Some(20776));
        assert_eq!(day_number("2024-03-01".into()).unwrap() - day_number("2024-02-28".into()).unwrap(), 2);
        assert_eq!(day_number("nope".into()), None);
    }

    #[test]
    fn levels() {
        assert_eq!(player_level(0).level, 1);
        assert_eq!(player_level(100).level, 2);
        assert_eq!(player_level(399).xp_to_next, 1);
    }

    #[test]
    fn placement() {
        let a = |level, right| PlacementAnswer { level, right };
        assert_eq!(placement_level(vec![a(1, true), a(1, true), a(1, false), a(2, false), a(2, false), a(2, true)]), 1);
        assert_eq!(placement_level(vec![a(1, false), a(1, false), a(1, true), a(2, true), a(2, true), a(2, true)]), 0);
        assert!(!placement_should_continue(vec![a(1, true), a(1, false), a(1, false)]));
    }

    #[test]
    fn level_tests() {
        assert!(level_test_passed(16, 20) && !level_test_passed(15, 20) && !level_test_passed(0, 0));
        let level: Vec<String> = (0..30).map(|i| format!("1-{i}")).collect();
        let learned: Vec<String> = (0..5).map(|i| format!("1-{i}")).collect();
        let ids = level_test_word_ids(level.clone(), learned.clone(), 7);
        assert_eq!(ids.len(), 20);
        assert!(ids[..5].iter().all(|id| learned.contains(id)), "learned words first");
        let mut sorted = ids.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), 20, "no repeats");
        assert_eq!(level_test_word_ids(level[..3].to_vec(), vec![], 1).len(), 3);
        assert_eq!(known_level(0, vec![150, 150, 10], vec![150, 150, 300]), 2);
        assert_eq!(known_level(1, vec![3, 0], vec![150, 150]), 1);
        assert_eq!(known_level(0, vec![], vec![]), 0);
    }
}
