//! Battle rules shared by both apps, so an iPhone and an Android phone always agree.

use crate::words::*;

pub const MAX_HP: u32 = 100;
pub const BLITZ_SECONDS: u32 = 45;

/// Damage for a right answer in a duel: faster hits harder (12–22).
#[uniffi::export]
pub fn duel_damage(reaction_ms: u32) -> u32 {
    12 + 4000u32.saturating_sub(reaction_ms) / 400
}

/// Players can only battle with the same swear-word setting.
#[uniffi::export]
pub fn can_match(my_swears: bool, their_swears: bool) -> bool {
    my_swears == their_swears
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum Outcome {
    Win,
    Loss,
    Draw,
}

/// Coins for a finished online match. `bonus` is HP left / 5 (duel) or score (blitz);
/// `streak` is the win streak including this match.
#[uniffi::export]
pub fn match_coins(outcome: Outcome, bonus: u32, streak: u32) -> u32 {
    match outcome {
        Outcome::Win => 40 + bonus + streak.saturating_sub(1).min(5) * 5,
        Outcome::Loss => 10,
        Outcome::Draw => 20,
    }
}

/// Word ids for a battle (bundled words only, so both phones know them): regular words up to the lower player's level, plus the street deck if both
/// players have swears on.
#[uniffi::export]
pub fn battle_pool(level_a: u8, level_b: u8, swears_a: bool, swears_b: bool) -> Vec<String> {
    let level = level_a.min(level_b).max(1);
    let mut ids: Vec<String> = bundled_words().into_iter().filter(|w| w.level <= level).map(|w| w.id).collect();
    if swears_a && swears_b {
        ids.extend(swear_words().into_iter().map(|w| w.id));
    }
    ids
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BattleQuestion {
    pub word_id: String,
    /// 0 = characters → meaning, 1 = meaning → characters.
    pub kind: u8,
    pub option_ids: Vec<String>,
}

/// The host builds the question list once and sends it to the other phone.
#[uniffi::export]
pub fn battle_questions(pool_ids: Vec<String>, count: u32) -> Vec<BattleQuestion> {
    if pool_ids.is_empty() {
        return vec![];
    }
    let mut bag: Vec<String> = Vec::new();
    (0..count)
        .map(|i| {
            if bag.is_empty() {
                bag = pool_ids.clone();
                fastrand::shuffle(&mut bag);
            }
            let id = bag.pop().unwrap();
            BattleQuestion { option_ids: quiz_options(id.clone(), pool_ids.clone()), word_id: id, kind: (i % 2) as u8 }
        })
        .collect()
}

/// Blitz winner: Some(true) = me, Some(false) = them, None = draw.
#[uniffi::export]
pub fn blitz_winner(my_score: u32, their_score: u32) -> Option<bool> {
    if my_score == their_score {
        None
    } else {
        Some(my_score > their_score)
    }
}

/// Swear Sprint: points for a right answer at the current combo (×1 … ×5).
#[uniffi::export]
pub fn sprint_multiplier(combo: u32) -> u32 {
    (1 + combo / 3).min(5)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn damage_range() {
        assert_eq!(duel_damage(0), 22);
        assert_eq!(duel_damage(4000), 12);
        assert_eq!(duel_damage(9000), 12);
    }

    #[test]
    fn coins() {
        assert_eq!(match_coins(Outcome::Win, 10, 1), 50);
        assert_eq!(match_coins(Outcome::Win, 0, 10), 65);
        assert_eq!(match_coins(Outcome::Loss, 99, 0), 10);
    }

    #[test]
    fn pools() {
        let plain = battle_pool(2, 4, true, false);
        assert!(plain.iter().all(|id| !id.starts_with("5-")));
        let street = battle_pool(1, 1, true, true);
        assert!(street.iter().any(|id| id.starts_with("5-")));
        let qs = battle_questions(plain, 40);
        assert_eq!(qs.len(), 40);
        assert!(qs.iter().all(|q| q.option_ids.contains(&q.word_id) && q.option_ids.len() == 4));
    }

    #[test]
    fn matching() {
        assert!(can_match(true, true) && can_match(false, false));
        assert!(!can_match(true, false));
        assert_eq!(sprint_multiplier(0), 1);
        assert_eq!(sprint_multiplier(7), 3);
        assert_eq!(sprint_multiplier(100), 5);
    }
}
