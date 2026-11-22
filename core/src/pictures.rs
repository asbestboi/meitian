//! Profile pictures: the fallback when there is none, and the refund for the emoji avatars they replaced.

/// What shows on the coloured circle: up to two letters, or the first character of a Chinese name.
#[uniffi::export]
pub fn initials(name: String) -> String {
    let name = name.trim();
    let Some(first) = name.chars().next() else { return "?".into() };
    if crate::pinyin::is_hanzi_char(first) {
        return first.to_string();
    }
    let mut letters = name.split(|c: char| !c.is_alphanumeric()).filter_map(|w| w.chars().next());
    let a = letters.next().unwrap_or(first);
    let b = letters.next().filter(|c| !crate::pinyin::is_hanzi_char(*c));
    [Some(a), b].into_iter().flatten().flat_map(char::to_uppercase).collect()
}

const CIRCLES: [&str; 10] =
    ["#E5484D", "#F2711C", "#C98A00", "#4C9A2A", "#0F9D75", "#1B8FC4", "#3D63DD", "#7C4DDB", "#C2298A", "#8D6E63"];

/// The circle's colour, always the same for one player.
#[uniffi::export]
pub fn avatar_color(player_id: String) -> String {
    let h = player_id.bytes().fold(0xcbf2_9ce4_8422_2325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100_0000_01b3));
    CIRCLES[(h >> 32) as usize % CIRCLES.len()].into()
}

/// The emoji avatars the shop sold until 1.13, with their prices.
const RETIRED: [(&str, u32); 20] = [
    ("av.chick", 0), ("av.panda", 60), ("av.cat", 60), ("av.frog", 80), ("av.monkey", 100), ("av.tiger", 120), ("av.fox", 120),
    ("av.dumpling", 150), ("av.boba", 150), ("av.lantern", 200), ("av.unicorn", 250), ("av.dragon", 300), ("av.skull", 140),
    ("av.gorilla", 160), ("av.rat", 90), ("av.oni", 220), ("av.alien", 180), ("av.robot", 180), ("av.cool", 110), ("av.angry", 120),
];

/// Coins to give back for the avatars in a player's collection. The apps also drop them from the collection,
/// so it's only ever paid once.
#[uniffi::export]
pub fn retired_avatar_refund(owned_ids: Vec<String>) -> u32 {
    RETIRED.iter().filter(|(id, _)| owned_ids.iter().any(|o| o == id)).map(|(_, price)| price).sum()
}

/// The collection without retired items.
#[uniffi::export]
pub fn without_retired_avatars(owned_ids: Vec<String>) -> Vec<String> {
    owned_ids.into_iter().filter(|id| !id.starts_with("av.")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initials_of_names() {
        for (name, want) in [("Anna", "A"), ("anna smith", "AS"), ("小明", "小"), ("Anna_99", "A9"), ("  ", "?"), ("🐼", "🐼"), ("éva", "É")] {
            assert_eq!(initials(name.into()), want, "{name}");
        }
    }

    #[test]
    fn colors_are_stable() {
        assert_eq!(avatar_color("u1".into()), avatar_color("u1".into()));
        let seen: std::collections::HashSet<String> = (0..200).map(|i| avatar_color(format!("player-{i}"))).collect();
        assert_eq!(seen.len(), CIRCLES.len());
    }

    #[test]
    fn refund_once() {
        let owned: Vec<String> = ["av.chick", "av.dragon", "av.fox", "fx.fire", "av.unknown"].iter().map(|s| s.to_string()).collect();
        assert_eq!(retired_avatar_refund(owned.clone()), 420);
        let left = without_retired_avatars(owned);
        assert_eq!(left, vec!["fx.fire".to_string()]);
        assert_eq!(retired_avatar_refund(left), 0);
        assert_eq!(retired_avatar_refund(vec!["av.chick".into()]), 0, "the free one");
    }
}
