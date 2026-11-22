//! Hearts: a lesson (words, sentence node or story) starts with three, every wrong answer costs one, and
//! at zero the lesson starts over. They reset for every lesson; there is no global meter.

/// Hearts at the start of every lesson.
pub const LESSON_HEARTS: u32 = 3;

#[uniffi::export]
pub fn lesson_hearts() -> u32 {
    LESSON_HEARTS
}

/// Hearts left after a wrong answer.
#[uniffi::export]
pub fn lose_heart(hearts: u32) -> u32 {
    hearts.saturating_sub(1)
}

/// Out of hearts: the attempt is over and its progress and XP are thrown away.
#[uniffi::export]
pub fn lesson_failed(hearts: u32) -> bool {
    hearts == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn three_mistakes_end_the_lesson() {
        let mut h = lesson_hearts();
        assert_eq!(h, 3);
        for left in [2, 1] {
            h = lose_heart(h);
            assert_eq!(h, left);
            assert!(!lesson_failed(h));
        }
        h = lose_heart(h);
        assert!(lesson_failed(h));
        assert_eq!(lose_heart(h), 0, "never below zero");
    }
}
