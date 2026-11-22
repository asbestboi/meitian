//! Draw commands. Hit effects, auras and arena scenery are drawn by the core as a flat list of commands, so
//! iPhone and Android show exactly the same picture; the apps only have a small renderer for these eight.
//!
//! A drawing is little-endian `f32`s. Every command starts with its code; colours are r, g, b, a (0–1); `add` 1 =
//! additive (light) blending. Coordinates are points, the origin is the top left corner.
//!
//! ```text
//! 1 GLOW   x y r            rgba add            soft light, fading to nothing at r
//! 2 DISC   x y r            rgba add
//! 3 RING   x y r width      rgba add
//! 4 LINE   x1 y1 x2 y2 w    rgba add            round ends
//! 5 POLY   n  rgba(top) rgba(bottom) y1 y2 add  x y × n    filled, vertical gradient from y1 to y2
//! 6 GLYPH  codepoint x y size degrees alpha
//! 7 FLASH  rgba                                 the whole view
//! 8 STROKE n w rgba add                         x y × n    an open line with round joins
//! ```

pub(crate) type P = (f32, f32);

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct C(pub f32, pub f32, pub f32, pub f32);

impl C {
    /// 0xRRGGBB
    pub const fn hex(v: u32) -> C {
        C(((v >> 16) & 0xff) as f32 / 255.0, ((v >> 8) & 0xff) as f32 / 255.0, (v & 0xff) as f32 / 255.0, 1.0)
    }
    pub fn a(self, alpha: f32) -> C {
        C(self.0, self.1, self.2, (self.3 * alpha).clamp(0.0, 1.0))
    }
    pub fn mix(self, o: C, t: f32) -> C {
        let l = |a: f32, b: f32| a + (b - a) * t.clamp(0.0, 1.0);
        C(l(self.0, o.0), l(self.1, o.1), l(self.2, o.2), l(self.3, o.3))
    }
    /// A colour of the rainbow, `h` in turns.
    pub fn hue(h: f32) -> C {
        let f = |o: f32| 0.5 + 0.5 * (std::f32::consts::TAU * (h + o)).cos();
        C(0.55 + 0.45 * f(0.0), 0.55 + 0.45 * f(-0.333), 0.55 + 0.45 * f(-0.667), 1.0)
    }
}

pub(crate) const WHITE: C = C::hex(0xffffff);

#[derive(Default)]
pub(crate) struct Pen {
    pub v: Vec<f32>,
}

impl Pen {
    fn color(&mut self, c: C) {
        self.v.extend([c.0, c.1, c.2, c.3]);
    }
    fn add(&mut self, on: bool) {
        self.v.push(on as u8 as f32);
    }
    pub fn glow(&mut self, p: P, r: f32, c: C, add: bool) {
        if c.3 <= 0.004 || r <= 0.2 {
            return;
        }
        self.v.extend([1.0, p.0, p.1, r]);
        self.color(c);
        self.add(add);
    }
    pub fn disc(&mut self, p: P, r: f32, c: C, add: bool) {
        if c.3 <= 0.004 || r <= 0.1 {
            return;
        }
        self.v.extend([2.0, p.0, p.1, r]);
        self.color(c);
        self.add(add);
    }
    pub fn ring(&mut self, p: P, r: f32, w: f32, c: C, add: bool) {
        if c.3 <= 0.004 || r <= 0.1 || w <= 0.05 {
            return;
        }
        self.v.extend([3.0, p.0, p.1, r, w]);
        self.color(c);
        self.add(add);
    }
    pub fn line(&mut self, a: P, b: P, w: f32, c: C, add: bool) {
        if c.3 <= 0.004 || w <= 0.05 {
            return;
        }
        self.v.extend([4.0, a.0, a.1, b.0, b.1, w]);
        self.color(c);
        self.add(add);
    }
    pub fn poly(&mut self, pts: &[P], c: C, add: bool) {
        self.poly2(pts, c, c, 0.0, 1.0, add);
    }
    /// Vertical gradient: `top` at `y1`, `bottom` at `y2`.
    pub fn poly2(&mut self, pts: &[P], top: C, bottom: C, y1: f32, y2: f32, add: bool) {
        if pts.len() < 3 || (top.3 <= 0.004 && bottom.3 <= 0.004) {
            return;
        }
        self.v.extend([5.0, pts.len() as f32]);
        self.color(top);
        self.color(bottom);
        self.v.extend([y1, y2]);
        self.add(add);
        for p in pts {
            self.v.extend([p.0, p.1]);
        }
    }
    pub fn glyph(&mut self, ch: char, p: P, size: f32, degrees: f32, alpha: f32) {
        if alpha <= 0.01 || size <= 0.5 {
            return;
        }
        self.v.extend([6.0, ch as u32 as f32, p.0, p.1, size, degrees, alpha.min(1.0)]);
    }
    pub fn flash(&mut self, c: C) {
        if c.3 > 0.004 {
            self.v.push(7.0);
            self.color(c);
        }
    }
    pub fn stroke(&mut self, pts: &[P], w: f32, c: C, add: bool) {
        if pts.len() < 2 || c.3 <= 0.004 || w <= 0.05 {
            return;
        }
        self.v.extend([8.0, pts.len() as f32, w]);
        self.color(c);
        self.add(add);
        for p in pts {
            self.v.extend([p.0, p.1]);
        }
    }
    pub fn bytes(self) -> Vec<u8> {
        self.v.into_iter().flat_map(f32::to_le_bytes).collect()
    }
}

/// Repeatable random number in 0–1 from two keys.
pub(crate) fn rnd(i: u32, salt: u32) -> f32 {
    let mut z = ((i as u64) << 32 | salt as u64).wrapping_add(0x9e37_79b9_7f4a_7c15).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z ^= z >> 29;
    z = z.wrapping_mul(0x94d0_49bb_1331_11eb);
    z ^= z >> 32;
    (z & 0xff_ffff) as f32 / 0x100_0000 as f32
}

pub(crate) fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

pub(crate) fn polar(c: P, r: f32, a: f32) -> P {
    (c.0 + r * a.cos(), c.1 + r * a.sin())
}

/// Rotates and scales a shape given around (0, 0) and moves it to `c`. `squash` flattens it sideways (a turning coin).
pub(crate) fn place(shape: &[P], c: P, size: f32, rot: f32, squash: f32) -> Vec<P> {
    let (s, k) = rot.sin_cos();
    shape
        .iter()
        .map(|&(x, y)| {
            let (x, y) = (x * size * squash, y * size);
            (c.0 + x * k - y * s, c.1 + x * s + y * k)
        })
        .collect()
}

/// A star polygon with `n` points.
pub(crate) fn star(n: usize, inner: f32) -> Vec<P> {
    (0..n * 2)
        .map(|i| polar((0.0, 0.0), if i % 2 == 0 { 1.0 } else { inner }, std::f32::consts::PI * i as f32 / n as f32 - std::f32::consts::FRAC_PI_2))
        .collect()
}

pub(crate) fn heart() -> Vec<P> {
    (0..26)
        .map(|i| {
            let t = std::f32::consts::TAU * i as f32 / 26.0;
            let x = 16.0 * t.sin().powi(3);
            let y = 13.0 * t.cos() - 5.0 * (2.0 * t).cos() - 2.0 * (3.0 * t).cos() - (4.0 * t).cos();
            (x / 17.0, -y / 17.0)
        })
        .collect()
}

pub(crate) fn petal() -> Vec<P> {
    vec![
        (0.0, 1.0), (-0.42, 0.45), (-0.55, -0.1), (-0.42, -0.62), (-0.16, -0.95), (0.0, -0.74), (0.16, -0.95), (0.42, -0.62), (0.55, -0.1), (0.42, 0.45),
    ]
}

pub(crate) fn leaf() -> Vec<P> {
    vec![(0.0, -1.0), (0.22, -0.5), (0.3, 0.0), (0.2, 0.5), (0.0, 1.0), (-0.2, 0.5), (-0.3, 0.0), (-0.22, -0.5)]
}

pub(crate) fn rect(w: f32, h: f32) -> Vec<P> {
    vec![(-w, -h), (w, -h), (w, h), (-w, h)]
}

pub(crate) fn circle(n: usize) -> Vec<P> {
    (0..n).map(|i| polar((0.0, 0.0), 1.0, std::f32::consts::TAU * i as f32 / n as f32)).collect()
}

/// Walks a drawing and returns its commands' codes; `None` when it's malformed (used by the tests).
#[cfg(test)]
pub(crate) fn check(bytes: &[u8]) -> Option<Vec<u32>> {
    let v: Vec<f32> = bytes.chunks(4).map(|b| Some(f32::from_le_bytes(b.try_into().ok()?))).collect::<Option<_>>()?;
    if v.iter().any(|f| !f.is_finite()) {
        return None;
    }
    let (mut i, mut out) = (0, vec![]);
    while i < v.len() {
        let n = match v[i] as u32 {
            1 | 2 => 9,
            3 => 10,
            4 => 11,
            5 => 13 + 2 * *v.get(i + 1)? as usize,
            6 => 7,
            7 => 5,
            8 => 8 + 2 * *v.get(i + 1)? as usize,
            _ => return None,
        };
        out.push(v[i] as u32);
        i += n;
    }
    (i == v.len()).then_some(out)
}
