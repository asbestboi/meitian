//! Hit effects (`fx.*`) and auras (`au.*`), drawn frame by frame as draw commands (see draw.rs). Every frame is a
//! pure function of time, so a dropped frame never changes the picture.

use crate::draw::*;
use std::f32::consts::{FRAC_PI_2, PI, TAU};

/// Every hit effect cosmetic.
pub const HIT_EFFECTS: [&str; 17] = [
    "fx.boom", "fx.fire", "fx.zap", "fx.envelope", "fx.blossom", "fx.dragon", "fx.bomb", "fx.glove", "fx.firecracker",
    "fx.tomato", "fx.mic", "fx.poop", "fx.glitch", "fx.money", "fx.snow", "fx.hearts", "fx.chrome",
];

/// Every aura cosmetic that draws something.
pub const AURAS: [&str; 8] =
    ["au.flame", "au.sparkle", "au.hearts", "au.snow", "au.money", "au.chrome", "au.glitch", "au.notes"];

/// Seconds from the throw to the impact.
const FLIGHT: f32 = 0.38;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HitInfo {
    pub id: String,
    /// Impact sound (`hit_sound_pcm`).
    pub sound: String,
    /// Screen shake at the impact, in points.
    pub shake: f32,
    /// When it lands.
    pub impact_ms: u32,
    /// When the last particle is gone.
    pub duration_ms: u32,
}

/// What the apps need to know to play a hit effect. Unknown ids fall back to the default boom.
#[uniffi::export]
pub fn hit_info(id: String) -> HitInfo {
    let id = if HIT_EFFECTS.contains(&id.as_str()) { id } else { "fx.boom".into() };
    let shake = match id.as_str() {
        "fx.bomb" => 20.0,
        "fx.dragon" => 16.0,
        "fx.glove" => 15.0,
        "fx.zap" => 13.0,
        "fx.firecracker" | "fx.glitch" => 10.0,
        "fx.mic" | "fx.fire" => 9.0,
        "fx.boom" | "fx.chrome" => 8.0,
        "fx.tomato" | "fx.poop" | "fx.snow" => 6.0,
        _ => 4.0,
    };
    let sound = id.trim_start_matches("fx.").to_string();
    HitInfo { id, sound, shake, impact_ms: (FLIGHT * 1000.0) as u32, duration_ms: 2100 }
}

// ---------- particles ----------

#[derive(Clone, Copy, PartialEq)]
enum Shape {
    Glow,
    Disc,
    /// A bright streak along the direction of travel.
    Spark,
    Smoke,
    Petal,
    Leaf,
    Heart,
    Star,
    Flake,
    Shard,
    Square,
    Coin,
    Bill,
    Note,
}

#[derive(Clone, Copy)]
struct Emit<'a> {
    n: u32,
    shape: Shape,
    colors: &'a [C],
    /// Speed from–to, points per second.
    v: (f32, f32),
    life: (f32, f32),
    size: (f32, f32),
    /// Size at the end of its life, times the size at the start.
    grow: f32,
    dir: f32,
    spread: f32,
    gravity: f32,
    drag: f32,
    /// Radians per second.
    spin: f32,
    /// Particles start somewhere within this distance.
    radius: f32,
    add: bool,
    /// Every particle starts up to this much later.
    stagger: f32,
    salt: u32,
}

const E: Emit<'static> = Emit {
    n: 30,
    shape: Shape::Glow,
    colors: &[WHITE],
    v: (60.0, 300.0),
    life: (0.4, 0.9),
    size: (4.0, 10.0),
    grow: 0.3,
    dir: 0.0,
    spread: TAU,
    gravity: 0.0,
    drag: 2.6,
    spin: 0.0,
    radius: 0.0,
    add: true,
    stagger: 0.0,
    salt: 1,
};

fn pick(colors: &[C], r: f32) -> C {
    colors[((r * colors.len() as f32) as usize).min(colors.len() - 1)]
}

/// Draws one particle.
#[allow(clippy::too_many_arguments)]
fn particle(pen: &mut Pen, shape: Shape, p: P, size: f32, rot: f32, flip: f32, vel: P, c: C, add: bool) {
    match shape {
        Shape::Glow => {
            pen.glow(p, size * 2.2, c.a(0.75), add);
            pen.disc(p, size * 0.45, c.mix(WHITE, 0.55), add);
        }
        Shape::Disc => {
            pen.disc(p, size, c, add);
            pen.disc((p.0 - size * 0.3, p.1 - size * 0.3), size * 0.3, WHITE.a(0.45 * c.3), false);
        }
        Shape::Spark => {
            let tail = (p.0 - vel.0 * 0.06, p.1 - vel.1 * 0.06);
            pen.line(p, tail, size * 1.9, c.a(0.35), add);
            pen.line(p, (lerp(p.0, tail.0, 0.6), lerp(p.1, tail.1, 0.6)), size * 0.8, c.mix(WHITE, 0.6), add);
        }
        Shape::Smoke => pen.glow(p, size * 2.0, c, false),
        Shape::Petal => {
            let sq = 0.35 + 0.65 * flip.cos().abs();
            pen.poly(&place(&petal(), p, size, rot, sq), c, false);
            let tip = place(&[(0.0, 0.9), (0.0, -0.3)], p, size, rot, sq);
            pen.line(tip[0], tip[1], size * 0.12, C::hex(0xff5f9e).a(0.5 * c.3), false);
        }
        Shape::Leaf => pen.poly(&place(&leaf(), p, size, rot, 0.4 + 0.6 * flip.cos().abs()), c, false),
        Shape::Heart => {
            pen.poly(&place(&heart(), p, size, rot * 0.25, 1.0), c, false);
            pen.disc(polar(p, size * 0.5, -2.4 + rot * 0.25), size * 0.16, WHITE.a(0.7 * c.3), false);
        }
        Shape::Star => {
            pen.glow(p, size * 1.8, c.a(0.5), true);
            pen.poly(&place(&star(4, 0.16), p, size * 1.2, rot * 0.3, 1.0), c.mix(WHITE, 0.4), add);
        }
        Shape::Flake => {
            for k in 0..3 {
                let a = rot + PI * k as f32 / 3.0;
                let (p1, p2) = (polar(p, size, a), polar(p, size, a + PI));
                pen.line(p1, p2, size * 0.16, c, false);
                for (e, back) in [(p1, a + PI), (p2, a)] {
                    let m = (lerp(e.0, p.0, 0.35), lerp(e.1, p.1, 0.35));
                    pen.line(m, polar(m, size * 0.32, back + 2.3), size * 0.12, c, false);
                    pen.line(m, polar(m, size * 0.32, back - 2.3), size * 0.12, c, false);
                }
            }
        }
        Shape::Shard => {
            let pts = place(&[(0.0, -1.0), (0.45, 0.2), (0.1, 0.9), (-0.35, 0.4)], p, size, rot, 0.4 + 0.6 * flip.cos().abs());
            pen.poly(&pts, c, add);
            pen.poly(&pts[0..3], c.mix(WHITE, 0.4), add);
        }
        Shape::Square => pen.poly(&place(&rect(0.8, 0.8), p, size, 0.0, 1.0), c, add),
        Shape::Coin => {
            let sq = flip.cos().abs().max(0.14);
            pen.poly(&place(&circle(16), p, size, rot * 0.2, sq), C::hex(0xb36b00).a(c.3), false);
            pen.poly2(&place(&circle(16), (p.0, p.1 - size * 0.08), size * 0.92, rot * 0.2, sq), C::hex(0xfff0a0).a(c.3), c, p.1 - size, p.1 + size, false);
            // the square hole of an old Chinese coin
            pen.poly(&place(&rect(0.26, 0.26), (p.0, p.1 - size * 0.08), size, rot * 0.2, sq), C::hex(0xa86400).a(c.3), false);
        }
        Shape::Bill => {
            let sq = flip.cos().abs().max(0.12);
            pen.poly2(&place(&rect(0.6, 1.0), p, size, rot, sq), c.mix(WHITE, 0.25), c, p.1 - size, p.1 + size, false);
            pen.poly(&place(&rect(0.48, 0.86), p, size, rot, sq), c.mix(C::hex(0x0b5c3a), 0.25), false);
            pen.poly(&place(&circle(12), p, size * 0.32, rot, sq), c.mix(WHITE, 0.65), false);
        }
        Shape::Note => {
            let head = place(&circle(12), p, size * 0.42, rot * 0.2 - 0.4, 1.35);
            pen.poly(&head, c, add);
            let top = (p.0 + size * 0.5, p.1 - size * 1.5);
            pen.line((p.0 + size * 0.5, p.1), top, size * 0.16, c, add);
            pen.poly(&[top, (top.0 + size * 0.7, top.1 + size * 0.65), (top.0, top.1 + size * 0.45)], c, add);
        }
    }
}

/// `e`'s particles `t` seconds after they were thrown from `at`.
fn burst(pen: &mut Pen, e: &Emit, at: P, t: f32) {
    if t < 0.0 {
        return;
    }
    for i in 0..e.n {
        let r = |k: u32| rnd(i * 16 + k, e.salt);
        let age = t - e.stagger * r(9);
        let life = lerp(e.life.0, e.life.1, r(0));
        if age < 0.0 || age >= life {
            continue;
        }
        let u = age / life;
        let a = e.dir + (r(1) - 0.5) * e.spread;
        // square root: as many slow ones as fast ones per area, so a burst looks like a filled ball
        let speed = lerp(e.v.0, e.v.1, r(2).sqrt());
        let k = e.drag.max(0.05);
        let decay = (-k * age).exp();
        let reach = (1.0 - decay) / k;
        let start = polar(at, e.radius * r(3).sqrt(), r(4) * TAU);
        let g = e.gravity / k;
        let p = (start.0 + a.cos() * speed * reach, start.1 + g * age + (a.sin() * speed - g) * reach);
        let vel = (a.cos() * speed * decay, g + (a.sin() * speed - g) * decay);
        let alpha = (u / 0.08).min(1.0) * (1.0 - u.powf(2.2));
        let size = lerp(e.size.0, e.size.1, r(5)) * lerp(1.0, e.grow, u);
        let turn = r(6) * TAU + e.spin * (r(7) * 2.0 - 1.0) * age;
        particle(pen, e.shape, p, size, turn, r(8) * TAU + age * e.spin * 1.6, vel, pick(e.colors, r(10)).a(alpha), e.add);
    }
}

/// A trail left behind while flying along `path` (0–1) during the flight.
fn trail(pen: &mut Pen, e: &Emit, path: &dyn Fn(f32) -> P, t: f32) {
    for i in 0..e.n {
        let r = |k: u32| rnd(i * 16 + k, e.salt ^ 0x5bd1);
        let born = FLIGHT * (i as f32 + r(0)) / e.n as f32;
        let life = lerp(e.life.0, e.life.1, r(1));
        let age = t - born;
        if age < 0.0 || age >= life {
            continue;
        }
        let u = age / life;
        let c = path(born / FLIGHT);
        let start = polar(c, e.radius * r(2).sqrt(), r(3) * TAU);
        let a = r(4) * TAU;
        let v = lerp(e.v.0, e.v.1, r(5));
        let p = (start.0 + a.cos() * v * age, start.1 + a.sin() * v * age + 0.5 * e.gravity * age * age);
        let alpha = (u / 0.1).min(1.0) * (1.0 - u.powf(1.6));
        let size = lerp(e.size.0, e.size.1, r(6)) * lerp(1.0, e.grow, u);
        let turn = r(7) * TAU + e.spin * (r(8) * 2.0 - 1.0) * age;
        particle(pen, e.shape, p, size, turn, r(9) * TAU + age * e.spin * 1.6, (a.cos() * v, a.sin() * v), pick(e.colors, r(10)).a(alpha), e.add);
    }
}

// ---------- building blocks ----------

/// 0 → 1, fast first.
fn out(t: f32) -> f32 {
    1.0 - (1.0 - t.clamp(0.0, 1.0)).powi(3)
}

/// Pops past 1 and settles.
fn pop(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0) - 1.0;
    1.0 + 2.7 * t * t * t + 1.7 * t * t
}

/// Fades in quickly, stays, fades out. `t` in 0–1.
fn fade(t: f32, hold: f32) -> f32 {
    if t <= 0.0 || t >= 1.0 {
        0.0
    } else if t < hold {
        (t / 0.06).min(1.0)
    } else {
        1.0 - (t - hold) / (1.0 - hold)
    }
}

fn shockwave(pen: &mut Pen, c: P, t: f32, dur: f32, radius: f32, width: f32, color: C) {
    let u = t / dur;
    if !(0.0..1.0).contains(&u) {
        return;
    }
    let r = radius * out(u);
    let a = (1.0 - u).powf(1.4);
    pen.ring(c, r, width * (1.0 - u) * 2.4, color.a(a * 0.28), true);
    pen.ring(c, r, width * (1.0 - u) + 0.6, color.mix(WHITE, 0.5).a(a), true);
}

/// White-hot flash of light.
fn flare(pen: &mut Pen, c: P, t: f32, dur: f32, radius: f32, color: C) {
    let u = t / dur;
    if !(0.0..1.0).contains(&u) {
        return;
    }
    let a = (1.0 - u).powi(2);
    pen.glow(c, radius * (0.6 + 0.6 * out(u)), color.a(a), true);
    pen.glow(c, radius * 0.45 * (1.0 + u), WHITE.a(a), true);
}

/// Thin rays of light turning around `c`.
#[allow(clippy::too_many_arguments)]
fn rays(pen: &mut Pen, c: P, t: f32, dur: f32, radius: f32, n: u32, color: C, turn: f32) {
    let u = t / dur;
    if !(0.0..1.0).contains(&u) {
        return;
    }
    let a = fade(u, 0.25) * 0.5;
    for i in 0..n {
        let ang = TAU * i as f32 / n as f32 + turn * t + rnd(i, 77) * 0.3;
        let r = radius * out(u) * (0.6 + 0.4 * rnd(i, 78));
        let w = 0.06 + 0.05 * rnd(i, 79);
        pen.poly(&[polar(c, radius * 0.5 * w, ang - 1.5), polar(c, r * 0.45, ang - w * 1.2), polar(c, r, ang), polar(c, r * 0.45, ang + w * 1.2), polar(c, radius * 0.5 * w, ang + 1.5)], color.a(a * (0.5 + 0.5 * rnd(i, 80))), true);
    }
}

/// A comic-book burst.
fn comic(pen: &mut Pen, c: P, t: f32, dur: f32, radius: f32, colors: [C; 3]) {
    let u = t / dur;
    if !(0.0..1.0).contains(&u) {
        return;
    }
    let s = pop((t / 0.16).min(1.0)) * (1.0 + 0.15 * u);
    let a = fade(u, 0.5);
    for (k, col) in colors.iter().enumerate() {
        let n = 13;
        let pts: Vec<P> = (0..n * 2)
            .map(|i| {
                let long = i % 2 == 0;
                let r = if long { 0.8 + 0.35 * rnd(i, 40) } else { 0.52 + 0.06 * rnd(i, 41) };
                polar(c, radius * s * r * [1.0, 0.78, 0.52][k], PI * i as f32 / n as f32 + 0.12 * k as f32)
            })
            .collect();
        pen.poly(&pts, col.a(a), false);
    }
}

/// Jagged lightning with branches.
#[allow(clippy::too_many_arguments)]
fn lightning(pen: &mut Pen, a: P, b: P, seed: u32, width: f32, color: C, alpha: f32, branches: u32) {
    let n = 14u32;
    let len = ((b.0 - a.0).powi(2) + (b.1 - a.1).powi(2)).sqrt().max(1.0);
    let (nx, ny) = (-(b.1 - a.1) / len, (b.0 - a.0) / len);
    let pts: Vec<P> = (0..=n)
        .map(|i| {
            let t = i as f32 / n as f32;
            let j = if i == 0 || i == n { 0.0 } else { (rnd(i, seed) - 0.5) * len * 0.16 };
            (lerp(a.0, b.0, t) + nx * j, lerp(a.1, b.1, t) + ny * j)
        })
        .collect();
    pen.stroke(&pts, width * 5.0, color.a(alpha * 0.22), true);
    pen.stroke(&pts, width * 2.2, color.a(alpha * 0.55), true);
    pen.stroke(&pts, width * 0.9, WHITE.a(alpha), true);
    for k in 0..branches {
        let from = pts[(2 + (rnd(k, seed + 5) * (n - 4) as f32) as usize).min(pts.len() - 1)];
        let ang = (b.1 - a.1).atan2(b.0 - a.0) + (rnd(k, seed + 6) - 0.5) * 2.2;
        let l = len * (0.1 + 0.16 * rnd(k, seed + 7));
        let mut p = from;
        let mut br = vec![p];
        for m in 0..4 {
            p = polar(p, l / 4.0, ang + (rnd(k * 8 + m, seed + 8) - 0.5) * 1.4);
            br.push(p);
        }
        pen.stroke(&br, width * 1.6, color.a(alpha * 0.4), true);
        pen.stroke(&br, width * 0.5, WHITE.a(alpha * 0.8), true);
    }
}

/// Rolling fire and smoke.
fn fireball(pen: &mut Pen, c: P, t: f32, dur: f32, radius: f32, smoke: bool) {
    let u = t / dur;
    if !(0.0..1.0).contains(&u) {
        return;
    }
    if smoke {
        for i in 0..16 {
            let a = TAU * i as f32 / 16.0 + rnd(i, 60);
            let d = radius * (0.35 + 0.75 * out(u)) * (0.5 + 0.5 * rnd(i, 61));
            let p = polar((c.0, c.1 - radius * 0.7 * u), d, a);
            let shade = C::hex(0x2b2321).mix(C::hex(0x6a5f5a), rnd(i, 62));
            pen.glow(p, radius * (0.34 + 0.35 * u), shade.a(0.75 * fade(u, 0.35)), false);
        }
    }
    for i in 0..22 {
        let a = TAU * rnd(i, 63);
        let d = radius * out(u * 1.4) * 0.8 * rnd(i, 64).sqrt();
        let p = polar((c.0, c.1 - radius * 0.25 * u), d, a);
        let heat = (u * 1.9 + 0.4 * rnd(i, 65)).min(1.0);
        let col = C::hex(0xfff6c8).mix(C::hex(0xffa21f), (heat * 2.0).min(1.0)).mix(C::hex(0xc4200a), (heat * 2.0 - 1.0).max(0.0));
        pen.glow(p, radius * (0.42 + 0.2 * rnd(i, 66)) * (1.0 - 0.35 * u), col.a(0.6 * (1.0 - heat * heat)), true);
    }
}

/// A wet blob that hits, spreads and drips.
fn splat(pen: &mut Pen, c: P, t: f32, dur: f32, radius: f32, dark: C, light: C) {
    let u = t / dur;
    if !(0.0..1.0).contains(&u) {
        return;
    }
    let s = pop((t / 0.14).min(1.0));
    let a = fade(u, 0.6);
    let blob = |scale: f32, off: f32| -> Vec<P> {
        (0..40)
            .map(|i| {
                let ang = TAU * i as f32 / 40.0;
                let spike = (ang * 9.0 + off).sin().max(0.0).powi(6) * (0.25 + 0.45 * rnd(i / 4, 51));
                polar(c, radius * s * scale * (0.62 + 0.1 * (ang * 5.0).sin() + spike), ang)
            })
            .collect()
    };
    for i in 0..5u32 {
        let x = c.0 + radius * (rnd(i, 52) - 0.5) * 1.1;
        let drop = radius * (0.5 + 0.9 * rnd(i, 53)) * out((u * 1.6).min(1.0));
        let w = radius * (0.07 + 0.05 * rnd(i, 54));
        pen.line((x, c.1), (x, c.1 + radius * 0.35 + drop), w * 1.6, dark.a(a), false);
        pen.disc((x, c.1 + radius * 0.35 + drop), w * 1.2, dark.a(a), false);
    }
    pen.poly(&blob(1.0, 0.0), dark.a(a), false);
    pen.poly(&blob(0.8, 0.4), light.a(a), false);
    pen.disc((c.0 - radius * 0.2, c.1 - radius * 0.22), radius * 0.13, WHITE.a(0.55 * a), false);
    pen.disc((c.0 - radius * 0.02, c.1 - radius * 0.32), radius * 0.06, WHITE.a(0.55 * a), false);
}

/// The flying part: a hot core with a tapering tail.
fn comet(pen: &mut Pen, path: &dyn Fn(f32) -> P, f: f32, size: f32, core: C, tail: C) {
    for i in 0..18 {
        let k = i as f32 / 18.0;
        let g = f - k * 0.32;
        if g < 0.0 {
            break;
        }
        let p = path(g);
        pen.glow(p, size * (2.4 - 1.9 * k), tail.a(0.55 * (1.0 - k)), true);
    }
    let p = path(f);
    pen.glow(p, size * 3.4, core.a(0.5), true);
    pen.disc(p, size * 0.8, core.mix(WHITE, 0.7), true);
}

// ---------- hits ----------

/// One frame of a hit effect, `t_ms` after the throw, thrown from (`ax`, `ay`) at (`bx`, `by`) in a view of `w` × `h`
/// points. Empty when it's over.
#[uniffi::export]
#[allow(clippy::too_many_arguments)]
pub fn hit_frame(id: String, t_ms: u32, w: f32, h: f32, ax: f32, ay: f32, bx: f32, by: f32) -> Vec<u8> {
    let info = hit_info(id);
    if t_ms >= info.duration_ms || w <= 1.0 || h <= 1.0 {
        return vec![];
    }
    let mut pen = Pen::default();
    let t = t_ms as f32 / 1000.0;
    let (a, b): (P, P) = ((ax, ay), (bx, by));
    // effects scale with the screen (tuned on a 390-point-wide phone)
    let s = (w.min(h * 1.4) / 390.0).clamp(0.45, 1.6);
    let bulge = 80.0 * s * if bx + ax > w { -1.0 } else { 1.0 };
    // smoothstep along a sideways arc, like something thrown
    let path = move |f: f32| -> P {
        let e = f * f * (3.0 - 2.0 * f);
        let m = ((ax + bx) / 2.0 + bulge, (ay + by) / 2.0);
        let q = |p0: f32, p1: f32, p2: f32| (1.0 - e) * (1.0 - e) * p0 + 2.0 * (1.0 - e) * e * p1 + e * e * p2;
        (q(a.0, m.0, b.0), q(a.1, m.1, b.1))
    };
    let f = t / FLIGHT;
    let i = t - FLIGHT;
    let up = if by < ay { -FRAC_PI_2 } else { FRAC_PI_2 };
    let key = info.sound.as_str();
    draw_hit(&mut pen, key, t, f, i, s, a, b, &path, up);
    // the flash, brightest right at the impact
    let flash = match key {
        "fire" => Some(0xff6a1a),
        "zap" => Some(0xbfe9ff),
        "dragon" => Some(0xffd23f),
        "bomb" | "boom" => Some(0xffffff),
        "firecracker" => Some(0xff3b30),
        "glitch" => Some(0xff3da8),
        "snow" | "chrome" => Some(0xe8f7ff),
        "hearts" | "blossom" => Some(0xffb7d5),
        _ => None,
    };
    if let (Some(c), true) = (flash, (0.0..0.3).contains(&i)) {
        pen.flash(C::hex(c).a(0.38 * (1.0 - i / 0.3)));
    }
    pen.bytes()
}

#[allow(clippy::too_many_arguments)]
fn draw_hit(pen: &mut Pen, key: &str, t: f32, f: f32, i: f32, s: f32, a: P, b: P, path: &dyn Fn(f32) -> P, up: f32) {
    let flying = (0.0..1.0).contains(&f);
    let h = C::hex;
    match key {
        "fire" => {
            let hot = [h(0xfff1a8), h(0xffd23f), h(0xff8a1f), h(0xff3b1f)];
            trail(pen, &Emit { n: 60, colors: &hot, v: (10.0, 50.0), life: (0.25, 0.55), size: (6.0 * s, 13.0 * s), gravity: -260.0, radius: 8.0 * s, ..E }, path, t);
            trail(pen, &Emit { n: 18, shape: Shape::Smoke, colors: &[h(0x3a2f2b).a(0.4)], v: (5.0, 30.0), life: (0.5, 0.9), size: (8.0 * s, 16.0 * s), grow: 1.8, gravity: -90.0, add: false, salt: 4, ..E }, path, t);
            if flying {
                comet(pen, path, f, 15.0 * s, h(0xffe08a), h(0xff5a1f));
            }
            fireball(pen, b, i, 0.75, 92.0 * s, true);
            // tongues of flame
            for k in 0..14u32 {
                let u = (i - 0.05 * rnd(k, 3)) / (0.6 + 0.4 * rnd(k, 4));
                if !(0.0..1.0).contains(&u) {
                    continue;
                }
                let x = b.0 + (rnd(k, 5) - 0.5) * 110.0 * s;
                let tall = (60.0 + 90.0 * rnd(k, 6)) * s * (u * PI).sin();
                let wide = (11.0 + 12.0 * rnd(k, 7)) * s * (1.0 - u * 0.5);
                let sway = (t * 9.0 + k as f32).sin() * 9.0 * s;
                let base = b.1 + (28.0 + 26.0 * rnd(k, 8)) * s;
                let low = base - tall * 0.05;
                let tongue = [(x - wide * 0.4, base), (x - wide, low - tall * 0.2), (x - wide * 0.55 + sway * 0.4, base - tall * 0.6), (x + sway, base - tall), (x + wide * 0.6 + sway * 0.4, base - tall * 0.55), (x + wide, low - tall * 0.2), (x + wide * 0.4, base)];
                let al = 0.6 * (1.0 - u);
                pen.poly2(&tongue, h(0xffa21f).a(al), h(0xff3b1f).a(0.0), base - tall * 0.75, base, true);
            }
            shockwave(pen, b, i, 0.55, 150.0 * s, 12.0 * s, h(0xff8a1f));
            burst(pen, &Emit { n: 46, shape: Shape::Spark, colors: &hot, v: (120.0, 420.0), life: (0.5, 1.3), size: (1.5 * s, 3.0 * s), gravity: -40.0, ..E }, b, i);
            burst(pen, &Emit { n: 26, colors: &hot, v: (20.0, 110.0), life: (0.7, 1.5), size: (2.0 * s, 4.0 * s), gravity: -120.0, radius: 60.0 * s, stagger: 0.4, salt: 9, ..E }, b, i);
        }
        "zap" => {
            // charging up
            if flying {
                let g = out(f);
                pen.glow(a, 60.0 * s * g, h(0x7fd3ff).a(0.6 * g), true);
                pen.disc(a, 9.0 * s * g, WHITE, true);
                for k in 0..5u32 {
                    let ang = TAU * rnd(k, (t * 24.0) as u32);
                    lightning(pen, polar(a, 46.0 * s, ang), a, (t * 24.0) as u32 * 7 + k, 1.2 * s, h(0x7fd3ff), 0.9 * g, 0);
                }
            }
            if (0.0..0.55).contains(&i) {
                let tick = (i * 22.0) as u32;
                let al = fade(i / 0.55, 0.45);
                let bright = if tick.is_multiple_of(2) { 1.0 } else { 0.55 };
                lightning(pen, a, b, 100 + tick, 3.4 * s, h(0x7fd3ff), al * bright, 5);
                lightning(pen, a, b, 900 + tick, 1.8 * s, h(0xc6a8ff), al * 0.7, 3);
                for k in 0..4u32 {
                    let ang = TAU * rnd(k, tick + 31);
                    lightning(pen, b, polar(b, 100.0 * s, ang), tick * 5 + k + 400, 1.6 * s, h(0xbfe9ff), al, 1);
                }
                pen.glow(b, 130.0 * s, h(0x7fd3ff).a(0.6 * al), true);
            }
            flare(pen, b, i, 0.3, 120.0 * s, h(0xbfe9ff));
            shockwave(pen, b, i, 0.5, 140.0 * s, 8.0 * s, h(0x7fd3ff));
            shockwave(pen, b, i - 0.12, 0.5, 100.0 * s, 5.0 * s, h(0xc6ff3d));
            burst(pen, &Emit { n: 56, shape: Shape::Spark, colors: &[h(0xe8f7ff), h(0x7fd3ff), h(0xc6ff3d)], v: (150.0, 620.0), life: (0.3, 0.8), size: (1.2 * s, 2.4 * s), gravity: 260.0, ..E }, b, i);
        }
        "envelope" => {
            let envelope = |pen: &mut Pen, p: P, size: f32, rot: f32, al: f32| {
                pen.poly2(&place(&rect(0.66, 1.0), p, size, rot, 1.0), h(0xff4a3d).a(al), h(0xc4161c).a(al), p.1 - size, p.1 + size, false);
                pen.poly(&place(&[(-0.66, -1.0), (0.66, -1.0), (0.0, -0.25)], p, size, rot, 1.0), h(0xa50f16).a(al), false);
                pen.stroke(&place(&[(-0.66, -1.0), (0.0, -0.25), (0.66, -1.0)], p, size, rot, 1.0), size * 0.06, h(0xffd23f).a(al), false);
                pen.poly(&place(&circle(20), p, size * 0.34, rot, 1.0), h(0xffd23f).a(al), false);
                pen.glyph('福', p, size * 0.42, rot.to_degrees(), al);
            };
            trail(pen, &Emit { n: 22, shape: Shape::Star, colors: &[h(0xffd23f), h(0xfff1a8)], v: (5.0, 40.0), life: (0.3, 0.7), size: (3.0 * s, 7.0 * s), spin: 3.0, ..E }, path, t);
            if flying {
                let p = path(f);
                pen.glow(p, 60.0 * s, h(0xffd23f).a(0.5), true);
                envelope(pen, p, 26.0 * s, t * 14.0, 1.0);
            }
            rays(pen, b, i, 1.3, 170.0 * s, 14, h(0xffd23f), 0.7);
            flare(pen, b, i, 0.4, 110.0 * s, h(0xffd23f));
            if (0.0..0.9).contains(&i) {
                envelope(pen, (b.0, b.1 - 8.0 * s * out(i * 2.0)), 44.0 * s * pop((i / 0.18).min(1.0)), (i * 22.0).sin() * 0.1 * (1.0 - i), fade(i / 0.9, 0.6));
            }
            burst(pen, &Emit { n: 34, shape: Shape::Coin, colors: &[h(0xffc21f), h(0xffb000)], v: (180.0, 430.0), life: (1.0, 1.6), size: (7.0 * s, 12.0 * s), grow: 1.0, dir: -FRAC_PI_2, spread: 2.2, gravity: 620.0, drag: 0.9, spin: 7.0, add: false, stagger: 0.25, ..E }, b, i);
            burst(pen, &Emit { n: 26, shape: Shape::Star, colors: &[h(0xfff1a8), h(0xffd23f)], v: (40.0, 220.0), life: (0.5, 1.2), size: (3.0 * s, 8.0 * s), spin: 4.0, stagger: 0.3, salt: 8, ..E }, b, i);
        }
        "blossom" => {
            let pinks = [h(0xffd3e4), h(0xffa8cb), h(0xff86b5), h(0xfff0f6)];
            trail(pen, &Emit { n: 46, shape: Shape::Petal, colors: &pinks, v: (15.0, 70.0), life: (0.6, 1.2), size: (5.0 * s, 10.0 * s), grow: 0.8, gravity: 60.0, radius: 16.0 * s, spin: 4.0, add: false, ..E }, path, t);
            if flying {
                comet(pen, path, f, 10.0 * s, h(0xffe3ef), h(0xff7fb4));
            }
            flare(pen, b, i, 0.5, 120.0 * s, h(0xff9ec6));
            shockwave(pen, b, i, 0.7, 150.0 * s, 8.0 * s, h(0xff9ec6));
            // a flower opens
            if (0.0..1.1).contains(&i) {
                let g = pop((i / 0.35).min(1.0));
                let al = fade(i / 1.1, 0.55);
                for ring in 0..2 {
                    for k in 0..5 {
                        let ang = TAU * k as f32 / 5.0 + i * 0.5 + ring as f32 * 0.63;
                        let size = [54.0, 34.0][ring] * s * g;
                        let c = polar(b, size * 0.72, ang);
                        pen.poly2(&place(&petal(), c, size * 0.8, ang + FRAC_PI_2, 1.1), pinks[ring * 2].a(al), pinks[1].a(al), c.1 - size, c.1 + size, false);
                    }
                }
                pen.glow(b, 30.0 * s * g, h(0xffe680).a(al), true);
                for k in 0..9 {
                    let e = polar(b, 17.0 * s * g, TAU * k as f32 / 9.0 + i);
                    pen.line(b, e, 1.4 * s, h(0xff5f9e).a(al), false);
                    pen.disc(e, 2.4 * s, h(0xffd23f).a(al), false);
                }
            }
            // petals swirl outward
            for k in 0..44u32 {
                let life = 1.0 + 0.6 * rnd(k, 20);
                let u = (i - 0.12 * rnd(k, 21)) / life;
                if !(0.0..1.0).contains(&u) {
                    continue;
                }
                let r = (26.0 + 150.0 * rnd(k, 22)) * s * out(u);
                let ang = TAU * rnd(k, 23) + u * 3.2;
                let p = polar(b, r, ang);
                let p = (p.0, p.1 + 70.0 * s * u * u);
                particle(pen, Shape::Petal, p, (6.0 + 6.0 * rnd(k, 24)) * s, ang + u * 6.0, u * 9.0 + rnd(k, 25) * TAU, (0.0, 0.0), pick(&pinks, rnd(k, 26)).a(fade(u, 0.5)), false);
            }
        }
        "dragon" => {
            // the body follows the arc, then coils around the target
            let coil = 1.15;
            let pos = |d: f32| -> P {
                if d <= 1.0 {
                    let p = path(d.max(0.0));
                    (p.0 + (d * 16.0).sin() * 22.0 * s, p.1 + (d * 13.0).cos() * 10.0 * s)
                } else {
                    let u = (d - 1.0) / coil;
                    let ang = up + PI + u * TAU * 1.5;
                    let r = (74.0 * (1.0 - (-u * 5.0).exp())) * s;
                    (b.0 + r * ang.cos(), b.1 + r * 0.72 * ang.sin())
                }
            };
            let head = t / FLIGHT * if t < FLIGHT { 1.0 } else { 0.0 } + if t >= FLIGHT { 1.0 + (t - FLIGHT) * 1.9 } else { 0.0 };
            let al = fade(t / 1.5, 0.72);
            let n = 46;
            for k in (0..n).rev() {
                let d = head - k as f32 * 0.021;
                if d < 0.0 {
                    continue;
                }
                let p = pos(d);
                let taper = (1.0 - k as f32 / n as f32).powf(0.7);
                let size = (17.0 * taper + 2.0) * s;
                let body = if k % 2 == 0 { h(0xd9231a) } else { h(0xb3140f) };
                pen.glow(p, size * 2.0, h(0xff8a1f).a(0.22 * al), true);
                pen.disc(p, size, body.a(al), false);
                pen.disc((p.0, p.1 + size * 0.35), size * 0.55, h(0xffc94a).a(al * 0.9), false);
                // spines
                if k % 3 == 1 && k > 2 {
                    let q = pos(d - 0.03);
                    let ang = (p.1 - q.1).atan2(p.0 - q.0);
                    let tip = polar(p, size * 1.9, ang - FRAC_PI_2 - 0.4);
                    pen.poly(&[polar(p, size * 0.8, ang - FRAC_PI_2 + 0.5), tip, polar(p, size * 0.8, ang - FRAC_PI_2 - 0.6)], h(0x2fc98b).a(al), false);
                }
            }
            if head > 0.0 && al > 0.0 {
                let (p, q) = (pos(head), pos(head - 0.04));
                let ang = (p.1 - q.1).atan2(p.0 - q.0);
                let z = 24.0 * s;
                let skull = [(-0.9, -0.75), (0.1, -0.8), (0.7, -0.5), (1.5, -0.42), (1.55, 0.0), (0.8, 0.1), (1.4, 0.35), (0.9, 0.62), (0.1, 0.7), (-0.9, 0.7)];
                pen.poly2(&place(&skull, p, z, ang, 1.0), h(0xf0392b).a(al), h(0xb3140f).a(al), p.1 - z, p.1 + z, false);
                for side in [-1.0f32, -0.55] {
                    let horn = place(&[(-0.5, side), (-1.7, side - 0.7), (-0.85, side + 0.12)], p, z, ang, 1.0);
                    pen.poly(&horn, h(0xffe7a8).a(al), false);
                }
                let eye = place(&[(0.35, -0.35)], p, z, ang, 1.0)[0];
                pen.glow(eye, z * 0.5, h(0xfff07a).a(al), true);
                pen.disc(eye, z * 0.16, h(0xfff6c8).a(al), false);
                let w1 = place(&[(1.5, -0.3), (2.2, -1.0 + 0.3 * (t * 10.0).sin()), (1.7, -1.9)], p, z, ang, 1.0);
                pen.stroke(&w1, z * 0.1, h(0xffd23f).a(al), false);
                let w2 = place(&[(1.4, 0.2), (2.3, 0.7 + 0.3 * (t * 9.0).cos()), (1.9, 1.7)], p, z, ang, 1.0);
                pen.stroke(&w2, z * 0.1, h(0xffd23f).a(al), false);
                // fire breath
                if i > 0.0 {
                    let mouth = polar(p, z * 1.5, ang);
                    burst(pen, &Emit { n: 40, colors: &[h(0xfff1a8), h(0xffa21f), h(0xff3b1f)], v: (100.0, 300.0), life: (0.25, 0.6), size: (4.0 * s, 9.0 * s), dir: ang, spread: 0.7, stagger: 0.8, ..E }, mouth, i);
                }
            }
            fireball(pen, b, i, 0.7, 78.0 * s, false);
            shockwave(pen, b, i, 0.6, 170.0 * s, 12.0 * s, h(0xffd23f));
            shockwave(pen, b, i - 0.15, 0.6, 120.0 * s, 8.0 * s, h(0xff3b1f));
            burst(pen, &Emit { n: 60, shape: Shape::Spark, colors: &[h(0xffd23f), h(0xff3b1f), h(0x3dffb0)], v: (150.0, 520.0), life: (0.5, 1.2), size: (1.6 * s, 3.0 * s), ..E }, b, i);
        }
        "bomb" => {
            trail(pen, &Emit { n: 30, shape: Shape::Smoke, colors: &[h(0x6a6460).a(0.4)], v: (4.0, 25.0), life: (0.4, 0.9), size: (6.0 * s, 10.0 * s), grow: 2.0, add: false, ..E }, path, t);
            if flying {
                let p = path(f);
                let z = 21.0 * s;
                pen.disc(p, z, h(0x17181c), false);
                pen.glow((p.0 - z * 0.35, p.1 - z * 0.4), z * 0.8, WHITE.a(0.35), true);
                let neck = place(&[(0.55, -0.75), (0.95, -1.1), (0.75, -1.5)], p, z, t * 8.0, 1.0);
                pen.stroke(&neck, z * 0.14, h(0xb9905a), false);
                let tip = neck[2];
                pen.glow(tip, z * 1.3, h(0xffd23f).a(0.9), true);
                for k in 0..6u32 {
                    let ang = TAU * rnd(k, (t * 40.0) as u32);
                    pen.line(tip, polar(tip, z * (0.5 + 0.5 * rnd(k, 5)), ang), 1.6 * s, h(0xfff1a8), true);
                }
            }
            flare(pen, b, i, 0.35, 210.0 * s, h(0xfff1a8));
            fireball(pen, b, i, 1.1, 130.0 * s, true);
            // mushroom cap
            if (0.1..1.6).contains(&i) {
                let u = (i - 0.1) / 1.5;
                for k in 0..14u32 {
                    let ang = PI + PI * (k as f32 + 0.5) / 14.0;
                    let c = (b.0, b.1 - 110.0 * s * out(u));
                    let p = polar(c, 62.0 * s * out(u * 1.3), ang);
                    pen.glow(p, 46.0 * s, h(0x3b302b).mix(h(0x8a7f78), rnd(k, 1)).a(0.6 * fade(u, 0.4)), false);
                }
                for k in 0..7u32 {
                    pen.glow((b.0 + (rnd(k, 2) - 0.5) * 34.0 * s, b.1 - k as f32 * 16.0 * s * out(u)), 34.0 * s, h(0x4a3d36).a(0.5 * fade(u, 0.4)), false);
                }
            }
            shockwave(pen, b, i, 0.6, 260.0 * s, 20.0 * s, h(0xffe7b0));
            shockwave(pen, b, i - 0.1, 0.7, 190.0 * s, 12.0 * s, h(0xff8a1f));
            burst(pen, &Emit { n: 34, shape: Shape::Shard, colors: &[h(0x2a2a2e), h(0x4a4440), h(0x77645a)], v: (220.0, 620.0), life: (0.8, 1.5), size: (5.0 * s, 12.0 * s), grow: 0.9, gravity: 700.0, drag: 1.0, spin: 12.0, add: false, ..E }, b, i);
            burst(pen, &Emit { n: 64, shape: Shape::Spark, colors: &[WHITE, h(0xffd23f), h(0xff6a1a)], v: (200.0, 720.0), life: (0.4, 1.1), size: (1.8 * s, 3.6 * s), gravity: 240.0, ..E }, b, i);
        }
        "glove" => {
            if flying {
                let (p, q) = (path(f), path((f - 0.08).max(0.0)));
                let ang = (p.1 - q.1).atan2(p.0 - q.0);
                for k in 0..9u32 {
                    let off = (k as f32 - 4.0) * 6.0 * s;
                    let o = polar(p, off, ang + FRAC_PI_2);
                    pen.line(o, polar(o, (60.0 + 60.0 * rnd(k, 3)) * s * f, ang + PI), 2.0 * s, WHITE.a(0.5), true);
                }
                let z = 24.0 * s * (1.0 + 0.5 * f);
                pen.disc(p, z, h(0xe0261e), false);
                pen.disc(polar(p, z * 0.75, ang + 1.2), z * 0.5, h(0xc11a14), false);
                let cuff = polar(p, z * 1.1, ang + PI);
                pen.poly(&place(&rect(0.35, 0.75), cuff, z, ang, 1.0), WHITE, false);
                pen.disc((p.0 - z * 0.3, p.1 - z * 0.35), z * 0.28, WHITE.a(0.4), false);
            }
            comic(pen, b, i, 0.7, 120.0 * s, [h(0xff8a1f), h(0xffd23f), WHITE]);
            // the glove sinks in
            if (0.0..0.4).contains(&i) {
                let z = 46.0 * s * (1.0 + 0.25 * (1.0 - out(i / 0.2)));
                let al = fade(i / 0.4, 0.7);
                pen.disc(b, z, h(0xe0261e).a(al), false);
                pen.disc((b.0 + z * 0.55, b.1 + z * 0.5), z * 0.48, h(0xc11a14).a(al), false);
                pen.disc((b.0 - z * 0.3, b.1 - z * 0.35), z * 0.26, WHITE.a(0.4 * al), false);
            }
            shockwave(pen, b, i, 0.45, 170.0 * s, 14.0 * s, WHITE);
            // cracks
            if (0.0..0.8).contains(&i) {
                for k in 0..9u32 {
                    let ang = TAU * k as f32 / 9.0 + rnd(k, 12) * 0.5;
                    let l = (50.0 + 60.0 * rnd(k, 13)) * s * out(i * 5.0);
                    let m = polar(b, l * 0.55, ang + (rnd(k, 14) - 0.5) * 0.5);
                    pen.stroke(&[polar(b, 30.0 * s, ang), m, polar(b, l + 30.0 * s, ang)], 2.6 * s, WHITE.a(0.8 * (1.0 - i / 0.8)), false);
                }
            }
            // seeing stars
            for k in 0..6u32 {
                let u = (i - 0.1) / 1.4;
                if (0.0..1.0).contains(&u) {
                    let ang = TAU * k as f32 / 6.0 + i * 4.5;
                    let p = (b.0 + 74.0 * s * ang.cos(), b.1 - 58.0 * s + 22.0 * s * ang.sin());
                    let z = (9.0 + 4.0 * ang.sin()) * s;
                    pen.poly(&place(&star(5, 0.45), p, z * 1.2, ang, 1.0), h(0xe09a00).a(fade(u, 0.7)), false);
                    pen.poly(&place(&star(5, 0.45), p, z, ang, 1.0), h(0xffe14a).a(fade(u, 0.7)), false);
                }
            }
            burst(pen, &Emit { n: 30, shape: Shape::Spark, colors: &[WHITE, h(0xffd23f)], v: (200.0, 560.0), life: (0.25, 0.6), size: (2.0 * s, 3.6 * s), ..E }, b, i);
        }
        "firecracker" => {
            let reds = [h(0xff3b30), h(0xffd23f), WHITE];
            trail(pen, &Emit { n: 44, shape: Shape::Spark, colors: &reds, v: (40.0, 160.0), life: (0.2, 0.5), size: (1.2 * s, 2.2 * s), gravity: 300.0, ..E }, path, t);
            if flying {
                let p = path(f);
                for k in 0..4 {
                    let q = path((f - 0.05 * k as f32).max(0.0));
                    pen.poly2(&place(&rect(0.38, 1.0), q, 14.0 * s, t * 12.0 + k as f32, 1.0), h(0xff5a4a), h(0xb3140f), q.1 - 14.0 * s, q.1 + 14.0 * s, false);
                }
                pen.glow(p, 40.0 * s, h(0xffd23f).a(0.8), true);
            }
            // one bang after another
            for k in 0..9u32 {
                let d = 0.085 * k as f32;
                let c = if k == 0 { b } else { polar(b, (30.0 + 70.0 * rnd(k, 33)) * s, TAU * rnd(k, 34)) };
                let j = i - d;
                flare(pen, c, j, 0.22, 60.0 * s, h(0xffc24a));
                shockwave(pen, c, j, 0.3, 54.0 * s, 5.0 * s, h(0xffd23f));
                burst(pen, &Emit { n: 12, shape: Shape::Spark, colors: &reds, v: (120.0, 380.0), life: (0.25, 0.6), size: (1.4 * s, 2.6 * s), gravity: 260.0, salt: 60 + k, ..E }, c, j);
                burst(pen, &Emit { n: 4, shape: Shape::Smoke, colors: &[h(0x9a8f8a).a(0.35)], v: (10.0, 40.0), life: (0.5, 0.9), size: (14.0 * s, 22.0 * s), grow: 1.9, gravity: -50.0, add: false, salt: 90 + k, ..E }, c, j);
            }
            // shreds of red paper
            burst(pen, &Emit { n: 40, shape: Shape::Square, colors: &[h(0xe0261e), h(0xff5a4a), h(0xffd23f)], v: (80.0, 320.0), life: (0.8, 1.2), size: (2.0 * s, 4.5 * s), grow: 1.0, gravity: 320.0, drag: 2.0, spin: 8.0, add: false, stagger: 0.5, salt: 5, ..E }, b, i);
        }
        "tomato" => {
            if flying {
                let p = path(f);
                let z = 20.0 * s;
                trail(pen, &Emit { n: 14, shape: Shape::Disc, colors: &[h(0xe5261f)], v: (5.0, 30.0), life: (0.3, 0.5), size: (1.5 * s, 3.5 * s), gravity: 500.0, add: false, ..E }, path, t);
                pen.poly2(&place(&circle(24), p, z, 0.0, 1.08), h(0xff5a45), h(0xb3120d), p.1 - z, p.1 + z, false);
                pen.disc((p.0 - z * 0.35, p.1 - z * 0.35), z * 0.25, WHITE.a(0.6), false);
                for k in 0..5 {
                    let ang = t * 11.0 + TAU * k as f32 / 5.0;
                    let c = (p.0, p.1 - z * 0.75);
                    pen.poly(&place(&leaf(), polar(c, z * 0.35, ang), z * 0.42, ang + FRAC_PI_2, 1.0), h(0x2f9e44), false);
                }
            }
            splat(pen, b, i, 1.6, 92.0 * s, h(0xa80f0b), h(0xe5261f));
            burst(pen, &Emit { n: 46, shape: Shape::Disc, colors: &[h(0xe5261f), h(0xb3120d), h(0xff6b5e)], v: (120.0, 480.0), life: (0.5, 1.1), size: (2.0 * s, 7.0 * s), grow: 0.7, gravity: 760.0, drag: 0.8, add: false, ..E }, b, i);
            burst(pen, &Emit { n: 14, shape: Shape::Leaf, colors: &[h(0xffe9a8)], v: (80.0, 260.0), life: (0.6, 1.1), size: (2.0 * s, 4.0 * s), grow: 1.0, gravity: 600.0, spin: 9.0, add: false, salt: 6, ..E }, b, i);
        }
        "mic" => {
            let neon = [h(0xc6ff3d), h(0x3dfff0), h(0xff3da8)];
            // sound waves rolling toward the target
            if flying {
                let d = (b.1 - a.1).atan2(b.0 - a.0);
                for k in 0..6 {
                    let g = f - k as f32 * 0.09;
                    if g > 0.0 {
                        let p = path(g);
                        let r = (14.0 + 34.0 * g) * s;
                        let arc: Vec<P> = (0..=10).map(|m| polar(p, r, d - 0.9 + 0.18 * m as f32)).collect();
                        pen.stroke(&arc, 7.0 * s * (1.0 - g * 0.4), neon[k % 3].a(0.28), true);
                        pen.stroke(&arc, 2.6 * s, neon[k % 3].a(0.9), true);
                    }
                }
            }
            for k in 0..4u32 {
                shockwave(pen, b, i - 0.13 * k as f32, 0.7, (170.0 - 22.0 * k as f32) * s, 9.0 * s, neon[k as usize % 3]);
            }
            // equalizer around the target
            if (0.0..1.3).contains(&i) {
                let al = fade(i / 1.3, 0.55);
                for k in 0..32u32 {
                    let ang = TAU * k as f32 / 32.0;
                    let beat = (i * 15.0 + rnd(k, 8) * TAU).sin().abs() * (1.0 - i / 1.6);
                    let l = (10.0 + 46.0 * beat) * s;
                    let c = C::hue(k as f32 / 32.0 + i * 0.4);
                    pen.line(polar(b, 62.0 * s, ang), polar(b, 62.0 * s + l, ang), 5.0 * s, c.a(al * 0.9), true);
                }
                pen.glow(b, 70.0 * s, h(0xc6ff3d).a(0.35 * al), true);
            }
            burst(pen, &Emit { n: 18, shape: Shape::Note, colors: &neon, v: (90.0, 260.0), life: (0.9, 1.6), size: (8.0 * s, 14.0 * s), grow: 1.1, gravity: -60.0, spin: 1.5, add: false, stagger: 0.3, ..E }, b, i);
            burst(pen, &Emit { n: 24, shape: Shape::Star, colors: &neon, v: (60.0, 320.0), life: (0.4, 1.0), size: (3.0 * s, 7.0 * s), salt: 7, ..E }, b, i);
        }
        "poop" => {
            let pile = |pen: &mut Pen, p: P, z: f32, al: f32| {
                for (dy, w, hh) in [(0.55, 1.0, 0.42), (0.05, 0.74, 0.38), (-0.42, 0.46, 0.32)] {
                    let c = (p.0, p.1 + dy * z);
                    let e: Vec<P> = circle(22).iter().map(|q| (c.0 + q.0 * w * z, c.1 + q.1 * hh * z)).collect();
                    pen.poly2(&e, h(0x9a6132).a(al), h(0x5c3413).a(al), c.1 - hh * z, c.1 + hh * z, false);
                }
                pen.poly(&place(&[(-0.2, -0.65), (0.18, -1.15), (0.24, -0.6)], p, z, 0.0, 1.0), h(0x8a5528).a(al), false);
                for x in [-0.3f32, 0.3] {
                    pen.disc((p.0 + x * z, p.1 + 0.1 * z), 0.16 * z, WHITE.a(al), false);
                    pen.disc((p.0 + x * z, p.1 + 0.12 * z), 0.08 * z, h(0x17181c).a(al), false);
                }
            };
            if flying {
                pile(pen, path(f), 20.0 * s, 1.0);
            }
            splat(pen, b, i, 1.6, 84.0 * s, h(0x5c3413), h(0x8a5528));
            if (0.0..1.5).contains(&i) {
                let al = fade(i / 1.5, 0.65);
                pile(pen, (b.0, b.1 - 6.0 * s), 34.0 * s * pop((i / 0.2).min(1.0)), al);
                for k in 0..4 {
                    let x = b.0 + (k as f32 - 1.5) * 34.0 * s;
                    let pts: Vec<P> = (0..14).map(|m| (x + (m as f32 * 0.8 + t * 6.0 + k as f32).sin() * 6.0 * s, b.1 - 50.0 * s - m as f32 * 6.0 * s * out(i * 2.0))).collect();
                    pen.stroke(&pts, 4.0 * s, h(0x9acb3c).a(0.55 * al), false);
                }
                for k in 0..4u32 {
                    let ang = t * (6.0 + k as f32) + k as f32 * 1.7;
                    let p = (b.0 + 70.0 * s * ang.cos(), b.1 - 30.0 * s + 34.0 * s * (ang * 1.6).sin());
                    pen.poly(&place(&leaf(), (p.0, p.1 - 3.0 * s), 4.5 * s, 0.9, 1.0), WHITE.a(0.5 * al), false);
                    pen.disc(p, 2.6 * s, h(0x17181c).a(al), false);
                }
            }
            burst(pen, &Emit { n: 30, shape: Shape::Disc, colors: &[h(0x7a4a1e), h(0x5c3413), h(0x9a6132)], v: (110.0, 420.0), life: (0.5, 1.0), size: (2.0 * s, 6.0 * s), gravity: 700.0, drag: 0.8, add: false, ..E }, b, i);
        }
        "glitch" => {
            let neon = [h(0xff3da8), h(0x3dfff0), h(0xc6ff3d)];
            trail(pen, &Emit { n: 46, shape: Shape::Square, colors: &neon, v: (0.0, 40.0), life: (0.1, 0.4), size: (3.0 * s, 8.0 * s), grow: 1.0, radius: 22.0 * s, ..E }, path, t);
            if flying {
                let p = path(f);
                let j = (rnd((t * 30.0) as u32, 9) - 0.5) * 16.0 * s;
                for (k, c) in neon.iter().enumerate() {
                    let o = (p.0 + (k as f32 - 1.0) * 7.0 * s + j, p.1);
                    pen.poly(&place(&rect(1.0, 1.0), o, 15.0 * s, 0.0, 1.0), c.a(0.7), true);
                }
            }
            if (0.0..0.75).contains(&i) {
                let al = fade(i / 0.75, 0.5);
                let tick = (i * 26.0) as u32;
                for k in 0..26u32 {
                    let y = b.1 + (rnd(k, tick) - 0.5) * 240.0 * s;
                    let hh = (2.0 + 13.0 * rnd(k, tick + 1)) * s;
                    let x = b.0 + (rnd(k, tick + 2) - 0.5) * 150.0 * s;
                    let w = (14.0 + 92.0 * rnd(k, tick + 3)) * s;
                    pen.poly(&[(x - w, y), (x + w, y), (x + w, y + hh), (x - w, y + hh)], neon[k as usize % 3].a(al * (0.25 + 0.5 * rnd(k, tick + 4))), true);
                }
                for k in 0..14 {
                    let y = b.1 + (k as f32 - 7.0) * 17.0 * s;
                    pen.line((b.0 - 150.0 * s, y), (b.0 + 150.0 * s, y), 1.0, h(0x3dfff0).a(0.35 * al), true);
                }
                for (k, c) in neon.iter().enumerate() {
                    let o = (rnd(k as u32, tick + 7) - 0.5) * 26.0 * s;
                    let pts: Vec<P> = place(&rect(1.0, 1.0), (b.0 + o, b.1), 56.0 * s * out(i * 5.0), 0.0, 1.0);
                    let mut loopd = pts.clone();
                    loopd.push(pts[0]);
                    pen.stroke(&loopd, 4.0 * s, c.a(al), true);
                }
            }
            shockwave(pen, b, i, 0.5, 150.0 * s, 8.0 * s, h(0xff3da8));
            burst(pen, &Emit { n: 70, shape: Shape::Square, colors: &neon, v: (60.0, 420.0), life: (0.3, 1.0), size: (2.0 * s, 8.0 * s), grow: 0.4, ..E }, b, i);
        }
        "money" => {
            let greens = [h(0x3dd68c), h(0x2fb574), h(0x66e0a5)];
            trail(pen, &Emit { n: 20, shape: Shape::Bill, colors: &greens, v: (20.0, 80.0), life: (0.6, 1.1), size: (8.0 * s, 12.0 * s), grow: 1.0, gravity: 160.0, spin: 5.0, add: false, ..E }, path, t);
            if flying {
                let p = path(f);
                pen.glow(p, 56.0 * s, h(0xffd23f).a(0.5), true);
                for (k, green) in greens.iter().enumerate() {
                    particle(pen, Shape::Bill, p, 24.0 * s, t * 9.0 + k as f32 * 0.5, 0.0, (0.0, 0.0), *green, false);
                }
            }
            rays(pen, b, i, 1.2, 160.0 * s, 12, h(0xffe27a), -0.6);
            flare(pen, b, i, 0.4, 110.0 * s, h(0xffe27a));
            shockwave(pen, b, i, 0.55, 150.0 * s, 9.0 * s, h(0xffd23f));
            burst(pen, &Emit { n: 34, shape: Shape::Bill, colors: &greens, v: (120.0, 380.0), life: (1.2, 1.7), size: (11.0 * s, 17.0 * s), grow: 1.0, gravity: 200.0, drag: 1.9, spin: 6.0, add: false, ..E }, b, i);
            burst(pen, &Emit { n: 22, shape: Shape::Coin, colors: &[h(0xffc21f)], v: (200.0, 440.0), life: (0.9, 1.4), size: (6.0 * s, 10.0 * s), grow: 1.0, dir: -FRAC_PI_2, spread: 2.6, gravity: 680.0, drag: 0.8, spin: 9.0, add: false, salt: 3, ..E }, b, i);
            burst(pen, &Emit { n: 18, shape: Shape::Star, colors: &[h(0xfff1a8)], v: (30.0, 200.0), life: (0.5, 1.2), size: (4.0 * s, 8.0 * s), stagger: 0.5, salt: 11, ..E }, b, i);
        }
        "snow" => {
            let ice = [WHITE, h(0xd6f0ff), h(0x9fdcff)];
            trail(pen, &Emit { n: 44, colors: &ice, v: (6.0, 40.0), life: (0.3, 0.8), size: (2.0 * s, 5.0 * s), gravity: 50.0, radius: 10.0 * s, ..E }, path, t);
            if flying {
                let (p, q) = (path(f), path((f - 0.05).max(0.0)));
                let ang = (p.1 - q.1).atan2(p.0 - q.0);
                pen.glow(p, 46.0 * s, h(0x9fdcff).a(0.6), true);
                let pts = place(&[(1.6, 0.0), (0.2, -0.42), (-0.9, 0.0), (0.2, 0.42)], p, 22.0 * s, ang, 1.0);
                pen.poly(&pts, h(0xbfe9ff), false);
                pen.poly(&pts[0..3], WHITE, false);
            }
            // ice crystals shoot up, then break
            let grown = out(i / 0.22);
            if (0.0..0.8).contains(&i) {
                let al = fade(i / 0.8, 0.75);
                for k in 0..12u32 {
                    let ang = TAU * k as f32 / 12.0 + rnd(k, 15) * 0.3;
                    let l = (54.0 + 64.0 * rnd(k, 16)) * s * grown;
                    let w = (9.0 + 8.0 * rnd(k, 17)) * s;
                    let m = polar(b, l * 0.6, ang);
                    let tip = polar(b, l, ang);
                    let (l1, r1) = (polar(m, w, ang + FRAC_PI_2), polar(m, w, ang - FRAC_PI_2));
                    pen.poly(&[b, l1, tip, r1], h(0x8fd2ff).a(0.8 * al), false);
                    pen.poly(&[b, l1, tip], WHITE.a(0.75 * al), false);
                    pen.line(b, tip, 1.2 * s, WHITE.a(al), true);
                }
                pen.glow(b, 60.0 * s, WHITE.a(0.8 * al), true);
            }
            shockwave(pen, b, i, 0.6, 160.0 * s, 10.0 * s, h(0xbfe9ff));
            let j = i - 0.6;
            burst(pen, &Emit { n: 34, shape: Shape::Shard, colors: &ice, v: (90.0, 360.0), life: (0.5, 1.0), size: (5.0 * s, 12.0 * s), grow: 0.8, gravity: 420.0, drag: 1.2, spin: 8.0, add: false, ..E }, b, j);
            burst(pen, &Emit { n: 30, shape: Shape::Flake, colors: &ice, v: (30.0, 190.0), life: (1.0, 1.6), size: (5.0 * s, 11.0 * s), grow: 0.9, gravity: 46.0, drag: 1.8, spin: 2.0, add: false, salt: 2, ..E }, b, i);
        }
        "hearts" => {
            let pinks = [h(0xff3da8), h(0xff7cc4), h(0xff5f7e)];
            trail(pen, &Emit { n: 26, shape: Shape::Heart, colors: &pinks, v: (8.0, 40.0), life: (0.4, 0.9), size: (4.0 * s, 8.0 * s), grow: 0.5, gravity: -90.0, spin: 2.0, add: false, ..E }, path, t);
            if flying {
                comet(pen, path, f, 9.0 * s, h(0xffd6ec), h(0xff3da8));
                let p = path(f);
                pen.poly(&place(&heart(), p, 22.0 * s, (t * 10.0).sin() * 0.2, 1.0), h(0xff2e8a), false);
                pen.disc((p.0 - 9.0 * s, p.1 - 9.0 * s), 4.0 * s, WHITE.a(0.8), false);
            }
            // a big heart beats twice, then bursts
            if (0.0..0.75).contains(&i) {
                let beat = 1.0 + 0.22 * ((i * 16.0).sin().max(0.0)) * (1.0 - i);
                let z = 56.0 * s * pop((i / 0.2).min(1.0)) * beat;
                let al = fade(i / 0.75, 0.8);
                pen.glow(b, z * 2.0, h(0xff3da8).a(0.5 * al), true);
                pen.poly2(&place(&heart(), b, z, 0.0, 1.0), h(0xff7cc4).a(al), h(0xe0186e).a(al), b.1 - z, b.1 + z, false);
                pen.poly(&place(&circle(14), (b.0 - z * 0.42, b.1 - z * 0.42), z * 0.2, -0.6, 0.6), WHITE.a(0.75 * al), false);
            }
            shockwave(pen, b, i - 0.05, 0.5, 130.0 * s, 8.0 * s, h(0xff7cc4));
            shockwave(pen, b, i - 0.42, 0.5, 150.0 * s, 8.0 * s, h(0xff3da8));
            burst(pen, &Emit { n: 36, shape: Shape::Heart, colors: &pinks, v: (90.0, 330.0), life: (0.6, 1.1), size: (5.0 * s, 12.0 * s), grow: 0.7, gravity: -70.0, spin: 2.5, add: false, ..E }, b, i - 0.6);
            burst(pen, &Emit { n: 28, shape: Shape::Star, colors: &[h(0xffd6ec), WHITE], v: (40.0, 280.0), life: (0.5, 1.0), size: (3.0 * s, 7.0 * s), salt: 4, ..E }, b, i - 0.55);
        }
        "chrome" => {
            let prism = [h(0xccf2ff), h(0xf9ccff), h(0xd9ffcc), h(0xccd9ff)];
            trail(pen, &Emit { n: 40, shape: Shape::Star, colors: &prism, v: (4.0, 40.0), life: (0.3, 0.8), size: (3.0 * s, 8.0 * s), spin: 4.0, ..E }, path, t);
            if flying {
                let p = path(f);
                for k in 0..6 {
                    pen.ring(p, (24.0 - 3.4 * k as f32) * s, 2.6 * s, C::hue(k as f32 / 6.0 + t * 1.6).a(0.9), true);
                }
                pen.glow(p, 50.0 * s, WHITE.a(0.5), true);
            }
            flare(pen, b, i, 0.4, 130.0 * s, h(0xe6f4ff));
            if (0.0..1.1).contains(&i) {
                let al = fade(i / 1.1, 0.4);
                for k in 0..9 {
                    let r = (18.0 + 15.0 * k as f32) * s * out(i * 2.2);
                    pen.ring(b, r, 4.5 * s, C::hue(k as f32 / 9.0 - i * 1.4).a(0.7 * al), true);
                }
                rays(pen, b, i, 1.1, 190.0 * s, 16, WHITE, 1.2);
            }
            // glints
            for k in 0..9u32 {
                let u = (i - 0.1 * rnd(k, 42) - 0.05 * k as f32) / 0.5;
                if (0.0..1.0).contains(&u) {
                    let p = polar(b, (30.0 + 100.0 * rnd(k, 43)) * s, TAU * rnd(k, 44));
                    let z = (12.0 + 16.0 * rnd(k, 45)) * s * (u * PI).sin();
                    pen.poly(&place(&star(4, 0.1), p, z * 1.6, 0.0, 1.0), WHITE.a((u * PI).sin()), true);
                    pen.glow(p, z * 1.4, C::hue(rnd(k, 46)).a(0.5), true);
                }
            }
            burst(pen, &Emit { n: 40, shape: Shape::Shard, colors: &prism, v: (110.0, 420.0), life: (0.5, 1.2), size: (4.0 * s, 10.0 * s), grow: 0.5, spin: 8.0, ..E }, b, i);
        }
        // boom
        _ => {
            if flying {
                comet(pen, path, f, 11.0 * s, h(0xfff1a8), h(0xffa21f));
            }
            comic(pen, b, i, 0.6, 104.0 * s, [h(0xff5a1f), h(0xffc21f), h(0xfff6c8)]);
            flare(pen, b, i, 0.25, 110.0 * s, h(0xffd23f));
            shockwave(pen, b, i, 0.5, 150.0 * s, 12.0 * s, h(0xffd23f));
            burst(pen, &Emit { n: 14, shape: Shape::Smoke, colors: &[h(0x8a7f78).a(0.5), h(0x5c534e).a(0.5)], v: (60.0, 190.0), life: (0.6, 1.2), size: (14.0 * s, 24.0 * s), grow: 1.8, gravity: -40.0, add: false, ..E }, b, i - 0.06);
            burst(pen, &Emit { n: 40, shape: Shape::Spark, colors: &[WHITE, h(0xffd23f), h(0xff6a1a)], v: (160.0, 520.0), life: (0.35, 0.9), size: (1.6 * s, 3.0 * s), gravity: 140.0, salt: 2, ..E }, b, i);
        }
    }
}

// ---------- auras ----------

/// Does this aura draw anything?
#[uniffi::export]
pub fn has_aura(id: String) -> bool {
    AURAS.contains(&id.as_str())
}

/// One frame of an idle aura around an avatar of `radius` in the middle of a `w` × `h` view, at `t_ms` on any clock.
/// Empty for "no aura".
#[uniffi::export]
pub fn aura_frame(id: String, t_ms: u64, w: f32, h: f32, radius: f32) -> Vec<u8> {
    if !has_aura(id.clone()) {
        return vec![];
    }
    let mut pen = Pen::default();
    let c: P = (w / 2.0, h / 2.0);
    // the clock may be anything: keep it small enough for f32
    let t = (t_ms % 3_600_000) as f32 / 1000.0;
    let x = C::hex;
    // `n` particles, each reborn every `life` seconds: position on the rim, age 0–1, random keys
    let each = |n: u32, life: f32, f: &mut dyn FnMut(u32, f32, f32)| {
        for i in 0..n {
            let q = t / life + rnd(i, 1);
            let (round, u) = (q.floor(), q.fract());
            f(i.wrapping_mul(7919).wrapping_add(round as u32), u, rnd(i, round as u32 + 2));
        }
    };
    let pen = &mut pen;
    match id.as_str() {
        "au.flame" => {
            pen.glow(c, radius * 1.7, x(0xff6a1a).a(0.28 + 0.06 * (t * 7.0).sin()), true);
            each(34, 0.85, &mut |k, u, r| {
                let p = polar(c, radius * (0.92 + 0.15 * rnd(k, 4)), TAU * r);
                let p = (p.0 + (t * 6.0 + k as f32).sin() * 2.0, p.1 - radius * 0.75 * u);
                let col = x(0xfff1a8).mix(x(0xff8a1f), u * 2.0).mix(x(0xe0261e), u * 2.0 - 1.0);
                pen.glow(p, radius * (0.3 - 0.2 * u), col.a(0.7 * (1.0 - u)), true);
            });
        }
        "au.sparkle" => each(9, 1.5, &mut |k, u, r| {
            let p = polar(c, radius * (0.95 + 0.4 * rnd(k, 4)), TAU * r);
            let a = (u * PI).sin();
            particle(pen, Shape::Star, p, radius * 0.17 * a * (0.6 + 0.6 * rnd(k, 5)), u * 3.0, 0.0, (0.0, 0.0), if rnd(k, 6) < 0.5 { x(0xc6ff3d) } else { WHITE }.a(a), true);
        }),
        "au.hearts" => each(8, 2.0, &mut |k, u, r| {
            let p = polar(c, radius, TAU * r);
            let p = (p.0 + (u * 6.0 + k as f32).sin() * radius * 0.12, p.1 - radius * 0.8 * u);
            particle(pen, Shape::Heart, p, radius * 0.17 * (0.7 + 0.5 * rnd(k, 5)), (u * 5.0).sin(), 0.0, (0.0, 0.0), pick(&[x(0xff3da8), x(0xff7cc4)], rnd(k, 6)).a((u * PI).sin()), false);
        }),
        "au.snow" => {
            pen.ring(c, radius * 1.05, 1.5, x(0xbfe9ff).a(0.35), true);
            each(12, 2.6, &mut |k, u, r| {
                let p = (c.0 + (r - 0.5) * radius * 2.6 + (u * 5.0 + k as f32).sin() * radius * 0.1, c.1 - radius * 1.2 + radius * 2.4 * u);
                particle(pen, Shape::Flake, p, radius * 0.13 * (0.7 + 0.6 * rnd(k, 5)), u * 3.0, 0.0, (0.0, 0.0), x(0xe8f7ff).a((u * PI).sin()), false);
            });
        }
        "au.money" => each(7, 2.2, &mut |k, u, r| {
            let p = (c.0 + (r - 0.5) * radius * 2.6, c.1 - radius * 1.2 + radius * 2.3 * u);
            let (shape, col) = if rnd(k, 5) < 0.55 { (Shape::Bill, x(0x3dd68c)) } else { (Shape::Coin, x(0xffc21f)) };
            particle(pen, shape, p, radius * 0.2, u * 4.0 + r * 6.0, u * 9.0, (0.0, 0.0), col.a((u * PI).sin()), false);
        }),
        "au.chrome" => {
            for k in 0..40 {
                let a = TAU * k as f32 / 40.0;
                let col = C::hue(k as f32 / 40.0 + t * 0.35);
                pen.line(polar(c, radius * 1.06, a), polar(c, radius * 1.06, a + 0.17), radius * 0.09, col.a(0.75), true);
            }
            for k in 0..4 {
                let a = t * 1.7 + TAU * k as f32 / 4.0;
                let p = polar(c, radius * 1.06, a);
                particle(pen, Shape::Star, p, radius * 0.2, a, 0.0, (0.0, 0.0), WHITE, true);
            }
        }
        "au.glitch" => {
            let tick = (t * 11.0) as u32;
            for k in 0..11u32 {
                let p = polar(c, radius * (0.9 + 0.35 * rnd(k, tick)), TAU * rnd(k, tick + 1));
                let w = radius * (0.08 + 0.28 * rnd(k, tick + 2));
                let hh = radius * (0.03 + 0.06 * rnd(k, tick + 3));
                pen.poly(&[(p.0 - w, p.1), (p.0 + w, p.1), (p.0 + w, p.1 + hh), (p.0 - w, p.1 + hh)], pick(&[x(0xff3da8), x(0x3dfff0), x(0xc6ff3d)], rnd(k, tick + 4)).a(0.85), true);
            }
        }
        _ => each(6, 2.0, &mut |k, u, r| {
            let p = polar(c, radius * 1.05, TAU * r);
            let p = (p.0 + (u * 5.0).sin() * radius * 0.15, p.1 - radius * 0.6 * u);
            particle(pen, Shape::Note, p, radius * 0.2, (u * 4.0).sin(), 0.0, (0.0, 0.0), C::hue(rnd(k, 6)).a((u * PI).sin()), false);
        }),
    }
    std::mem::take(pen).bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(id: &str, t: u32) -> Vec<u8> {
        hit_frame(id.into(), t, 390.0, 800.0, 195.0, 700.0, 195.0, 120.0)
    }

    #[test]
    fn every_effect_draws() {
        for id in HIT_EFFECTS {
            let info = hit_info(id.into());
            assert_eq!(info.id, id);
            assert!(info.shake > 0.0 && info.impact_ms < info.duration_ms);
            let mut most = 0;
            for t in (0..info.duration_ms).step_by(16) {
                let f = frame(id, t);
                let ops = check(&f).unwrap_or_else(|| panic!("{id} at {t} ms is malformed"));
                assert!(f.len() < 160_000, "{id} at {t} ms: {} bytes", f.len());
                most = most.max(ops.len());
                // more than emoji
                assert!(ops.iter().filter(|o| **o == 6).count() <= 2, "{id}");
            }
            assert!(most > 40, "{id} is too plain ({most})");
            let at_impact = check(&frame(id, info.impact_ms + 60)).unwrap();
            assert!(at_impact.len() > 20, "{id} has no impact");
            assert!(frame(id, info.duration_ms).is_empty(), "{id} ends");
            let last = check(&frame(id, info.duration_ms - 1)).unwrap();
            assert!(last.len() < 12, "{id} stops abruptly ({})", last.len());
            assert_eq!(frame(id, 500), frame(id, 500), "the same every time");
        }
        assert_eq!(hit_info("fx.nope".into()).id, "fx.boom");
        assert!(hit_frame("fx.boom".into(), 100, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0).is_empty());
    }

    #[test]
    fn effects_look_different() {
        let all: std::collections::HashSet<Vec<u8>> = HIT_EFFECTS.iter().map(|id| frame(id, 520)).collect();
        assert_eq!(all.len(), HIT_EFFECTS.len());
    }

    #[test]
    fn auras_draw() {
        for id in AURAS {
            for t in [0u64, 500, 1_795_363_644_276] {
                let f = aura_frame(id.into(), t, 110.0, 110.0, 34.0);
                assert!(!check(&f).unwrap_or_else(|| panic!("{id}")).is_empty(), "{id} at {t}");
            }
        }
        assert!(aura_frame("au.none".into(), 5, 100.0, 100.0, 30.0).is_empty());
        assert!(has_aura("au.flame".into()) && !has_aura("au.none".into()));
    }
}
