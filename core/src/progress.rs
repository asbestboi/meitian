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
    if answers.is_empty() || answers.len() % 3 != 0 {
        return true;
    }
    let level = answers[answers.len() - 1].level;
    answers.iter().filter(|a| a.level == level && a.right).count() >= 2
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
}
