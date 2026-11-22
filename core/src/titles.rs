//! Colours of the title cosmetics. A title colours itself and the player's name.

/// "#RRGGBB" colours from left to right (one = plain). They're readable on white, on black and on the card frames' dark
/// name plate. Unknown titles are grey.
#[uniffi::export]
pub fn title_colors(id: String) -> Vec<String> {
    let c: &[&str] = match id.as_str() {
        "ti.newbie" => &["#4E9A5B"],
        "ti.student" => &["#3D8BFF", "#35B6E8"],
        "ti.panda" => &["#8A8F9C", "#5FA777"],
        "ti.tea" => &["#2FA36B", "#8DB83A"],
        "ti.dumpling" => &["#E39A2D", "#F0703A"],
        "ti.kungfu" => &["#E5383B", "#F77F3A"],
        "ti.dragon" => &["#10B981", "#1D9BF0"],
        "ti.master" => &["#E0A100", "#F26B1D"],
        "ti.street" => &["#EC4899", "#9B6BFF"],
        "ti.boss" => &["#9B5CFF", "#E0409A"],
        "ti.flat" => &["#14B8A6", "#5B9DF9"],
        "ti.owl" => &["#7C7FF5", "#A78BFA"],
        "ti.drone" => &["#7387A3", "#94A3B8"],
        "ti.legend" => &["#FF4DA6", "#F59E0B", "#1FB5D8"],
        "ti.hooligan" => &["#F43F5E", "#D6336C"],
        "ti.swearking" => &["#D946EF", "#EF4444"],
        _ => &["#8A8F9C"],
    };
    c.iter().map(|s| s.to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const TITLES: [&str; 16] = [
        "ti.newbie", "ti.student", "ti.panda", "ti.tea", "ti.dumpling", "ti.kungfu", "ti.dragon", "ti.master", "ti.street", "ti.boss",
        "ti.flat", "ti.owl", "ti.drone", "ti.legend", "ti.hooligan", "ti.swearking",
    ];

    fn luminance(hex: &str) -> f64 {
        let part = |i: usize| {
            let v = u8::from_str_radix(&hex[i..i + 2], 16).unwrap() as f64 / 255.0;
            if v <= 0.03928 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) }
        };
        0.2126 * part(1) + 0.7152 * part(3) + 0.0722 * part(5)
    }

    #[test]
    fn every_title_has_its_own_readable_colours() {
        let mut seen = std::collections::HashSet::new();
        for id in TITLES {
            let c = title_colors(id.into());
            assert!(seen.insert(c.clone()), "{id} looks like another title");
            for hex in c {
                let l = luminance(&hex);
                let (on_white, on_black) = (1.05 / (l + 0.05), (l + 0.05) / (luminance("#14161B") + 0.05));
                assert!(on_white > 1.9 && on_black > 3.0, "{id} {hex}: {on_white:.1} on white, {on_black:.1} on black");
            }
        }
        assert_eq!(title_colors("ti.nope".into()).len(), 1);
    }
}
