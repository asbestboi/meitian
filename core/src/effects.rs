//! Particle effect recipes for hit effects and auras. One table, so iPhone and Android draw the same thing.
//! The apps own the renderers (SwiftUI Canvas / Compose Canvas); this only says what to draw.

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ParticleShape {
    /// Draw one of `glyphs` (emoji / characters).
    Glyph,
    /// Soft round dot (glows with additive blending).
    Dot,
    /// Short bright line along the direction of travel (sparks, rain).
    Streak,
    /// Jagged lightning bolt between attacker and target.
    Bolt,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct EffectSpec {
    pub id: String,
    pub shape: ParticleShape,
    pub glyphs: Vec<String>,
    /// "#RRGGBB" colors; particles pick one at random.
    pub colors: Vec<String>,
    /// Particles in the impact burst.
    pub burst: u32,
    /// Particles per second while the projectile flies (trail) or the aura idles.
    pub rate: f32,
    /// Seconds a particle lives.
    pub lifetime: f32,
    /// Initial speed in points per second.
    pub speed: f32,
    /// Spread of the burst in degrees (360 = all around).
    pub spread: f32,
    /// Downward acceleration in points/s² (negative floats up: fire, hearts).
    pub gravity: f32,
    /// Base particle size in points.
    pub size: f32,
    /// Spin in degrees per second.
    pub spin: f32,
    /// Additive glow blending.
    pub glow: bool,
    /// Projectile glyph that flies from attacker to target ("" = none, impact only).
    pub projectile: String,
    /// Screen shake strength in points.
    pub shake: f32,
    /// Full-screen flash color ("" = none).
    pub flash: String,
    /// Impact sound (`hit_sound_pcm`), one per hit effect. Empty for auras.
    pub sound: String,
}

/// Every hit effect cosmetic.
pub const HIT_EFFECTS: [&str; 17] = [
    "fx.boom", "fx.fire", "fx.zap", "fx.envelope", "fx.blossom", "fx.dragon", "fx.bomb", "fx.glove", "fx.firecracker",
    "fx.tomato", "fx.mic", "fx.poop", "fx.glitch", "fx.money", "fx.snow", "fx.hearts", "fx.chrome",
];

fn spec(id: &str, shape: ParticleShape, glyphs: &[&str], colors: &[&str]) -> EffectSpec {
    EffectSpec {
        id: id.into(),
        shape,
        glyphs: glyphs.iter().map(|s| s.to_string()).collect(),
        colors: colors.iter().map(|s| s.to_string()).collect(),
        burst: 28,
        rate: 40.0,
        lifetime: 0.9,
        speed: 260.0,
        spread: 360.0,
        gravity: 300.0,
        size: 14.0,
        spin: 0.0,
        glow: false,
        projectile: String::new(),
        shake: 6.0,
        flash: String::new(),
        sound: String::new(),
    }
}

/// The recipe for a hit effect cosmetic (`fx.*`). Unknown ids fall back to the default boom.
#[uniffi::export]
pub fn effect_spec(id: String) -> EffectSpec {
    use ParticleShape::*;
    let mut s = match id.as_str() {
        "fx.fire" => EffectSpec {
            burst: 46, rate: 90.0, lifetime: 0.8, speed: 160.0, gravity: -420.0, size: 18.0, glow: true,
            projectile: "🔥".into(), shake: 8.0, flash: "#FF6A1A".into(),
            ..spec(&id, Dot, &[], &["#FFD23F", "#FF8A1F", "#FF3B1F", "#FFF1A8"])
        },
        "fx.zap" => EffectSpec {
            burst: 30, rate: 0.0, lifetime: 0.45, speed: 520.0, gravity: 0.0, size: 3.0, glow: true,
            shake: 12.0, flash: "#BFE9FF".into(),
            ..spec(&id, Bolt, &[], &["#E8F7FF", "#7FD3FF", "#C6FF3D"])
        },
        "fx.envelope" => EffectSpec {
            burst: 22, rate: 20.0, lifetime: 1.4, speed: 300.0, gravity: 520.0, size: 22.0, spin: 220.0,
            projectile: "🧧".into(), shake: 4.0,
            ..spec(&id, Glyph, &["🧧", "🪙", "💰"], &["#FF3B30"])
        },
        "fx.blossom" => EffectSpec {
            burst: 40, rate: 30.0, lifetime: 1.8, speed: 140.0, gravity: 60.0, size: 16.0, spin: 120.0,
            projectile: "🌸".into(), shake: 2.0,
            ..spec(&id, Glyph, &["🌸", "💮", "🌺"], &["#FFB7D5"])
        },
        "fx.dragon" => EffectSpec {
            burst: 60, rate: 120.0, lifetime: 1.0, speed: 300.0, gravity: -120.0, size: 20.0, glow: true,
            projectile: "🐉".into(), shake: 16.0, flash: "#FFD23F".into(),
            ..spec(&id, Dot, &[], &["#FFD23F", "#FF3B1F", "#3DFFB0", "#FFFFFF"])
        },
        "fx.bomb" => EffectSpec {
            burst: 50, rate: 30.0, lifetime: 0.7, speed: 420.0, gravity: 200.0, size: 12.0, glow: true,
            projectile: "💣".into(), shake: 18.0, flash: "#FFFFFF".into(),
            ..spec(&id, Streak, &[], &["#FFFFFF", "#FFD23F", "#FF6A1A", "#888888"])
        },
        "fx.glove" => EffectSpec {
            burst: 18, rate: 0.0, lifetime: 0.6, speed: 360.0, gravity: 0.0, size: 20.0,
            projectile: "🥊".into(), shake: 14.0,
            ..spec(&id, Glyph, &["⭐️", "💫", "✨"], &["#FFD23F"])
        },
        "fx.firecracker" => EffectSpec {
            burst: 70, rate: 60.0, lifetime: 0.6, speed: 460.0, gravity: 260.0, size: 3.0, glow: true,
            projectile: "🧨".into(), shake: 10.0, flash: "#FF3B30".into(),
            ..spec(&id, Streak, &[], &["#FF3B30", "#FFD23F", "#FFFFFF"])
        },
        "fx.tomato" => EffectSpec {
            burst: 34, rate: 10.0, lifetime: 0.9, speed: 280.0, gravity: 700.0, size: 10.0,
            projectile: "🍅".into(), shake: 5.0,
            ..spec(&id, Dot, &[], &["#E5261F", "#B3120D", "#FF6B5E"])
        },
        "fx.mic" => EffectSpec {
            burst: 24, rate: 0.0, lifetime: 1.2, speed: 220.0, gravity: -80.0, size: 20.0, spin: 60.0,
            projectile: "🎤".into(), shake: 9.0,
            ..spec(&id, Glyph, &["🎵", "🎶", "✦"], &["#C6FF3D"])
        },
        "fx.poop" => EffectSpec {
            burst: 20, rate: 14.0, lifetime: 1.0, speed: 260.0, gravity: 600.0, size: 22.0, spin: 200.0,
            projectile: "💩".into(), shake: 6.0,
            ..spec(&id, Glyph, &["💩", "🪰"], &["#7A4A1E"])
        },
        "fx.glitch" => EffectSpec {
            burst: 36, rate: 50.0, lifetime: 0.5, speed: 200.0, gravity: 0.0, size: 14.0,
            projectile: "👾".into(), shake: 10.0, flash: "#FF3DA8".into(),
            ..spec(&id, Glyph, &["▓", "▒", "░", "█"], &["#FF3DA8", "#3DFFF0", "#C6FF3D"])
        },
        "fx.money" => EffectSpec {
            burst: 30, rate: 40.0, lifetime: 1.8, speed: 220.0, gravity: 260.0, size: 22.0, spin: 160.0,
            projectile: "💸".into(), shake: 4.0,
            ..spec(&id, Glyph, &["💸", "💵", "💴"], &["#3DD68C"])
        },
        "fx.snow" => EffectSpec {
            burst: 50, rate: 40.0, lifetime: 2.0, speed: 120.0, gravity: 40.0, size: 14.0, spin: 90.0,
            projectile: "❄️".into(), shake: 3.0, flash: "#E8F7FF".into(),
            ..spec(&id, Glyph, &["❄️", "✦", "·"], &["#E8F7FF"])
        },
        "fx.hearts" => EffectSpec {
            burst: 30, rate: 30.0, lifetime: 1.6, speed: 180.0, gravity: -160.0, size: 20.0, spin: 30.0,
            projectile: "💘".into(), shake: 2.0,
            ..spec(&id, Glyph, &["💖", "💗", "💕"], &["#FF3DA8"])
        },
        "fx.chrome" => EffectSpec {
            burst: 54, rate: 60.0, lifetime: 0.9, speed: 300.0, gravity: 0.0, size: 9.0, glow: true,
            projectile: "💿".into(), shake: 7.0, flash: "#E6F4FF".into(),
            ..spec(&id, Dot, &[], &["#CCF2FF", "#F9CCFF", "#D9FFCC", "#CCD9FF", "#FFFFFF"])
        },
        // fx.boom and anything unknown
        _ => EffectSpec {
            burst: 36, rate: 0.0, lifetime: 0.7, speed: 340.0, gravity: 120.0, size: 10.0, glow: true,
            shake: 8.0,
            ..spec("fx.boom", Dot, &[], &["#FFFFFF", "#FFD23F", "#FF6A1A"])
        },
    };
    if s.id != "fx.boom" {
        s.id = id;
    }
    s.sound = s.id.trim_start_matches("fx.").to_string();
    s
}

/// Idle aura recipes (`au.*` cosmetics) drawn around the avatar. `None` for "no aura".
#[uniffi::export]
pub fn aura_spec(id: String) -> Option<EffectSpec> {
    use ParticleShape::*;
    let base = |shape, glyphs: &[&str], colors: &[&str]| EffectSpec {
        burst: 0, rate: 10.0, lifetime: 1.6, speed: 30.0, spread: 360.0, gravity: -30.0, size: 10.0, shake: 0.0,
        ..spec(&id, shape, glyphs, colors)
    };
    Some(match id.as_str() {
        "au.flame" => EffectSpec { rate: 26.0, gravity: -90.0, lifetime: 0.9, size: 12.0, glow: true, ..base(Dot, &[], &["#FFD23F", "#FF8A1F", "#FF3B1F"]) },
        "au.sparkle" => EffectSpec { rate: 6.0, gravity: 0.0, spin: 90.0, size: 12.0, ..base(Glyph, &["✦", "✧"], &["#C6FF3D", "#FFFFFF"]) },
        "au.hearts" => EffectSpec { rate: 4.0, size: 14.0, ..base(Glyph, &["💗", "💕"], &["#FF3DA8"]) },
        "au.snow" => EffectSpec { rate: 6.0, gravity: 20.0, spin: 60.0, ..base(Glyph, &["❄️", "·"], &["#E8F7FF"]) },
        "au.money" => EffectSpec { rate: 3.0, gravity: 60.0, spin: 90.0, size: 14.0, ..base(Glyph, &["💸", "💵"], &["#3DD68C"]) },
        "au.chrome" => EffectSpec { rate: 18.0, gravity: 0.0, size: 6.0, glow: true, ..base(Dot, &[], &["#CCF2FF", "#F9CCFF", "#D9FFCC", "#FFFFFF"]) },
        "au.glitch" => EffectSpec { rate: 10.0, gravity: 0.0, lifetime: 0.4, ..base(Glyph, &["▓", "░"], &["#FF3DA8", "#3DFFF0"]) },
        "au.notes" => EffectSpec { rate: 4.0, gravity: -40.0, spin: 40.0, size: 14.0, ..base(Glyph, &["🎵", "🎶"], &["#FFFFFF"]) },
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_effect_has_a_recipe() {
        for id in HIT_EFFECTS {
            let s = effect_spec(id.into());
            assert_eq!(s.id, id);
            assert!(!s.colors.is_empty(), "{id} needs colors");
            assert!(s.shape != ParticleShape::Glyph || !s.glyphs.is_empty(), "{id} glyph effect needs glyphs");
            assert!(s.lifetime > 0.0 && s.burst > 0);
            for c in &s.colors {
                assert!(c.len() == 7 && c.starts_with('#'), "{id}: bad color {c}");
            }
        }
        assert_eq!(effect_spec("fx.nope".into()).id, "fx.boom");
        assert!(aura_spec("au.flame".into()).is_some());
        assert!(aura_spec("au.none".into()).is_none());
    }
}
