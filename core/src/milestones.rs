//! Daily XP milestones (Duolingo-style): the daily goal is only the first stop. Every XP earned today
//! fills a bar toward the next milestone, each one hands out bonus XP, and the last one keeps
//! repeating, so there's always another one to reach no matter how long you practice.

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Milestone {
    /// 1-based position in the day's ladder.
    pub index: u32,
    /// Today's XP needed to reach it.
    pub xp: u32,
    pub title: String,
    pub emoji: String,
    /// Bonus XP for reaching it (doesn't count toward later milestones).
    pub bonus: u32,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct MilestoneProgress {
    /// Milestones reached so far today.
    pub reached: u32,
    /// The next one to aim for.
    pub next: Milestone,
    /// XP of the previous milestone (0 before the first), for drawing the bar.
    pub from_xp: u32,
    /// 0.0–1.0 from the previous milestone to the next.
    pub progress: f64,
}

const LADDER: [(u32, &str, &str, u32); 6] = [
    (30, "warmed up", "🔥", 5),
    (80, "on a roll", "⚡️", 10),
    (150, "unstoppable", "🚀", 15),
    (250, "word machine", "🤖", 20),
    (400, "legend", "👑", 30),
    (600, "dragon mode", "🐉", 40),
];
/// After the ladder: another "dragon mode ×n" every 250 XP.
const REPEAT_EVERY: u32 = 250;

/// The `index`th milestone of the day (1-based; goes on forever).
#[uniffi::export]
pub fn milestone_at(index: u32) -> Milestone {
    let i = index.max(1);
    if let Some(&(xp, title, emoji, bonus)) = LADDER.get(i as usize - 1) {
        return Milestone {
            index: i,
            xp,
            title: title.into(),
            emoji: emoji.into(),
            bonus,
        };
    }
    let (last_xp, title, emoji, bonus) = LADDER[LADDER.len() - 1];
    let extra = i - LADDER.len() as u32;
    Milestone {
        index: i,
        xp: last_xp + extra * REPEAT_EVERY,
        title: format!("{title} ×{}", extra + 1),
        emoji: emoji.into(),
        bonus,
    }
}

/// How many milestones `xp_today` has reached.
#[uniffi::export]
pub fn milestones_reached(xp_today: u32) -> u32 {
    let mut n = 0;
    while milestone_at(n + 1).xp <= xp_today {
        n += 1;
    }
    n
}

/// Where today's XP stands on the ladder.
#[uniffi::export]
pub fn milestone_progress(xp_today: u32) -> MilestoneProgress {
    let reached = milestones_reached(xp_today);
    let next = milestone_at(reached + 1);
    let from_xp = if reached == 0 {
        0
    } else {
        milestone_at(reached).xp
    };
    let progress = (xp_today - from_xp) as f64 / (next.xp - from_xp) as f64;
    MilestoneProgress {
        reached,
        next,
        from_xp,
        progress,
    }
}

/// Milestones newly reached when today's XP (bonuses excluded) goes from `before` to `after`.
#[uniffi::export]
pub fn milestones_crossed(before: u32, after: u32) -> Vec<Milestone> {
    (milestones_reached(before) + 1..=milestones_reached(after))
        .map(milestone_at)
        .collect()
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LessonPath {
    /// The lesson the learner is on within the level (1-based).
    pub lesson: u32,
    pub lessons: u32,
    /// 0.0–1.0 through the level.
    pub progress: f64,
}

/// A level's words split into lessons of `lesson_size` new words, like stops on a path.
#[uniffi::export]
pub fn lesson_path(learned: u32, total: u32, lesson_size: u32) -> LessonPath {
    let size = lesson_size.max(1);
    let lessons = total.div_ceil(size).max(1);
    let lesson = (learned / size + 1).min(lessons);
    let progress = if total == 0 {
        1.0
    } else {
        (learned.min(total)) as f64 / total as f64
    };
    LessonPath {
        lesson,
        lessons,
        progress,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ladder() {
        assert_eq!(milestones_reached(0), 0);
        assert_eq!(milestones_reached(29), 0);
        assert_eq!(milestones_reached(30), 1);
        assert_eq!(milestones_reached(600), 6);
        assert_eq!(milestone_at(7).xp, 850);
        assert_eq!(milestone_at(8).title, "dragon mode ×3");
        assert_eq!(milestones_reached(5000), 6 + (5000 - 600) / 250);
        let p = milestone_progress(55);
        assert_eq!((p.reached, p.next.xp, p.from_xp), (1, 80, 30));
        assert!((p.progress - 0.5).abs() < 1e-9);
        let crossed: Vec<u32> = milestones_crossed(20, 160).iter().map(|m| m.xp).collect();
        assert_eq!(crossed, vec![30, 80, 150]);
        assert!(milestones_crossed(160, 160).is_empty());
        assert!(milestones_crossed(200, 100).is_empty(), "never backwards");
    }

    #[test]
    fn path() {
        assert_eq!(
            lesson_path(0, 150, 5),
            LessonPath {
                lesson: 1,
                lessons: 30,
                progress: 0.0
            }
        );
        assert_eq!(lesson_path(7, 150, 5).lesson, 2);
        assert_eq!(lesson_path(150, 150, 5).lesson, 30);
        assert_eq!(lesson_path(0, 0, 0).lessons, 1);
    }
}
