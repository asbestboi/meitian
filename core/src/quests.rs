//! Daily quests (three small goals a day that pay Arena coins) and streak freezes.

use crate::challenge::day_seed;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum QuestKind {
    EarnXp,
    Review,
    Story,
    Lesson,
    Perfect,
    Sentences,
    ListenSpeak,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Quest {
    /// Stable within the day ("2026-11-19-0"), for remembering claims.
    pub id: String,
    pub kind: QuestKind,
    pub title: String,
    pub emoji: String,
    pub target: u32,
    /// Coins for finishing it.
    pub reward: u32,
}

/// What the learner has done today (counted by the apps).
#[derive(Debug, Clone, Default, PartialEq, uniffi::Record)]
pub struct DayStats {
    pub xp: u32,
    /// Review answers and other practice activity.
    pub reviewed: u32,
    /// Stories or chats read for the first time.
    pub stories: u32,
    /// Lessons finished (today's words count as one).
    pub lessons: u32,
    /// Lesson quizzes with every answer right.
    pub perfect: u32,
    /// Sentence lessons finished.
    pub sentences: u32,
    /// Listening or speaking practice rounds finished.
    pub listen_speak: u32,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct QuestStatus {
    pub quest: Quest,
    /// Capped at the target.
    pub progress: u32,
    pub done: bool,
}

fn template(kind: QuestKind, step: u32) -> (String, &'static str, u32, u32) {
    // (title, emoji, target, reward)
    match kind {
        QuestKind::EarnXp => {
            let t = [40, 60, 90][step as usize % 3];
            (format!("earn {t} XP"), "⭐", t, [10, 15, 20][step as usize % 3])
        }
        QuestKind::Review => {
            let t = [10, 15, 25][step as usize % 3];
            (format!("answer {t} practice questions"), "🃏", t, [10, 15, 20][step as usize % 3])
        }
        QuestKind::Story => ("read a story or chat".into(), "📖", 1, 15),
        QuestKind::Lesson => {
            let t = 1 + step % 2;
            (if t == 1 { "finish a lesson".into() } else { "finish 2 lessons".into() }, "🎯", t, 10 + 5 * t)
        }
        QuestKind::Perfect => ("finish a lesson with no mistakes".into(), "💯", 1, 20),
        QuestKind::Sentences => ("do a sentence lesson".into(), "✍️", 1, 15),
        QuestKind::ListenSpeak => ("do a listening or speaking round".into(), "🎧", 1, 15),
    }
}

const OTHERS: [QuestKind; 6] = [
    QuestKind::Review,
    QuestKind::Story,
    QuestKind::Lesson,
    QuestKind::Perfect,
    QuestKind::Sentences,
    QuestKind::ListenSpeak,
];

/// Today's three quests: an XP quest plus two different others, the same all day on both platforms.
#[uniffi::export]
pub fn daily_quests(day_key: String) -> Vec<Quest> {
    let seed = day_seed(day_key.clone());
    let mut rng = fastrand::Rng::with_seed(seed as u64);
    let mut others = OTHERS.to_vec();
    rng.shuffle(&mut others);
    let step = seed / 7;
    std::iter::once(QuestKind::EarnXp)
        .chain(others.into_iter().take(2))
        .enumerate()
        .map(|(i, kind)| {
            let (title, emoji, target, reward) = template(kind, step + i as u32);
            Quest { id: format!("{day_key}-{i}"), kind, title, emoji: emoji.into(), target, reward }
        })
        .collect()
}

#[uniffi::export]
pub fn quest_status(quest: Quest, stats: DayStats) -> QuestStatus {
    let value = match quest.kind {
        QuestKind::EarnXp => stats.xp,
        QuestKind::Review => stats.reviewed,
        QuestKind::Story => stats.stories,
        QuestKind::Lesson => stats.lessons,
        QuestKind::Perfect => stats.perfect,
        QuestKind::Sentences => stats.sentences,
        QuestKind::ListenSpeak => stats.listen_speak,
    };
    QuestStatus { progress: value.min(quest.target), done: value >= quest.target, quest }
}

/// Extra coins for finishing all three quests in a day.
#[uniffi::export]
pub fn quests_all_done_bonus() -> u32 {
    20
}

/// Price of a streak freeze in coins, and how many can be held at once.
#[uniffi::export]
pub fn streak_freeze_price() -> u32 {
    200
}

#[uniffi::export]
pub fn streak_freeze_max() -> u32 {
    2
}

/// Current streak where frozen days keep it alive but don't add to it (like Duolingo).
#[uniffi::export]
pub fn streak_with_freezes(active_days: Vec<i64>, frozen_days: Vec<i64>, today: i64) -> u32 {
    let active: std::collections::HashSet<i64> = active_days.into_iter().collect();
    let frozen: std::collections::HashSet<i64> = frozen_days.into_iter().collect();
    let mut day = if active.contains(&today) { today } else { today - 1 };
    let mut n = 0;
    while active.contains(&day) || frozen.contains(&day) {
        if active.contains(&day) {
            n += 1;
        }
        day -= 1;
    }
    n
}

/// Missed days (most recent first) that freezes should cover so the streak survives, given `owned`
/// freezes. Empty when nothing was missed, there's no streak to save, or too many days were missed
/// (then the streak is lost and the freezes are kept).
#[uniffi::export]
pub fn freezes_to_use(active_days: Vec<i64>, frozen_days: Vec<i64>, today: i64, owned: u32) -> Vec<i64> {
    let active: std::collections::HashSet<i64> = active_days.iter().copied().collect();
    let frozen: std::collections::HashSet<i64> = frozen_days.iter().copied().collect();
    let mut missed = Vec::new();
    let mut day = today - 1;
    while !active.contains(&day) && !frozen.contains(&day) {
        missed.push(day);
        day -= 1;
        if missed.len() as u32 > owned {
            return Vec::new();
        }
    }
    if missed.is_empty() || streak_with_freezes(active_days, frozen_days, day) == 0 {
        return Vec::new();
    }
    missed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quests() {
        for d in 1..=28 {
            let q = daily_quests(format!("2026-11-{d:02}"));
            assert_eq!(q.len(), 3);
            assert_eq!(q[0].kind, QuestKind::EarnXp);
            assert_ne!(q[1].kind, q[2].kind);
            assert!(q.iter().all(|x| x.target > 0 && x.reward > 0));
        }
        assert_eq!(daily_quests("2026-11-19".into()), daily_quests("2026-11-19".into()));
        let q = Quest { id: "x".into(), kind: QuestKind::Review, title: String::new(), emoji: String::new(), target: 10, reward: 10 };
        let s = quest_status(q.clone(), DayStats { reviewed: 4, ..Default::default() });
        assert_eq!((s.progress, s.done), (4, false));
        let s = quest_status(q, DayStats { reviewed: 30, ..Default::default() });
        assert_eq!((s.progress, s.done), (10, true));
    }

    #[test]
    fn freezes() {
        // active 10..=12, missed 13, today 14
        let active = vec![10, 11, 12];
        assert_eq!(freezes_to_use(active.clone(), vec![], 14, 1), vec![13]);
        assert_eq!(freezes_to_use(active.clone(), vec![], 14, 0), Vec::<i64>::new(), "no freeze, streak lost");
        assert_eq!(freezes_to_use(active.clone(), vec![], 15, 1), Vec::<i64>::new(), "two missed, one freeze");
        assert_eq!(freezes_to_use(active.clone(), vec![], 15, 2), vec![14, 13]);
        assert!(freezes_to_use(active.clone(), vec![], 13, 2).is_empty(), "yesterday was active");
        assert!(freezes_to_use(vec![], vec![], 13, 2).is_empty(), "no streak to save");
        assert_eq!(streak_with_freezes(active.clone(), vec![13], 14), 3, "frozen day keeps it, doesn't add");
        assert_eq!(streak_with_freezes(vec![10, 11, 12, 14], vec![13], 14), 4);
        assert_eq!(streak_with_freezes(active, vec![], 14), 0);
    }
}
