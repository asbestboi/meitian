//! Arenas: the scenery behind the learning path and the battles. Calm nature for beginners, darker and more
//! hellish as the material gets harder. Everything is drawn in code by the apps from the numbers here.

use crate::effects::{EffectSpec, ParticleShape};

pub const ARENA_TIERS: u32 = 6;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ArenaTheme {
    pub id: String,
    pub name_zh: String,
    pub pinyin: String,
    pub name_en: String,
    /// 1 (spring meadow) – 6 (the gates of hell).
    pub tier: u32,
    /// Rank badge.
    pub emoji: String,
    /// 0–1: how far into the level the learner is. Livelier particles the further they get.
    pub intensity: f32,
}

/// The arena for a learner's HSK level and learn-path unit. Levels above 6 stay in hell.
#[uniffi::export]
pub fn arena_for(level: u8, unit: u32) -> ArenaTheme {
    let tier = (level.max(1) as u32).min(ARENA_TIERS);
    let (id, name_zh, pinyin, name_en, emoji) = match tier {
        1 => ("meadow", "春日草地", "chūnrì cǎodì", "Spring Meadow", "🌸"),
        2 => ("bamboo", "竹林", "zhúlín", "Bamboo Forest", "🎋"),
        3 => ("temple", "云山古寺", "yúnshān gǔsì", "Misty Temple Mountains", "🏔️"),
        4 => ("volcano", "火山荒原", "huǒshān huāngyuán", "Volcanic Badlands", "🌋"),
        5 => ("lava", "熔岩之地", "róngyán zhī dì", "Lava Fields", "🔥"),
        _ => ("hell", "地狱之门", "dìyù zhī mén", "Gates of Hell", "😈"),
    };
    ArenaTheme {
        id: id.into(),
        name_zh: name_zh.into(),
        pinyin: pinyin.into(),
        name_en: name_en.into(),
        tier,
        emoji: emoji.into(),
        intensity: (unit.saturating_sub(1) as f32 / 12.0).min(1.0),
    }
}

/// The arena the learner just crossed into, if it's a new one (`seen_tier` = the highest one shown; 0 = never).
/// Someone whose save is older than arenas doesn't get a reveal for where they already are.
#[uniffi::export]
pub fn new_arena(level: u8, seen_tier: u32) -> Option<ArenaTheme> {
    let a = arena_for(level, 1);
    (seen_tier > 0 && a.tier > seen_tier).then_some(a)
}

/// One silhouette, back to front.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ArenaLayer {
    pub color_light: String,
    pub color_dark: String,
    /// Heights from left to right, as fractions of the view's height from the bottom.
    pub heights: Vec<f32>,
    /// How much it moves with scrolling (0 = still, far away).
    pub parallax: f32,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ArenaLook {
    /// Sky gradient, top to bottom.
    pub sky_light: Vec<String>,
    pub sky_dark: Vec<String>,
    pub layers: Vec<ArenaLayer>,
    /// Falling petals, leaves, mist, ashes, embers or fire.
    pub particles: EffectSpec,
    /// Particles rise from the bottom instead of falling from the top.
    pub rising: bool,
}

const POINTS: usize = 96;

/// Smooth repeatable noise, 0–1.
fn wobble(x: f32, seed: f32) -> f32 {
    let s = (x * 2.1 + seed).sin() + 0.5 * (x * 4.7 + seed * 2.3).sin() + 0.25 * (x * 9.3 + seed * 4.1).sin();
    (s / 1.75 + 1.0) / 2.0
}

/// Pointed noise, 0–1 (mountain ridges).
fn ridge(x: f32, seed: f32) -> f32 {
    1.0 - (2.0 * wobble(x, seed) - 1.0).abs()
}

fn heights(f: impl Fn(f32) -> f32) -> Vec<f32> {
    (0..=POINTS).map(|i| f(i as f32 / POINTS as f32).clamp(0.0, 1.0)).collect()
}

fn layer(color_light: &str, color_dark: &str, parallax: f32, f: impl Fn(f32) -> f32) -> ArenaLayer {
    ArenaLayer { color_light: color_light.into(), color_dark: color_dark.into(), heights: heights(f), parallax }
}

/// Upright stalks (bamboo) or spikes of different heights on a low ground.
fn stalks(x: f32, count: f32, width: f32, lo: f32, hi: f32, seed: f32, pointed: bool) -> f32 {
    let cell = x * count;
    let i = cell.floor();
    let at = (cell - i - 0.5).abs() * 2.0;
    let h = lo + (hi - lo) * wobble(i * 3.7, seed);
    if at > width {
        0.06 + 0.02 * wobble(x * 3.0, seed)
    } else if pointed {
        0.06 + h * (1.0 - at / width)
    } else {
        h
    }
}

fn drift(shape: ParticleShape, glyphs: &[&str], colors: &[&str]) -> EffectSpec {
    EffectSpec {
        id: "arena".into(),
        shape,
        glyphs: glyphs.iter().map(|s| s.to_string()).collect(),
        colors: colors.iter().map(|s| s.to_string()).collect(),
        burst: 0,
        rate: 2.5,
        lifetime: 9.0,
        speed: 24.0,
        spread: 60.0,
        gravity: 6.0,
        size: 8.0,
        spin: 50.0,
        glow: false,
        projectile: String::new(),
        shake: 0.0,
        flash: String::new(),
        sound: String::new(),
    }
}

/// What to draw for an arena.
#[uniffi::export]
pub fn arena_look(theme: ArenaTheme) -> ArenaLook {
    use ParticleShape::*;
    let sky = |c: &[&str]| c.iter().map(|s| s.to_string()).collect::<Vec<_>>();
    let mut look = match theme.tier {
        1 => ArenaLook {
            sky_light: sky(&["#CFEBFF", "#EAF6EE", "#F6F5E6"]),
            sky_dark: sky(&["#0B1626", "#10201C", "#131A12"]),
            layers: vec![
                layer("#CBE7C2", "#15281C", 0.05, |x| 0.22 + 0.10 * wobble(x * 2.2, 0.4)),
                layer("#AEDBA0", "#1A3320", 0.10, |x| 0.14 + 0.09 * wobble(x * 2.8, 2.1)),
                layer("#8FCB83", "#204027", 0.18, |x| 0.07 + 0.06 * wobble(x * 3.4, 4.0)),
            ],
            particles: EffectSpec { rate: 2.0, ..drift(Glyph, &["🌸", "❀"], &["#FF9EC6", "#FFC1DA"]) },
            rising: false,
        },
        2 => ArenaLook {
            sky_light: sky(&["#DDF3D8", "#EAF5DD", "#F3F4E2"]),
            sky_dark: sky(&["#08160F", "#0D1D13", "#101A10"]),
            layers: vec![
                layer("#CBE6BD", "#11281A", 0.04, |x| stalks(x, 17.0, 0.34, 0.50, 0.92, 1.0, false)),
                layer("#A9D398", "#16341F", 0.10, |x| stalks(x, 11.0, 0.30, 0.35, 0.75, 3.0, false)),
                layer("#86BC77", "#1C4126", 0.18, |x| 0.07 + 0.05 * wobble(x * 5.0, 5.0)),
            ],
            particles: EffectSpec { rate: 1.8, spin: 90.0, ..drift(Glyph, &["🍃", "🍂"], &["#7DBB6B"]) },
            rising: false,
        },
        3 => ArenaLook {
            sky_light: sky(&["#DCE4F0", "#E9EBF1", "#F1EFEB"]),
            sky_dark: sky(&["#0E1320", "#141926", "#171A22"]),
            layers: vec![
                layer("#CBD5E3", "#1B2333", 0.04, |x| 0.16 + 0.34 * ridge(x * 3.1, 0.7)),
                layer("#AEBBD0", "#212B3E", 0.09, |x| 0.10 + 0.24 * ridge(x * 4.0, 2.9)),
                // a temple roof on the ridge
                layer("#8C9AB2", "#2A354B", 0.16, |x| {
                    let ground = 0.06 + 0.10 * ridge(x * 4.6, 5.2);
                    let d = (x - 0.72).abs();
                    if d < 0.09 {
                        ground.max(0.16 + 0.10 * (1.0 - d / 0.09) - if d > 0.06 { 0.015 } else { 0.0 })
                    } else {
                        ground
                    }
                }),
            ],
            particles: EffectSpec { rate: 0.7, lifetime: 14.0, size: 15.0, speed: 12.0, gravity: 0.0, spin: 0.0, ..drift(Glyph, &["☁️"], &["#FFFFFF"]) },
            rising: false,
        },
        4 => ArenaLook {
            sky_light: sky(&["#FFD9A8", "#FFC08A", "#F6B58A"]),
            sky_dark: sky(&["#23100A", "#33160B", "#2B140D"]),
            layers: vec![
                // the volcano, with its crater
                layer("#D9A07A", "#3A1C12", 0.04, |x| {
                    let d = (x - 0.38).abs();
                    if d < 0.07 { 0.50 + 0.03 * (d / 0.07) } else { 0.53 - 1.05 * (d - 0.07) }.max(0.16 + 0.04 * wobble(x * 6.0, 1.0))
                }),
                layer("#B97E5C", "#4A2416", 0.10, |x| 0.10 + 0.16 * ridge(x * 5.2, 2.0)),
                layer("#8F5A43", "#2E150D", 0.18, |x| 0.05 + 0.10 * ridge(x * 7.5, 4.4)),
            ],
            particles: EffectSpec { rate: 3.0, size: 4.0, spin: 0.0, ..drift(Dot, &[], &["#8C7A70", "#6E5F57", "#B09A8C"]) },
            rising: false,
        },
        5 => ArenaLook {
            sky_light: sky(&["#FFB38A", "#FF9166", "#F0785A"]),
            sky_dark: sky(&["#1E0706", "#3A0D07", "#4A1408"]),
            layers: vec![
                layer("#C9553B", "#4E1209", 0.04, |x| 0.16 + 0.22 * ridge(x * 4.4, 0.2)),
                layer("#FF8A3D", "#B5360E", 0.08, |x| 0.15 + 0.02 * wobble(x * 9.0, 1.7)), // the glowing lava
                layer("#6E2A20", "#210A07", 0.18, |x| 0.04 + 0.15 * ridge(x * 9.0, 3.3)),
            ],
            particles: EffectSpec { rate: 5.0, lifetime: 6.0, size: 4.0, speed: 40.0, gravity: -10.0, spin: 0.0, glow: true, ..drift(Dot, &[], &["#FFD23F", "#FF8A1F", "#FF5A1F"]) },
            rising: true,
        },
        _ => ArenaLook {
            sky_light: sky(&["#7A1A1A", "#A32618", "#C93A1B"]),
            sky_dark: sky(&["#0A0202", "#240404", "#4A0A06"]),
            layers: vec![
                layer("#5C1210", "#2B0605", 0.04, |x| 0.10 + stalks(x, 14.0, 0.8, 0.10, 0.34, 2.0, true)),
                // the gate: two towers and a double roof
                layer("#2E0808", "#140303", 0.09, |x| {
                    let d = (x - 0.5).abs();
                    if (0.17..0.24).contains(&d) {
                        0.52
                    } else if d < 0.30 {
                        if d < 0.17 { 0.10 } else { 0.46 - 0.5 * (d - 0.24) }
                    } else {
                        0.08 + stalks(x, 22.0, 0.7, 0.02, 0.12, 5.0, true)
                    }
                }),
                layer("#1A0505", "#0A0101", 0.18, |x| stalks(x, 30.0, 0.9, 0.02, 0.09, 8.0, true)),
            ],
            particles: EffectSpec { rate: 9.0, lifetime: 4.0, size: 9.0, speed: 60.0, gravity: -26.0, spin: 0.0, glow: true, ..drift(Dot, &[], &["#FFD23F", "#FF6A1A", "#FF2E1F", "#C9140A"]) },
            rising: true,
        },
    };
    look.particles.rate *= 0.6 + 0.8 * theme.intensity;
    look
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiers_follow_the_level() {
        let tiers: Vec<u32> = (0..=9).map(|l| arena_for(l, 1).tier).collect();
        assert_eq!(tiers, vec![1, 1, 2, 3, 4, 5, 6, 6, 6, 6]);
        let ids: std::collections::HashSet<String> = (1..=6).map(|l| arena_for(l, 1).id).collect();
        assert_eq!(ids.len(), 6);
        assert_eq!(arena_for(6, 1).name_zh, "地狱之门");
        assert_eq!(arena_for(1, 1).intensity, 0.0);
        assert!(arena_for(1, 5).intensity > 0.3 && arena_for(1, 99).intensity == 1.0);
    }

    #[test]
    fn reveals() {
        assert_eq!(new_arena(2, 1).unwrap().id, "bamboo");
        assert!(new_arena(2, 2).is_none() && new_arena(1, 4).is_none(), "never twice, never backwards");
        assert!(new_arena(4, 0).is_none(), "an old save starts where it is");
        assert!(new_arena(8, 6).is_none());
    }

    #[test]
    fn every_arena_can_be_drawn() {
        for level in 1..=6 {
            let a = arena_for(level, 3);
            let look = arena_look(a.clone());
            assert_eq!(look.layers.len(), 3, "{}", a.id);
            for l in &look.layers {
                assert_eq!(l.heights.len(), POINTS + 1);
                assert!(l.heights.iter().all(|h| (0.0..=1.0).contains(h)));
                let max = l.heights.iter().cloned().fold(0.0f32, f32::max);
                assert!(max > 0.04, "{} has an empty layer", a.id);
            }
            for c in look.sky_light.iter().chain(&look.sky_dark).chain(&look.particles.colors).chain(look.layers.iter().flat_map(|l| [&l.color_light, &l.color_dark])) {
                assert!(c.len() == 7 && c.starts_with('#'), "{c}");
            }
            assert!(look.particles.rate > 0.0);
        }
        assert!(arena_look(arena_for(6, 13)).particles.rate > arena_look(arena_for(6, 1)).particles.rate);
    }
}
