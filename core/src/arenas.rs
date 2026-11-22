//! Arenas: the scenery behind the learning path and the battles. Calm nature for beginners, darker and more
//! hellish as the material gets harder. The scenery is drawn here as draw commands (see draw.rs).

use crate::draw::*;
use std::f32::consts::{PI, TAU};

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

/// One stop on the arena road.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ArenaStop {
    pub theme: ArenaTheme,
    /// HSK level that plays here.
    pub level: u8,
    pub state: ArenaStopState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ArenaStopState {
    Conquered,
    Current,
    Locked,
}

/// Every arena from the first to the last, for somebody on `level`.
#[uniffi::export]
pub fn arena_road(level: u8, unit: u32) -> Vec<ArenaStop> {
    let here = arena_for(level, 1).tier;
    (1..=ARENA_TIERS)
        .map(|tier| ArenaStop {
            theme: arena_for(tier as u8, if tier == here { unit } else { 1 }),
            level: tier as u8,
            state: match tier.cmp(&here) {
                std::cmp::Ordering::Less => ArenaStopState::Conquered,
                std::cmp::Ordering::Equal => ArenaStopState::Current,
                std::cmp::Ordering::Greater => ArenaStopState::Locked,
            },
        })
        .collect()
}

/// Part of the scenery that moves together, back to front.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SceneLayer {
    /// Draw commands.
    pub ops: Vec<u8>,
    /// How much it moves with scrolling (0 = still, far away).
    pub parallax: f32,
}

/// Smooth repeatable noise, 0–1.
fn wobble(x: f32, seed: f32) -> f32 {
    let s = (x * 2.1 + seed).sin() + 0.5 * (x * 4.7 + seed * 2.3).sin() + 0.25 * (x * 9.3 + seed * 4.1).sin();
    (s / 1.75 + 1.0) / 2.0
}

/// Pointed noise, 0–1 (mountain ridges).
fn ridge(x: f32, seed: f32) -> f32 {
    1.0 - (2.0 * wobble(x, seed) - 1.0).abs()
}

/// A view being painted: sizes in fractions of its width and height.
struct Scene {
    w: f32,
    h: f32,
    dark: bool,
    pen: Pen,
    layers: Vec<SceneLayer>,
}

impl Scene {
    /// Light or dark mode colour.
    fn c(&self, light: u32, dark: u32) -> C {
        C::hex(if self.dark { dark } else { light })
    }
    fn p(&self, x: f32, y: f32) -> P {
        (x * self.w, y * self.h)
    }
    /// Unit for things that mustn't stretch: the smaller side (a phone's width).
    fn u(&self) -> f32 {
        self.w.min(self.h * 1.2)
    }
    /// Closes the current layer.
    fn layer(&mut self, parallax: f32) {
        let pen = std::mem::take(&mut self.pen);
        self.layers.push(SceneLayer { ops: pen.bytes(), parallax });
    }
    fn sky(&mut self, colors: &[C]) {
        let n = colors.len() - 1;
        for i in 0..n {
            let (y1, y2) = (self.h * i as f32 / n as f32, self.h * (i + 1) as f32 / n as f32 + 1.0);
            self.pen.poly2(&[(0.0, y1), (self.w, y1), (self.w, y2), (0.0, y2)], colors[i], colors[i + 1], y1, y2, false);
        }
    }
    /// Ground whose top edge is `f(x)` (fraction of the height, from the top). It reaches below the view, so
    /// parallax never uncovers its bottom.
    fn ground(&mut self, top: C, bottom: C, f: impl Fn(f32) -> f32) {
        const N: usize = 72;
        let mut pts: Vec<P> = (0..=N).map(|i| self.p(i as f32 / N as f32, f(i as f32 / N as f32))).collect();
        let y1 = pts.iter().map(|p| p.1).fold(f32::MAX, f32::min);
        pts.push((self.w, self.h * 1.3));
        pts.push((0.0, self.h * 1.3));
        self.pen.poly2(&pts, top, bottom, y1, self.h, false);
    }
    fn mist(&mut self, y: f32, thick: f32, c: C) {
        let (y1, y2, y3) = ((y - thick) * self.h, y * self.h, (y + thick) * self.h);
        let w = self.w;
        self.pen.poly2(&[(0.0, y1), (w, y1), (w, y2), (0.0, y2)], c.a(0.0), c, y1, y2, false);
        self.pen.poly2(&[(0.0, y2), (w, y2), (w, y3), (0.0, y3)], c, c.a(0.0), y2, y3, false);
    }
    fn cloud(&mut self, at: P, size: f32, c: C, shade: C) {
        for (k, (dx, dy, r)) in [(-1.1, 0.1, 0.5), (-0.5, -0.2, 0.72), (0.25, -0.32, 0.86), (0.95, 0.0, 0.6), (0.2, 0.12, 0.7)].iter().enumerate() {
            let p = (at.0 + dx * size, at.1 + dy * size);
            self.pen.disc((p.0, p.1 + size * 0.1), r * size, if k < 4 { shade } else { c }, false);
            if k < 4 {
                self.pen.disc((p.0 - size * 0.04, p.1 - size * 0.04), r * size * 0.95, c, false);
            }
        }
        let y = at.1 + size * 0.42;
        self.pen.line((at.0 - 1.35 * size, y), (at.0 + 1.3 * size, y), size * 0.5, c, false);
    }
    fn stars(&mut self, n: u32, down_to: f32, c: C) {
        for i in 0..n {
            let p = self.p(rnd(i, 301), rnd(i, 302) * down_to);
            self.pen.disc(p, 0.5 + 1.1 * rnd(i, 303), c.a(0.35 + 0.6 * rnd(i, 304)), false);
        }
    }
    /// The sun by day, the moon by night.
    fn sun(&mut self, x: f32, y: f32, r: f32, day: C, night: C) {
        let (p, r) = (self.p(x, y), r * self.u());
        let c = if self.dark { night } else { day };
        self.pen.glow(p, r * 5.0, c.a(0.4), false);
        self.pen.glow(p, r * 2.2, c.a(0.7), false);
        self.pen.disc(p, r, c.mix(WHITE, 0.35), false);
        if self.dark {
            self.pen.disc((p.0 + r * 0.3, p.1 - r * 0.2), r * 0.18, c.mix(C::hex(0x8a93a8), 0.4).a(0.5), false);
            self.pen.disc((p.0 - r * 0.25, p.1 + r * 0.3), r * 0.26, c.mix(C::hex(0x8a93a8), 0.4).a(0.4), false);
        }
    }
    fn shafts(&mut self, n: u32, c: C, seed: u32) {
        for i in 0..n {
            let x = (i as f32 + rnd(i, seed)) / n as f32 * self.w * 1.2 - self.w * 0.05;
            let w = self.w * (0.03 + 0.06 * rnd(i, seed + 1));
            let d = self.w * 0.24;
            let y2 = self.h * (0.65 + 0.3 * rnd(i, seed + 2));
            self.pen.poly2(&[(x, -5.0), (x + w, -5.0), (x + w * 1.8 - d, y2), (x - d, y2)], c.a(0.5 + 0.5 * rnd(i, seed + 3)), c.a(0.0), 0.0, y2, false);
        }
    }
    fn tree(&mut self, at: P, size: f32, trunk: C, crown: C, light: C, seed: u32) {
        let t = size * 0.075;
        self.pen.poly(&[(at.0 - t * 1.4, at.1 + size * 0.05), (at.0 - t * 0.6, at.1 - size * 0.6), (at.0 + t * 0.6, at.1 - size * 0.6), (at.0 + t * 1.4, at.1 + size * 0.05)], trunk, false);
        self.pen.line((at.0, at.1 - size * 0.35), (at.0 - size * 0.24, at.1 - size * 0.62), t * 0.9, trunk, false);
        self.pen.line((at.0, at.1 - size * 0.42), (at.0 + size * 0.22, at.1 - size * 0.66), t * 0.8, trunk, false);
        for k in 0..11u32 {
            let a = TAU * rnd(k, seed);
            let d = size * 0.34 * rnd(k, seed + 1).sqrt();
            let p = (at.0 + d * a.cos() * 1.25, at.1 - size * 0.8 + d * a.sin() * 0.8);
            self.pen.disc((p.0, p.1 + size * 0.03), size * (0.16 + 0.08 * rnd(k, seed + 2)), crown, false);
        }
        for k in 0..9u32 {
            let a = TAU * rnd(k, seed + 5);
            let d = size * 0.28 * rnd(k, seed + 6).sqrt();
            let p = (at.0 - size * 0.06 + d * a.cos() * 1.2, at.1 - size * 0.86 + d * a.sin() * 0.7);
            self.pen.disc(p, size * (0.08 + 0.06 * rnd(k, seed + 7)), light.a(0.85), false);
        }
    }
    /// A Chinese roof: curved up at both ends.
    fn roof(&mut self, c: P, half: f32, tall: f32, col: C, edge: C) {
        let mut pts = vec![];
        for i in 0..=12 {
            let x = -1.0 + i as f32 / 6.0;
            pts.push((c.0 + x * half, c.1 - tall * 0.34 * x.abs().powi(4)));
        }
        pts.push((c.0 + half * 0.46, c.1 - tall * 0.9));
        pts.push((c.0 + half * 0.4, c.1 - tall));
        pts.push((c.0 - half * 0.4, c.1 - tall));
        pts.push((c.0 - half * 0.46, c.1 - tall * 0.9));
        self.pen.poly2(&pts, col.mix(WHITE, 0.08), col, c.1 - tall, c.1, false);
        let eave: Vec<P> = pts[..13].to_vec();
        self.pen.stroke(&eave, (tall * 0.13).max(1.0), edge, false);
        self.pen.line((c.0 - half * 0.42, c.1 - tall), (c.0 + half * 0.42, c.1 - tall), (tall * 0.14).max(1.0), edge, false);
    }
    #[allow(clippy::too_many_arguments)]
    fn pagoda(&mut self, at: P, size: f32, tiers: u32, wall: C, roof: C, edge: C, window: C) {
        for k in 0..tiers {
            let s = 1.0 - 0.17 * k as f32;
            let y = at.1 - size * 0.3 * k as f32;
            let half = size * 0.19 * s;
            self.pen.poly(&[(at.0 - half, y), (at.0 + half, y), (at.0 + half * 0.94, y - size * 0.24), (at.0 - half * 0.94, y - size * 0.24)], wall, false);
            for x in [-0.55f32, 0.0, 0.55] {
                let p = (at.0 + x * half, y - size * 0.09);
                self.pen.poly(&place(&rect(0.16, 0.3), p, half, 0.0, 1.0), window, false);
            }
            self.roof((at.0, y - size * 0.2), size * 0.33 * s, size * 0.13, roof, edge);
        }
        let top = at.1 - size * (0.3 * tiers as f32 - 0.03);
        self.pen.line((at.0, top), (at.0, top - size * 0.2), size * 0.025, edge, false);
        self.pen.disc((at.0, top - size * 0.1), size * 0.035, edge, false);
    }
    fn pine(&mut self, at: P, size: f32, c: C, trunk: C) {
        self.pen.line(at, (at.0, at.1 - size * 0.5), size * 0.06, trunk, false);
        for k in 0..4 {
            let y = at.1 - size * (0.18 + 0.2 * k as f32);
            let half = size * (0.28 - 0.055 * k as f32);
            let shade = c.mix(WHITE, 0.05 * k as f32);
            self.pen.poly(&[(at.0 - half, y), (at.0, y - size * 0.32), (at.0 + half, y), (at.0 + half * 0.3, y - size * 0.04), (at.0 - half * 0.3, y - size * 0.04)], shade, false);
        }
    }
    fn bamboo(&mut self, x: f32, w: f32, top: f32, c: C, light: C, seed: u32) {
        let lean = (rnd(seed, 1) - 0.5) * self.w * 0.05;
        // every stalk has its joints at other heights
        let (y0, y1) = (self.h * 1.1 + w * 8.0 * rnd(seed, 2), self.h * top);
        let x = x * self.w;
        let at = |t: f32| (x + lean * t * t, lerp(y0, y1, t));
        let joints = ((y0 - y1) / (w * (6.5 + 3.0 * rnd(seed, 7)))).max(3.0) as u32;
        for k in 0..joints {
            let (a, b) = (at(k as f32 / joints as f32), at((k + 1) as f32 / joints as f32));
            self.pen.line(a, (b.0, b.1 + w * 0.5), w, c, false);
            self.pen.line((a.0 - w * 0.22, a.1), (b.0 - w * 0.22, b.1 + w * 0.8), w * 0.24, light, false);
            self.pen.line((b.0 - w * 0.62, b.1), (b.0 + w * 0.62, b.1), w * 0.24, light, false);
            if k > joints / 3 && rnd(seed * 31 + k, 3) < 0.6 {
                let dir = if rnd(seed * 31 + k, 4) < 0.5 { -1.0 } else { 1.0 };
                let tip = (b.0 + dir * w * 4.2, b.1 - w * 1.2);
                self.pen.line(b, tip, w * 0.2, c, false);
                for m in 0..4u32 {
                    let q = (lerp(b.0, tip.0, 0.5 + 0.17 * m as f32), lerp(b.1, tip.1, 0.5 + 0.17 * m as f32));
                    let ang = dir * (1.5 + 0.5 * rnd(seed * 97 + k * 5 + m, 5));
                    let l = w * (1.6 + 0.9 * rnd(seed * 97 + k * 5 + m, 6));
                    self.pen.poly(&place(&leaf(), (q.0 + dir * l * 0.5, q.1 + l * 0.35), l, ang, 0.75), if m % 2 == 0 { c } else { light }, false);
                }
            }
        }
    }
    fn grass(&mut self, n: u32, base: f32, tall: f32, c: C, light: C, seed: u32) {
        for i in 0..n {
            let x = (i as f32 + rnd(i, seed)) / n as f32 * self.w;
            let y = self.h * (base + 0.02 * rnd(i, seed + 1));
            let l = self.h * tall * (0.5 + 0.8 * rnd(i, seed + 2));
            let d = (rnd(i, seed + 3) - 0.5) * l * 0.7;
            self.pen.poly(&[(x - 2.2, y), (x + d, y - l), (x + 2.2, y)], if rnd(i, seed + 4) < 0.5 { c } else { light }, false);
        }
    }
    fn flower(&mut self, p: P, r: f32, c: C, mid: C) {
        for k in 0..5 {
            self.pen.disc(polar(p, r * 0.72, TAU * k as f32 / 5.0 + p.0), r * 0.55, c, false);
        }
        self.pen.disc(p, r * 0.42, mid, false);
    }
    /// A chain hanging from the top.
    fn chain(&mut self, x: f32, to: f32, size: f32, c: C, light: C) {
        let mut y = -size;
        let mut k = 0;
        while y < to * self.h {
            let p = (x * self.w + (y * 0.02).sin() * size * 0.4, y);
            if k % 2 == 0 {
                let pts: Vec<P> = (0..=14).map(|i| { let a = TAU * i as f32 / 14.0; (p.0 + size * 0.5 * a.cos(), p.1 + size * 0.85 * a.sin()) }).collect();
                self.pen.stroke(&pts, size * 0.3, c, false);
                self.pen.stroke(&pts[6..11], size * 0.1, light, false);
            } else {
                self.pen.line((p.0, p.1 - size * 0.75), (p.0, p.1 + size * 0.75), size * 0.34, c, false);
            }
            y += size * 1.15;
            k += 1;
        }
    }
}

/// The still scenery of an arena in a `w` × `h` view, back to front.
#[uniffi::export]
pub fn arena_scene(theme: ArenaTheme, w: f32, h: f32, dark: bool) -> Vec<SceneLayer> {
    let mut s = Scene { w: w.max(10.0), h: h.max(10.0), dark, pen: Pen::default(), layers: vec![] };
    let u = s.u();
    let x = C::hex;
    match theme.tier {
        1 => {
            let sky = if dark { vec![x(0x0b1a3a), x(0x1a2f55), x(0x2d4a5e)] } else { vec![x(0x6cc1ff), x(0xb3e3ff), x(0xf6f3da)] };
            s.sky(&sky);
            if dark {
                s.stars(70, 0.5, WHITE);
            }
            s.sun(0.78, 0.13, 0.07, x(0xffe27a), x(0xe9eefc));
            s.layer(0.0);
            let (c, sh) = if dark { (x(0x4a6285), x(0x3a5072)) } else { (WHITE, x(0xd3ebfa)) };
            for (px, py, z) in [(0.2, 0.12, 0.085), (0.62, 0.27, 0.06), (0.05, 0.33, 0.05), (0.95, 0.39, 0.07)] {
                let p = s.p(px, py);
                s.cloud(p, z * u, c, sh);
            }
            s.layer(0.03);
            let (a, b) = (s.c(0x9fd8c8, 0x2a4a55), s.c(0xc9ecc4, 0x24403f));
            s.ground(a, b, |t| 0.60 - 0.11 * wobble(t * 2.0, 0.4));
            s.layer(0.06);
            let (a, b) = (s.c(0x86d078, 0x22513c), s.c(0xb4e58e, 0x1c4030));
            s.ground(a, b, |t| 0.70 - 0.08 * wobble(t * 2.6, 2.1));
            let (trunk, crown, light) = (s.c(0x7a4a35, 0x3b2a2a), s.c(0xff9dc4, 0x9a4f78), s.c(0xffd0e4, 0xc27ba0));
            for (k, (px, py, z)) in [(0.1, 0.68, 0.2), (0.34, 0.665, 0.13), (0.72, 0.675, 0.15), (0.93, 0.69, 0.22)].into_iter().enumerate() {
                let p = s.p(px, py);
                s.tree(p, z * u, trunk, crown, light, 20 + k as u32 * 11);
            }
            s.layer(0.1);
            let (a, b) = (s.c(0x5fbf57, 0x1b4a30), s.c(0x3f9c46, 0x12321f));
            s.ground(a, b, |t| 0.83 - 0.06 * wobble(t * 3.2, 4.0));
            // a brook
            let brook: Vec<P> = (0..=10).map(|i| { let t = i as f32 / 10.0; s.p(0.45 + 0.16 * (t * 5.0).sin() * (0.4 + t), 0.80 + 0.28 * t) }).collect();
            let mut bank = brook.iter().enumerate().map(|(i, p)| (p.0 - u * (0.008 + 0.008 * i as f32), p.1)).collect::<Vec<_>>();
            bank.extend(brook.iter().enumerate().rev().map(|(i, p)| (p.0 + u * (0.008 + 0.008 * i as f32), p.1)));
            let (ba, bb) = (s.c(0xbfeaff, 0x3d6c8f), s.c(0x5fb6e8, 0x1f4564));
            s.pen.poly2(&bank, ba, bb, 0.8 * s.h, s.h, false);
            let (g, gl) = (s.c(0x3f9c46, 0x15402a), s.c(0x8ee07a, 0x2c6b43));
            s.grass(80, 0.875, 0.028, g, gl, 50);
            for i in 0..34u32 {
                let p = s.p(rnd(i, 61), 0.86 + 0.14 * rnd(i, 62));
                let col = [s.c(0xff6fa8, 0xa8456f), s.c(0xffffff, 0xb9c4d6), s.c(0xffd23f, 0xb08a1f), s.c(0xb48cff, 0x6f55a8)][(rnd(i, 63) * 4.0) as usize % 4];
                s.flower(p, u * (0.008 + 0.007 * rnd(i, 64)), col, x(0xffe680));
            }
            s.layer(0.18);
        }
        2 => {
            let sky = if dark { vec![x(0x06201a), x(0x0d3327), x(0x164433)] } else { vec![x(0xd8f5b8), x(0xa9e2a0), x(0x7fca8b)] };
            s.sky(&sky);
            let glow = s.c(0xfffbd0, 0xcfe8ff);
            let p = s.p(0.62, 0.1);
            s.pen.glow(p, u * 0.6, glow.a(if dark { 0.25 } else { 0.85 }), false);
            s.layer(0.0);
            let (c, l) = (s.c(0x93d39a, 0x1a4a38), s.c(0xb0e3ae, 0x235a45));
            for i in 0..15u32 {
                s.bamboo((i as f32 + rnd(i, 1)) / 15.0, u * 0.022, 0.02 * rnd(i, 2) - 0.1, c, l, i + 1);
            }
            let m = s.c(0xe9f8d2, 0x1c4d3b);
            s.mist(0.62, 0.25, m.a(0.6));
            s.layer(0.04);
            let shaft = s.c(0xfffde0, 0x9fd8c0);
            s.shafts(6, shaft.a(if dark { 0.06 } else { 0.3 }), 9);
            let (c, l) = (s.c(0x55ab5e, 0x14402c), s.c(0x86cf78, 0x21603f));
            for i in 0..9u32 {
                s.bamboo((i as f32 + 0.9 * rnd(i, 5)) / 9.0, u * 0.036, -0.1, c, l, i + 40);
            }
            s.mist(0.8, 0.16, m.a(0.45));
            s.layer(0.1);
            let (a, b) = (s.c(0x4f9b52, 0x123a26), s.c(0x2f7a42, 0x0a2417));
            s.ground(a, b, |t| 0.86 - 0.05 * wobble(t * 4.0, 5.0));
            // stepping-stone path and a stone lantern
            let (st, stl) = (s.c(0xb9c2b4, 0x3b4a45), s.c(0xd9dfd2, 0x51615b));
            for i in 0..7 {
                let t = i as f32 / 6.0;
                let c = s.p(0.5 + 0.1 * (t * 4.0).sin(), 0.865 + 0.16 * t);
                let r = u * (0.02 + 0.03 * t);
                let e: Vec<P> = circle(16).iter().map(|q| (c.0 + q.0 * r * 1.5, c.1 + q.1 * r * 0.55)).collect();
                s.pen.poly(&e.iter().map(|q| (q.0, q.1 + r * 0.14)).collect::<Vec<_>>(), st, false);
                s.pen.poly(&e, stl, false);
            }
            let lp = s.p(0.8, 0.875);
            let z = u * 0.11;
            s.pen.poly(&[(lp.0 - z * 0.12, lp.1), (lp.0 + z * 0.12, lp.1), (lp.0 + z * 0.1, lp.1 - z * 0.6), (lp.0 - z * 0.1, lp.1 - z * 0.6)], st, false);
            s.pen.poly(&place(&rect(0.32, 0.26), (lp.0, lp.1 - z * 0.82), z, 0.0, 1.0), stl, false);
            s.pen.poly(&place(&rect(0.18, 0.18), (lp.0, lp.1 - z * 0.82), z, 0.0, 1.0), x(0xffd97a), false);
            s.pen.glow((lp.0, lp.1 - z * 0.82), z * 0.9, x(0xffd97a).a(if dark { 0.6 } else { 0.35 }), true);
            s.roof((lp.0, lp.1 - z * 1.02), z * 0.55, z * 0.28, st, stl);
            let (c, l) = (s.c(0x2c7d42, 0x0b2c1b), s.c(0x5fb55c, 0x1a4c30));
            for (i, px) in [(0u32, -0.015f32), (1, 0.07), (2, 0.975)] {
                s.bamboo(px, u * 0.06, -0.12, c, l, i + 80);
            }
            let (g, gl) = (s.c(0x2c7d42, 0x0d3320), s.c(0x7cc96a, 0x1f5636));
            s.grass(60, 0.95, 0.04, g, gl, 33);
            s.layer(0.18);
        }
        3 => {
            let sky = if dark { vec![x(0x0f1631), x(0x27315a), x(0x4d4a74)] } else { vec![x(0x8fb4e8), x(0xc7d5f0), x(0xfbe4d2)] };
            s.sky(&sky);
            if dark {
                s.stars(60, 0.45, WHITE);
            }
            s.sun(0.28, 0.2, 0.11, x(0xffc9a8), x(0xf2ecd8));
            s.layer(0.0);
            let cols = if dark { [0x3b4674, 0x303a64, 0x262f54] } else { [0xa9bfe3, 0x8ba6d3, 0x6d8bc0] };
            let m = s.c(0xf3f1f6, 0x565f8e);
            for (k, (base, tall, f, seed)) in [(0.52, 0.30, 3.1, 0.7), (0.62, 0.25, 4.0, 2.9), (0.72, 0.19, 4.6, 5.2)].into_iter().enumerate() {
                let c = x(cols[k]);
                s.ground(c.mix(WHITE, 0.1), c, |t| base - tall * ridge(t * f, seed) - 0.012 * wobble(t * 30.0, seed));
                s.mist(base + 0.06, 0.12, m.a(0.75));
                if k == 1 {
                    let (wall, roof, edge) = (s.c(0xf2e3d0, 0x4a4460), s.c(0xb3483c, 0x6b2f3a), s.c(0x7a2d28, 0x8f4a4a));
                    let win = s.c(0x6b4a3a, 0xffd27a);
                    let p = s.p(0.74, 0.60);
                    s.pagoda(p, u * 0.3, 4, wall, roof, edge, win);
                }
                s.layer(0.05 + 0.04 * k as f32);
            }
            let (a, b) = (s.c(0x55739c, 0x1b2445), s.c(0x33507a, 0x10172f));
            s.ground(a, b, |t| 0.86 - 0.10 * ridge(t * 3.7, 1.3));
            // stairs up to a gate
            let (st, stl) = (s.c(0xc9c4c0, 0x565a78), s.c(0xe5e0da, 0x6f7394));
            for i in 0..12 {
                let t = i as f32 / 11.0;
                let c = s.p(0.30 - 0.02 * t, 0.835 + 0.2 * t);
                let half = u * (0.05 + 0.11 * t);
                s.pen.poly(&[(c.0 - half, c.1), (c.0 + half, c.1), (c.0 + half * 1.04, c.1 + s.h * 0.02), (c.0 - half * 1.04, c.1 + s.h * 0.02)], if i % 2 == 0 { stl } else { st }, false);
            }
            let g = s.p(0.30, 0.835);
            let (red, roof, edge) = (s.c(0xb8402f, 0x7a2f2f), s.c(0x3f5a6b, 0x2d3b55), s.c(0x2c414f, 0x47597a));
            for k in [-1.0f32, 1.0] {
                s.pen.line((g.0 + k * u * 0.075, g.1), (g.0 + k * u * 0.075, g.1 - u * 0.15), u * 0.018, red, false);
            }
            s.pen.line((g.0 - u * 0.1, g.1 - u * 0.12), (g.0 + u * 0.1, g.1 - u * 0.12), u * 0.016, red, false);
            s.roof((g.0, g.1 - u * 0.145), u * 0.15, u * 0.055, roof, edge);
            let (pc, pt) = (s.c(0x2f6b5c, 0x16343f), s.c(0x5a4334, 0x2b2733));
            for (px, py, z) in [(0.05, 0.88, 0.2), (0.13, 0.91, 0.26), (0.55, 0.885, 0.16), (0.88, 0.89, 0.24), (0.97, 0.92, 0.3)] {
                let p = s.p(px, py);
                s.pine(p, z * u, pc, pt);
            }
            s.mist(0.97, 0.08, m.a(0.5));
            s.layer(0.18);
        }
        4 => {
            let sky = if dark { vec![x(0x1d0f1c), x(0x5a1f1c), x(0xb0481c)] } else { vec![x(0xc4562f), x(0xff9440), x(0xffd07a)] };
            s.sky(&sky);
            let p = s.p(0.4, 0.42);
            s.pen.glow(p, u * 0.7, x(0xff6a1a).a(0.5), true);
            // smoke from the crater
            for i in 0..26u32 {
                let t = i as f32 / 25.0;
                let p = s.p(0.40 + 0.22 * t * t + 0.03 * (rnd(i, 3) - 0.5), 0.40 - 0.40 * t);
                let c = s.c(0x5b3b38, 0x2b1c20).mix(s.c(0x8f5f4c, 0x4a2a28), rnd(i, 4));
                s.pen.glow(p, u * (0.07 + 0.15 * t), c.a(0.75 - 0.35 * t), false);
            }
            s.layer(0.0);
            // the volcano
            let vol = |t: f32| {
                let d = (t - 0.40).abs();
                (if d < 0.055 { 0.415 + 0.02 * (1.0 - d / 0.055) } else { 0.41 + 0.95 * (d - 0.055).powf(0.82) }).min(0.80) + 0.012 * wobble(t * 26.0, 1.0)
            };
            let (a, b) = (s.c(0x7a3a2c, 0x3a1a1c), s.c(0xa85a38, 0x52241c));
            s.ground(a, b, vol);
            let rim = s.p(0.40, 0.425);
            s.pen.glow(rim, u * 0.16, x(0xffc24a).a(0.9), true);
            for k in 0..5u32 {
                let mut pts = vec![];
                let dir = (k as f32 - 2.0) * 0.06;
                for i in 0..=12 {
                    let t = i as f32 / 12.0;
                    pts.push(s.p(0.40 + (k as f32 - 2.0) * 0.016 + dir * t * 1.6 + 0.012 * (t * 11.0 + k as f32).sin(), 0.425 + (0.2 + 0.1 * rnd(k, 5)) * t));
                }
                s.pen.stroke(&pts, u * 0.028, x(0xff5a1f).a(0.35), true);
                s.pen.stroke(&pts, u * 0.012, x(0xffb02e), false);
                s.pen.stroke(&pts, u * 0.005, x(0xfff1a8), false);
            }
            s.layer(0.05);
            let (a, b) = (s.c(0x9a5238, 0x4a211c), s.c(0x6e3527, 0x2f1414));
            // mesas
            s.ground(a, b, |t| { let v = wobble(t * 4.0, 2.0); 0.74 - 0.10 * ((v * 3.0).floor() / 3.0) - 0.03 * v });
            s.layer(0.1);
            let (a, b) = (s.c(0x5c2c24, 0x2a1214), s.c(0x3a1a18, 0x160a0c));
            s.ground(a, b, |t| 0.84 - 0.06 * ridge(t * 5.0, 4.4));
            // cracks glowing
            for k in 0..7u32 {
                let mut p = s.p(rnd(k, 11), 0.86 + 0.1 * rnd(k, 12));
                let mut pts = vec![p];
                for m in 0..5 {
                    p = (p.0 + u * (rnd(k * 9 + m, 13) - 0.4) * 0.12, p.1 + s.h * 0.016 * (rnd(k * 9 + m, 14) + 0.4));
                    pts.push(p);
                }
                s.pen.stroke(&pts, u * 0.022, x(0xff5a1f).a(0.35), true);
                s.pen.stroke(&pts, u * 0.007, x(0xffb02e), false);
            }
            // dead trees
            let tc = s.c(0x2b1513, 0x120709);
            for (px, py, z) in [(0.1, 0.87, 0.24), (0.83, 0.86, 0.2), (0.95, 0.9, 0.3)] {
                let p = s.p(px, py);
                let z = z * u;
                s.pen.line(p, (p.0 + z * 0.05, p.1 - z * 0.75), z * 0.07, tc, false);
                for (dx, dy, f) in [(-0.4, -0.95, 0.4), (0.42, -1.0, 0.5), (-0.26, -0.7, 0.3), (0.3, -0.74, 0.62)] {
                    let from = (p.0 + z * 0.05 * f, p.1 - z * 0.75 * f);
                    let mid = (p.0 + dx * z * 0.6, p.1 + dy * z * 0.8);
                    s.pen.stroke(&[from, mid, (p.0 + dx * z, p.1 + dy * z)], z * 0.035, tc, false);
                }
            }
            s.layer(0.18);
        }
        5 => {
            let sky = if dark { vec![x(0x120406), x(0x4a0d0a), x(0xa82a0c)] } else { vec![x(0x4a0f10), x(0xa8260f), x(0xff6a1f)] };
            s.sky(&sky);
            for i in 0..18u32 {
                let p = s.p(rnd(i, 1) * 1.1 - 0.05, 0.22 * rnd(i, 2));
                s.pen.glow(p, u * (0.12 + 0.16 * rnd(i, 3)), x(0x22090b).a(0.6), false);
            }
            let p = s.p(0.5, 0.62);
            s.pen.glow(p, u * 0.8, x(0xff7a1f).a(0.55), true);
            s.layer(0.0);
            let (a, b) = (s.c(0x5c1a14, 0x2a0a0a), s.c(0x8c2c14, 0x4a1409));
            s.ground(a, b, |t| 0.58 - 0.24 * ridge(t * 4.4, 0.2) * (0.55 + 0.9 * (t - 0.5).abs()));
            // lava falls
            for (px, top, w) in [(0.17, 0.44, 0.030), (0.84, 0.40, 0.038), (0.66, 0.50, 0.018)] {
                let (p1, p2) = (s.p(px, top), s.p(px + 0.015, 0.66));
                let w = w * u;
                s.pen.line(p1, p2, w * 2.4, x(0xff5a1f).a(0.3), true);
                s.pen.poly2(&[(p1.0 - w * 0.4, p1.1), (p1.0 + w * 0.4, p1.1), (p2.0 + w * 0.8, p2.1), (p2.0 - w * 0.8, p2.1)], x(0xfff1a8), x(0xff8a1f), p1.1, p2.1, false);
            }
            s.layer(0.05);
            // the lake
            s.ground(x(0xffd45a), x(0xff4a12), |t| 0.645 + 0.006 * wobble(t * 12.0, 1.7));
            for i in 0..26u32 {
                let c = s.p(rnd(i, 21), 0.67 + 0.22 * rnd(i, 22));
                let l = u * (0.04 + 0.12 * rnd(i, 23));
                s.pen.line((c.0 - l, c.1), (c.0 + l, c.1), u * 0.006, x(0xfff6c8).a(0.6), false);
            }
            for i in 0..12u32 {
                let t = rnd(i, 25);
                let c = s.p(rnd(i, 24), 0.69 + 0.17 * t);
                let r = u * (0.03 + 0.06 * t);
                let e: Vec<P> = (0..11).map(|k| { let a = TAU * k as f32 / 11.0; let rr = r * (0.75 + 0.4 * rnd(i * 13 + k, 26)); (c.0 + rr * 1.6 * a.cos(), c.1 + rr * 0.45 * a.sin()) }).collect();
                s.pen.poly(&e.iter().map(|q| (q.0, q.1 + r * 0.12)).collect::<Vec<_>>(), x(0xff7a1f), false);
                s.pen.poly(&e, s.c(0x3a1210, 0x1d0808), false);
            }
            s.layer(0.1);
            let (a, b) = (s.c(0x35100f, 0x1a0707), s.c(0x160506, 0x090203));
            s.ground(a, b, |t| 0.93 - 0.17 * ridge(t * 6.0, 3.3) * (0.25 + 1.5 * (t - 0.5).abs()));
            for i in 0..16u32 {
                let c = s.p((i as f32 + rnd(i, 31)) / 16.0, 1.0);
                let z = u * (0.05 + 0.1 * rnd(i, 32));
                s.pen.poly(&[(c.0 - z * 0.5, c.1), (c.0 + z * (rnd(i, 33) - 0.5) * 0.4, c.1 - z * 1.6), (c.0 + z * 0.5, c.1)], s.c(0x260a0a, 0x120404), false);
                s.pen.line((c.0 - z * 0.5, c.1), (c.0 - z * 0.05, c.1 - z * 1.35), u * 0.004, x(0xff7a1f).a(0.8), false);
            }
            s.layer(0.18);
        }
        _ => {
            let sky = if dark { vec![x(0x050102), x(0x2a0406), x(0x8a130a)] } else { vec![x(0x1c0305), x(0x6b0b0c), x(0xd92a0f)] };
            s.sky(&sky);
            for i in 0..22u32 {
                let p = s.p(rnd(i, 1) * 1.1 - 0.05, 0.3 * rnd(i, 2));
                s.pen.glow(p, u * (0.12 + 0.2 * rnd(i, 3)), x(0x0c0203).a(0.6), false);
            }
            let p = s.p(0.5, 0.5);
            s.pen.glow(p, u * 0.75, x(0xff3b1f).a(0.6), true);
            s.layer(0.0);
            // a blood moon behind the gate
            let (m, r) = (s.p(0.5, 0.2), u * 0.15);
            s.pen.glow(m, r * 2.6, x(0xff2e1f).a(0.5), true);
            s.pen.disc(m, r, x(0xb3140f), false);
            s.pen.disc((m.0 - r * 0.25, m.1 + r * 0.2), r * 0.25, x(0x7a0c0a).a(0.6), false);
            s.pen.disc((m.0 + r * 0.35, m.1 - r * 0.25), r * 0.16, x(0x7a0c0a).a(0.6), false);
            let (a, b) = (s.c(0x3d0b0c, 0x1c0405), s.c(0x7a1410, 0x450a08));
            s.ground(a, b, |t| 0.60 - 0.26 * ridge(t * 7.0, 2.0) * (0.3 + 1.2 * (t - 0.5).abs()) - 0.02 * wobble(t * 40.0, 1.0));
            s.layer(0.04);
            // the gate 地狱之门
            let (wall, lit, gold) = (x(0x1f0607), x(0x3d0d0d), x(0xc9851f));
            let g = |fx: f32, fy: f32| s_p(w, h, fx, fy);
            let k = u * 0.01;
            let base = 0.735;
            let c = g(0.5, base);
            let top = c.1 - 46.0 * k;
            // inner light
            s.pen.poly2(&[(c.0 - 16.0 * k, c.1), (c.0 - 16.0 * k, top + 8.0 * k), (c.0 + 16.0 * k, top + 8.0 * k), (c.0 + 16.0 * k, c.1)], x(0xff3b1f), x(0xffd45a), top, c.1, false);
            s.pen.glow((c.0, c.1 - 14.0 * k), 34.0 * k, x(0xffd45a).a(0.8), true);
            // doors ajar
            for d in [-1.0f32, 1.0] {
                let door = [(c.0 + d * 16.0 * k, top + 8.0 * k), (c.0 + d * 5.0 * k, top + 12.0 * k), (c.0 + d * 5.0 * k, c.1 - 1.5 * k), (c.0 + d * 16.0 * k, c.1)];
                s.pen.poly2(&door, x(0x5c0f0e), x(0x2b0606), top, c.1, false);
                for row in 0..5 {
                    for col in 0..3 {
                        let q = (c.0 + d * (7.5 + 3.2 * col as f32) * k, top + (16.0 + 5.6 * row as f32) * k);
                        s.pen.disc(q, 0.75 * k, gold, false);
                    }
                }
            }
            // pillars
            for (dx, pw, pt) in [(-27.0, 4.2, 4.0), (-17.5, 3.2, 0.0), (17.5, 3.2, 0.0), (27.0, 4.2, 4.0)] {
                let px = c.0 + dx * k;
                s.pen.poly2(&[(px - pw * k, c.1 + k), (px - pw * k * 0.86, top + pt * k), (px + pw * k * 0.86, top + pt * k), (px + pw * k, c.1 + k)], lit, wall, top, c.1, false);
                s.pen.line((px - pw * k * 0.5, c.1), (px - pw * k * 0.45, top + pt * k), 0.6 * k, x(0xff5a1f).a(0.5), false);
                for yy in [0.22f32, 0.78] {
                    let y = lerp(top + pt * k, c.1, yy);
                    s.pen.line((px - pw * k, y), (px + pw * k, y), 1.4 * k, gold, false);
                }
            }
            s.roof((c.0, top + 6.0 * k), 40.0 * k, 9.0 * k, x(0x2b0808), gold);
            s.roof((c.0, top - 4.0 * k), 28.0 * k, 10.0 * k, x(0x380a0a), gold);
            // the name board
            s.pen.poly(&place(&rect(11.0, 4.4), (c.0, top + 9.5 * k), k, 0.0, 1.0), gold, false);
            s.pen.poly(&place(&rect(10.2, 3.7), (c.0, top + 9.5 * k), k, 0.0, 1.0), x(0x17181c), false);
            for (i, ch) in "地狱之门".chars().enumerate() {
                s.pen.glyph(ch, (c.0 + (i as f32 - 1.5) * 4.9 * k, top + 9.5 * k), 4.4 * k, 0.0, 1.0);
            }
            // horns on the ridge
            for d in [-1.0f32, 1.0] {
                let q = (c.0 + d * 11.0 * k, top - 13.0 * k);
                s.pen.poly(&[(q.0 - d * 2.0 * k, q.1), (q.0 + d * 3.0 * k, q.1), (q.0 + d * 8.0 * k, q.1 - 9.0 * k)], wall, false);
            }
            s.layer(0.08);
            let (a, b) = (s.c(0x2b0808, 0x160405), s.c(0x100303, 0x060102));
            s.ground(a, b, |t| base - 0.012 + 0.03 * (1.0 - (t - 0.5).abs() * 2.0).max(0.0) - 0.05 * ridge(t * 9.0, 3.0) * (t - 0.5).abs() * 2.0);
            // a burning road to the gate
            let road: Vec<P> = [(0.46, 0.765), (0.54, 0.765), (0.86, 1.3), (0.14, 1.3)].iter().map(|q| s.p(q.0, q.1)).collect();
            s.pen.poly2(&road, x(0x7a1a10), x(0x2b0a08), 0.765 * s.h, s.h, false);
            for i in 0..9 {
                let t = (i as f32 / 9.0).powf(1.6);
                let (y, half) = (0.772 + 0.25 * t, 0.04 + 0.15 * t);
                let (l, r) = (s.p(0.5 - half, y), s.p(0.5 + half, y));
                s.pen.line(l, r, u * (0.003 + 0.006 * t), x(0xff5a1f).a(0.7), false);
            }
            // lava rivers on both sides
            for d in [-1.0f32, 1.0] {
                let pts: Vec<P> = (0..=12).map(|i| { let t = i as f32 / 12.0; s.p(0.5 + d * (0.12 + 0.36 * t + 0.02 * (t * 9.0).sin()), 0.775 + 0.28 * t) }).collect();
                s.pen.stroke(&pts, u * 0.07, x(0xff3b1f).a(0.35), true);
                s.pen.stroke(&pts, u * 0.034, x(0xff7a1f), false);
                s.pen.stroke(&pts, u * 0.013, x(0xfff1a8), false);
            }
            // braziers
            for px in [0.17f32, 0.83] {
                let q = s.p(px, 0.80);
                s.pen.line(q, (q.0, q.1 - 9.0 * k), 2.0 * k, wall, false);
                s.pen.poly(&[(q.0 - 5.5 * k, q.1 - 13.0 * k), (q.0 + 5.5 * k, q.1 - 13.0 * k), (q.0 + 3.0 * k, q.1 - 8.0 * k), (q.0 - 3.0 * k, q.1 - 8.0 * k)], lit, false);
                s.pen.line((q.0 - 5.8 * k, q.1 - 13.0 * k), (q.0 + 5.8 * k, q.1 - 13.0 * k), 1.2 * k, gold, false);
            }
            for i in 0..22u32 {
                let t = (i as f32 + rnd(i, 41)) / 22.0;
                let c = s.p(t, 1.02);
                let z = u * (0.04 + 0.1 * rnd(i, 42)) * (0.5 + (t - 0.5).abs());
                s.pen.poly(&[(c.0 - z * 0.42, c.1), (c.0 + z * 0.1, c.1 - z * 2.2), (c.0 + z * 0.42, c.1)], x(0x0c0203), false);
            }
            s.layer(0.14);
            let (cc, cl) = (x(0x17090a), x(0x6b2a20));
            for (px, to) in [(0.06f32, 0.46f32), (0.2, 0.28), (0.82, 0.32), (0.95, 0.5)] {
                s.chain(px, to, u * 0.032, cc, cl);
            }
            s.layer(0.22);
        }
    }
    s.layers
}

fn s_p(w: f32, h: f32, x: f32, y: f32) -> P {
    (x * w, y * h)
}

/// A flame of height `tall` standing on `p`.
fn flame(pen: &mut Pen, p: P, tall: f32, t: f32, seed: u32) {
    pen.glow((p.0, p.1 - tall * 0.4), tall * 1.1, C::hex(0xff5a1f).a(0.4 + 0.08 * (t * 9.0 + seed as f32).sin()), true);
    for (k, col) in [0xff3b1fu32, 0xff8a1f, 0xffd23f, 0xfff6c8].into_iter().enumerate() {
        let z = 1.0 - 0.22 * k as f32;
        let sway = (t * (7.0 + k as f32) + seed as f32 * 1.7).sin() * tall * 0.1;
        let hh = tall * z * (0.9 + 0.12 * (t * 11.0 + seed as f32 + k as f32).sin());
        let w = tall * 0.26 * z;
        let pts = [(p.0 - w * 0.6, p.1), (p.0 - w, p.1 - hh * 0.3), (p.0 - w * 0.45 + sway * 0.4, p.1 - hh * 0.65), (p.0 + sway, p.1 - hh), (p.0 + w * 0.5 + sway * 0.4, p.1 - hh * 0.62), (p.0 + w, p.1 - hh * 0.28), (p.0 + w * 0.6, p.1)];
        pen.poly(&pts, C::hex(col).a(0.85), false);
    }
}

/// The moving part of the scenery at `t_ms` on any clock: petals, leaves, clouds, ash, embers, fire.
#[uniffi::export]
pub fn arena_frame(theme: ArenaTheme, t_ms: u64, w: f32, h: f32, dark: bool) -> Vec<u8> {
    let mut pen = Pen::default();
    let t = (t_ms % 3_600_000) as f32 / 1000.0;
    let u = w.min(h * 1.2);
    let x = C::hex;
    let busy = 0.7 + 0.6 * theme.intensity;
    // `n` things, each reborn every `life` seconds: id of this life, age 0–1, its own random number
    let each = |n: f32, life: f32, f: &mut dyn FnMut(u32, f32, f32)| {
        for i in 0..(n * busy) as u32 {
            let l = life * (0.75 + 0.5 * rnd(i, 1));
            let q = t / l + rnd(i, 2);
            f(i.wrapping_mul(7919).wrapping_add(q.floor() as u32), q.fract(), rnd(i, q.floor() as u32 + 3));
        }
    };
    let embers = |pen: &mut Pen, n: f32, reach: f32| {
        each(n, 5.0, &mut |k, a, r| {
            let p = (r * w + (a * 7.0 + k as f32).sin() * u * 0.05, h * (1.02 - reach * a));
            let c = x(0xffd23f).mix(x(0xff5a1f), a * 1.6);
            let z = u * (0.004 + 0.005 * rnd(k, 5));
            pen.glow(p, z * 4.0, c.a(0.5 * (1.0 - a)), true);
            pen.disc(p, z, c.mix(WHITE, 0.4).a(1.0 - a * a), true);
        });
    };
    match theme.tier {
        1 => {
            each(16.0, 9.0, &mut |k, a, r| {
                let p = (r * w * 1.2 - w * 0.2 * (1.0 - a) + (a * 9.0 + k as f32).sin() * u * 0.05, h * (a * 1.1 - 0.05));
                let c = [x(0xffb7d5), x(0xff9ec6), x(0xffe3ef)][(rnd(k, 5) * 3.0) as usize % 3];
                let z = u * (0.010 + 0.008 * rnd(k, 6));
                pen.poly(&place(&petal(), p, z, a * 8.0 + r * 6.0, 0.35 + 0.65 * (a * 14.0 + k as f32).cos().abs()), c.a((a * PI).sin().sqrt()), false);
            });
            // butterflies by day, fireflies by night
            each(4.0, 12.0, &mut |k, a, r| {
                let p = (w * (r + 0.25 * (a * 5.0 + k as f32).sin()), h * (0.70 + 0.16 * (a * 7.0 + k as f32 * 2.0).sin()));
                let al = (a * PI).sin();
                if dark {
                    pen.glow(p, u * 0.03, x(0xd9ff7a).a(al * (0.5 + 0.5 * (t * 4.0 + k as f32).sin())), true);
                    pen.disc(p, u * 0.004, x(0xf6ffd0).a(al), true);
                } else {
                    let flap = 0.25 + 0.75 * (t * 13.0 + k as f32).sin().abs();
                    let c = [x(0xff8a3d), x(0x6aa8ff), x(0xffe14a)][(rnd(k, 5) * 3.0) as usize % 3].a(al);
                    for d in [-1.0f32, 1.0] {
                        pen.poly(&place(&leaf(), (p.0 + d * u * 0.008 * flap, p.1 - u * 0.004), u * 0.013, d * 0.7, 1.6 * flap), c, false);
                    }
                }
            });
        }
        2 => {
            each(13.0, 10.0, &mut |k, a, r| {
                let p = (r * w + (a * 8.0 + k as f32).sin() * u * 0.08, h * (a * 1.1 - 0.05));
                let c = [x(0x6fbf5a), x(0xa8d65f), x(0xd9c24a)][(rnd(k, 5) * 3.0) as usize % 3];
                pen.poly(&place(&leaf(), p, u * (0.016 + 0.01 * rnd(k, 6)), a * 7.0 + r * 6.0, 0.4 + 0.6 * (a * 11.0).cos().abs()), c.a((a * PI).sin().sqrt()), false);
            });
            each(9.0, 6.0, &mut |k, a, r| {
                let p = (w * (r + 0.06 * (a * 6.0 + k as f32).sin()), h * (0.45 + 0.45 * rnd(k, 5) + 0.04 * (a * 8.0).cos()));
                pen.glow(p, u * 0.022, x(0xe9ff9a).a((a * PI).sin() * if dark { 0.9 } else { 0.5 }), true);
            });
        }
        3 => {
            for i in 0..5u32 {
                let a = (t / (46.0 + 14.0 * i as f32) + rnd(i, 7)).fract();
                let p = (w * (a * 1.7 - 0.35), h * (0.42 + 0.11 * i as f32));
                let c = if dark { x(0x8b93bf) } else { WHITE };
                for k in 0..6 {
                    let q = (p.0 + (k as f32 - 2.5) * u * 0.1, p.1 + u * 0.02 * (k as f32 * 2.1).sin());
                    pen.glow(q, u * (0.13 + 0.04 * rnd(i * 7 + k, 8)), c.a(0.3 * (a * PI).sin()), false);
                }
            }
            // cranes
            for i in 0..3 {
                let a = (t / 30.0 + i as f32 * 0.05).fract();
                let p = (w * (1.15 - 1.3 * a) + i as f32 * u * 0.05, h * (0.24 + 0.02 * i as f32 + 0.02 * (a * 12.0).sin()));
                let f = (t * 5.0 + i as f32).sin() * u * 0.014;
                let c = if dark { x(0xd9def2) } else { x(0x4a5878) };
                pen.stroke(&[(p.0 - u * 0.024, p.1 - f), (p.0 - u * 0.009, p.1 - u * 0.004), p, (p.0 + u * 0.009, p.1 - u * 0.004), (p.0 + u * 0.024, p.1 - f)], u * 0.005, c, false);
            }
            each(7.0, 14.0, &mut |k, a, r| {
                let p = (r * w + a * u * 0.2, h * a);
                pen.disc(p, u * 0.004, WHITE.a(0.6 * (a * PI).sin() * (0.5 + 0.5 * rnd(k, 5))), false);
            });
        }
        4 => {
            let rim = (0.40 * w, 0.425 * h);
            pen.glow(rim, u * (0.2 + 0.03 * (t * 2.3).sin()), x(0xff8a1f).a(0.45 + 0.2 * (t * 3.1).sin()), true);
            // the volcano spits
            each(16.0, 2.2, &mut |k, a, r| {
                let (vx, vy) = ((r - 0.5) * u * 0.42, u * (0.3 + 0.35 * rnd(k, 5)));
                let p = (rim.0 + vx * a, rim.1 - vy * a * 1.6 + u * 0.75 * a * a);
                pen.glow(p, u * 0.018, x(0xff8a1f).a(0.8 * (1.0 - a)), true);
                pen.disc(p, u * 0.006, x(0xfff1a8).a(1.0 - a), true);
            });
            each(26.0, 8.0, &mut |k, a, r| {
                let p = (r * w * 1.2 - a * u * 0.25, h * (a * 1.05 - 0.02));
                let c = x(0x3a2a28).mix(x(0xb09a8c), rnd(k, 5));
                pen.disc(p, u * (0.004 + 0.005 * rnd(k, 6)), c.a(0.7 * (a * PI).sin()), false);
            });
            embers(&mut pen, 9.0, 0.5);
        }
        5 => {
            // the lake breathes
            for i in 0..5u32 {
                let p = (w * (0.1 + 0.2 * i as f32), h * (0.70 + 0.05 * rnd(i, 3)));
                pen.glow(p, u * 0.2, x(0xffb02e).a(0.16 + 0.12 * (t * 1.7 + i as f32 * 2.0).sin()), true);
            }
            each(10.0, 1.8, &mut |k, a, r| {
                let p = (r * w, h * (0.68 + 0.18 * rnd(k, 5)));
                pen.ring(p, u * 0.03 * a, u * 0.005, x(0xfff1a8).a(1.0 - a), true);
            });
            for (px, top) in [(0.17f32, 0.44f32), (0.84, 0.40), (0.66, 0.50)] {
                for i in 0..5 {
                    let a = (t * 0.7 + i as f32 / 5.0).fract();
                    let p = ((px + 0.015 * a) * w, h * lerp(top, 0.66, a));
                    pen.glow(p, u * 0.03, x(0xfff6c8).a(0.7 * (a * PI).sin()), true);
                }
            }
            embers(&mut pen, 34.0, 0.95);
        }
        _ => {
            let k = u * 0.01;
            let pulse = 0.5 + 0.5 * (t * 1.4).sin();
            pen.glow((0.5 * w, 0.735 * h - 16.0 * k), (34.0 + 8.0 * pulse) * k, x(0xff5a1f).a(0.35 + 0.25 * pulse), true);
            for (i, px) in [0.17f32, 0.83].into_iter().enumerate() {
                flame(&mut pen, (px * w, 0.80 * h - 13.0 * k), 22.0 * k, t, i as u32 * 5);
            }
            for i in 0..11u32 {
                let f = (i as f32 + 0.5) / 11.0;
                let d = (f - 0.5).abs() * 2.0;
                if d > 0.25 {
                    flame(&mut pen, (f * w, h * 1.01), u * (0.06 + 0.16 * d * (0.6 + 0.4 * rnd(i, 9))), t, i + 20);
                }
            }
            // bats
            for i in 0..5u32 {
                let a = (t / (17.0 + 3.0 * i as f32) + rnd(i, 11)).fract();
                let p = (w * (a * 1.3 - 0.15), h * (0.12 + 0.05 * i as f32 + 0.03 * (a * 14.0 + i as f32).sin()));
                let (f, z) = ((t * 12.0 + i as f32).sin() * 0.6, u * 0.02);
                pen.poly(&[(p.0, p.1 + z * 0.4), (p.0 - z, p.1 - z * f), (p.0 - z * 1.9, p.1 + z * f * 0.4), (p.0 - z * 0.9, p.1 + z * 0.12), (p.0, p.1 - z * 0.25), (p.0 + z * 0.9, p.1 + z * 0.12), (p.0 + z * 1.9, p.1 + z * f * 0.4), (p.0 + z, p.1 - z * f)], x(0x0c0203), false);
            }
            embers(&mut pen, 44.0, 1.0);
        }
    }
    pen.bytes()
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
    fn the_road_shows_every_arena() {
        use ArenaStopState::*;
        let road = arena_road(3, 5);
        assert_eq!(road.iter().map(|s| s.state).collect::<Vec<_>>(), vec![Conquered, Conquered, Current, Locked, Locked, Locked]);
        assert_eq!(road.iter().map(|s| s.level).collect::<Vec<_>>(), vec![1, 2, 3, 4, 5, 6]);
        assert!(road[2].theme.intensity > 0.0 && road[5].theme.id == "hell");
        assert!(arena_road(9, 1).iter().all(|s| s.state != Locked));
    }

    #[test]
    fn every_arena_can_be_drawn() {
        let mut seen = std::collections::HashSet::new();
        for level in 1..=6 {
            let a = arena_for(level, 3);
            for (w, h) in [(390.0, 844.0), (360.0, 240.0), (820.0, 1180.0)] {
                for dark in [false, true] {
                    let layers = arena_scene(a.clone(), w, h, dark);
                    assert!(layers.len() >= 4, "{}", a.id);
                    assert_eq!(layers[0].parallax, 0.0, "the sky stays");
                    let ops: usize = layers.iter().map(|l| check(&l.ops).unwrap_or_else(|| panic!("{} is malformed", a.id)).len()).sum();
                    assert!(ops > 60, "{} is too plain ({ops})", a.id);
                    assert!(seen.insert(layers.iter().flat_map(|l| l.ops.clone()).collect::<Vec<u8>>()));
                    for t in [0u64, 777, 1_795_363_644_276] {
                        assert!(check(&arena_frame(a.clone(), t, w, h, dark)).unwrap().len() > 5, "{} doesn't move", a.id);
                    }
                }
            }
        }
        let live = |unit| check(&arena_frame(arena_for(6, unit), 1234, 390.0, 844.0, false)).unwrap().len();
        assert!(live(13) > live(1), "livelier the further you get");
    }
}
