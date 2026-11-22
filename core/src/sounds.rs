//! Every sound effect, synthesized here so iPhone and Android play exactly the same thing (no audio files).
//! The apps get 16-bit mono PCM at 44.1 kHz and only have to play it.

pub const SAMPLE_RATE: u32 = 44_100;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum SoundId {
    // learning
    Correct,
    Wrong,
    NewWord,
    HeartLost,
    OutOfHearts,
    MicOn,
    MicOff,
    // interface
    Tap,
    TabSwitch,
    ToggleOn,
    ToggleOff,
    SheetOpen,
    SheetClose,
    Swoosh,
    Tick,
    Go,
    // rewards
    Coin,
    Purchase,
    LevelUp,
    Streak,
    Milestone,
    NodeUnlock,
    ArenaUnlock,
    Win,
    Lose,
    ReelTick,
    ReelStop,
    Jackpot,
    // battles
    Countdown,
    Crit,
    Ko,
    Victory,
    Defeat,
    Draw,
}

#[uniffi::export]
pub fn all_sounds() -> Vec<SoundId> {
    use SoundId::*;
    vec![
        Correct, Wrong, NewWord, HeartLost, OutOfHearts, MicOn, MicOff, Tap, TabSwitch, ToggleOn, ToggleOff, SheetOpen,
        SheetClose, Swoosh, Tick, Go, Coin, Purchase, LevelUp, Streak, Milestone, NodeUnlock, ArenaUnlock, Win, Lose,
        ReelTick, ReelStop, Jackpot, Countdown, Crit, Ko, Victory, Defeat, Draw,
    ]
}

#[derive(Clone, Copy)]
enum Wave {
    Sine,
    Triangle,
    Square,
}
use Wave::*;

/// One note: frequency, seconds, waveform, how far it bends (Hz over its length), volume.
#[derive(Clone, Copy)]
struct Note(f64, f64, Wave, f64, f64);

fn n(freq: f64, dur: f64) -> Note {
    Note(freq, dur, Sine, 0.0, 1.0)
}

impl Note {
    fn wave(mut self, w: Wave) -> Note {
        self.2 = w;
        self
    }
    fn bend(mut self, hz: f64) -> Note {
        self.3 = hz;
        self
    }
    fn vol(mut self, v: f64) -> Note {
        self.4 = v;
        self
    }
}

type Samples = Vec<f64>;

/// Notes one after the other, lightly bit-crushed for a lo-fi grit.
fn tones(notes: &[Note]) -> Samples {
    let sr = SAMPLE_RATE as f64;
    let mut out = Vec::new();
    for &Note(freq, dur, wave, bend, vol) in notes {
        let count = (dur * sr) as usize;
        let mut phase = 0.0f64;
        for i in 0..count {
            let t = i as f64 / sr;
            phase += (freq + bend * (t / dur)) / sr;
            let x = phase.fract();
            let v = match wave {
                Triangle => 1.0 - 4.0 * (x - 0.5).abs(),
                Square => {
                    if x < 0.5 {
                        0.6
                    } else {
                        -0.6
                    }
                }
                Sine => (std::f64::consts::TAU * x).sin(),
            };
            let v = (v * 8.0).round() / 8.0;
            let env = (t / 0.005).min(1.0) * (-3.5 * t / dur).exp();
            out.push(v * env * vol * 0.5);
        }
    }
    out
}

/// Filtered noise: a thud or crack, or with `sweep` a whoosh. `tone` 0–1 = dull to bright.
fn noise(dur: f64, vol: f64, tone: f64, sweep: bool) -> Samples {
    let sr = SAMPLE_RATE as f64;
    let mut rng = fastrand::Rng::with_seed(7 + (dur * 1000.0) as u64 + (tone * 100.0) as u64);
    let mut last = 0.0;
    (0..(dur * sr) as usize)
        .map(|i| {
            let t = i as f64 / sr;
            let a = if sweep { 0.05 + 0.6 * (t / dur) } else { tone };
            last += a * ((rng.f64() * 2.0 - 1.0) - last);
            let env = if sweep { (std::f64::consts::PI * t / dur).sin() } else { (-6.0 * t / dur).exp() };
            last * env * vol
        })
        .collect()
}

fn mix(layers: &[Samples]) -> Samples {
    let len = layers.iter().map(Vec::len).max().unwrap_or(0);
    (0..len).map(|i| layers.iter().filter_map(|l| l.get(i)).sum()).collect()
}

/// `s` starting `secs` later.
fn after(secs: f64, s: Samples) -> Samples {
    let mut out = vec![0.0; (secs * SAMPLE_RATE as f64) as usize];
    out.extend(s);
    out
}

fn arp(freqs: &[f64], dur: f64, wave: Wave) -> Samples {
    tones(&freqs.iter().map(|&f| n(f, dur).wave(wave)).collect::<Vec<_>>())
}

fn synth(id: SoundId) -> Samples {
    use SoundId::*;
    match id {
        Correct => tones(&[n(880.0, 0.08).wave(Triangle), n(1320.0, 0.14).wave(Triangle)]),
        Wrong => tones(&[n(200.0, 0.24).wave(Square).bend(-80.0).vol(0.6)]),
        NewWord => tones(&[n(1319.0, 0.07).vol(0.45), n(1760.0, 0.22).vol(0.45)]),
        HeartLost => mix(&[
            noise(0.08, 0.4, 0.35, false),
            tones(&[n(440.0, 0.1).wave(Triangle).bend(-120.0).vol(0.7), n(262.0, 0.2).wave(Triangle).bend(-90.0).vol(0.7)]),
        ]),
        OutOfHearts => tones(&[
            n(392.0, 0.16).wave(Triangle).vol(0.7),
            n(311.0, 0.16).wave(Triangle).vol(0.7),
            n(233.0, 0.36).wave(Triangle).bend(-50.0).vol(0.7),
        ]),
        MicOn => tones(&[n(740.0, 0.06), n(1110.0, 0.08)]),
        MicOff => tones(&[n(1110.0, 0.06), n(740.0, 0.08)]),
        Tap => tones(&[n(620.0, 0.035).wave(Triangle).bend(-160.0).vol(0.3)]),
        TabSwitch => tones(&[n(520.0, 0.03).wave(Triangle).vol(0.3), n(700.0, 0.045).wave(Triangle).vol(0.3)]),
        ToggleOn => tones(&[n(560.0, 0.04).vol(0.4), n(840.0, 0.06).vol(0.4)]),
        ToggleOff => tones(&[n(840.0, 0.04).vol(0.4), n(560.0, 0.06).vol(0.4)]),
        SheetOpen => mix(&[noise(0.12, 0.14, 0.2, true), tones(&[n(420.0, 0.12).bend(260.0).vol(0.25)])]),
        SheetClose => mix(&[noise(0.1, 0.12, 0.2, true), tones(&[n(680.0, 0.1).bend(-260.0).vol(0.22)])]),
        Swoosh => noise(0.16, 0.35, 0.35, true),
        Tick => tones(&[n(660.0, 0.07).wave(Triangle).vol(0.7)]),
        Go => tones(&[n(990.0, 0.2).wave(Triangle)]),
        Coin => tones(&[n(1568.0, 0.06).wave(Square).vol(0.5), n(2093.0, 0.16).wave(Square).vol(0.5)]),
        Purchase => mix(&[
            tones(&[n(1047.0, 0.06).wave(Square).vol(0.4), n(1319.0, 0.06).wave(Square).vol(0.4), n(1568.0, 0.2).wave(Square).vol(0.4)]),
            after(0.12, noise(0.16, 0.25, 0.8, false)),
        ]),
        LevelUp => mix(&[
            arp(&[523.0, 659.0, 784.0, 1047.0, 1319.0, 1568.0], 0.085, Triangle),
            after(0.5, tones(&[n(2093.0, 0.35).vol(0.5)])),
            after(0.5, tones(&[n(1568.0, 0.35).vol(0.4)])),
        ]),
        Streak => mix(&[noise(0.3, 0.22, 0.3, true), tones(&[n(392.0, 0.1).wave(Triangle), n(587.0, 0.1).wave(Triangle), n(880.0, 0.25).wave(Triangle).bend(60.0)])]),
        Milestone => mix(&[
            arp(&[659.0, 784.0, 988.0, 1319.0], 0.1, Triangle),
            after(0.4, tones(&[n(1319.0, 0.4).vol(0.6)])),
            after(0.4, tones(&[n(1976.0, 0.4).vol(0.35)])),
        ]),
        NodeUnlock => tones(&[n(587.0, 0.07).wave(Triangle).vol(0.7), n(880.0, 0.07).wave(Triangle).vol(0.7), n(1175.0, 0.18).wave(Triangle).vol(0.7)]),
        ArenaUnlock => mix(&[
            tones(&[n(110.0, 1.4).wave(Triangle).bend(-30.0).vol(1.0)]),
            noise(1.0, 0.45, 0.12, false),
            after(0.35, arp(&[392.0, 523.0, 659.0, 784.0], 0.12, Triangle)),
            after(0.85, tones(&[n(1047.0, 0.8).vol(0.6)])),
            after(0.85, tones(&[n(784.0, 0.8).vol(0.5)])),
        ]),
        Win => arp(&[523.0, 659.0, 784.0, 1047.0, 1047.0], 0.12, Triangle),
        Lose => tones(&[n(392.0, 0.16).wave(Square).vol(0.55), n(330.0, 0.16).wave(Square).vol(0.55), n(262.0, 0.16).wave(Square).vol(0.55)]),
        ReelTick => tones(&[n(1100.0, 0.025).wave(Square).vol(0.4)]),
        ReelStop => mix(&[noise(0.1, 0.6, 0.25, false), tones(&[n(150.0, 0.14).bend(-60.0)])]),
        Jackpot => mix(&[
            arp(&[784.0, 988.0, 1175.0, 1568.0, 1175.0, 1568.0, 1976.0, 2349.0], 0.09, Square),
            after(0.72, arp(&[2093.0, 2637.0, 3136.0], 0.14, Triangle)),
            after(0.1, noise(0.9, 0.12, 0.9, false)),
        ]),
        Countdown => tones(&[n(587.0, 0.12).wave(Triangle).vol(0.9)]),
        Crit => mix(&[noise(0.09, 0.8, 0.9, false), tones(&[n(1760.0, 0.06).wave(Square).vol(0.6), n(2637.0, 0.14).wave(Square).bend(-400.0).vol(0.6)])]),
        Ko => mix(&[noise(0.5, 1.0, 0.15, false), tones(&[n(130.0, 0.6).wave(Triangle).bend(-90.0)]), after(0.08, tones(&[n(98.0, 0.5).wave(Square).bend(-60.0).vol(0.5)]))]),
        Victory => mix(&[
            arp(&[523.0, 523.0, 523.0, 659.0, 784.0], 0.11, Triangle),
            after(0.55, tones(&[n(1047.0, 0.6).wave(Triangle)])),
            after(0.55, tones(&[n(784.0, 0.6).vol(0.6)])),
        ]),
        Defeat => tones(&[
            n(392.0, 0.2).wave(Triangle).vol(0.7),
            n(370.0, 0.2).wave(Triangle).vol(0.7),
            n(349.0, 0.2).wave(Triangle).vol(0.7),
            n(330.0, 0.5).wave(Triangle).bend(-40.0).vol(0.7),
        ]),
        Draw => tones(&[n(523.0, 0.16).wave(Triangle).vol(0.7), n(523.0, 0.16).wave(Triangle).vol(0.7), n(466.0, 0.3).wave(Triangle).vol(0.7)]),
    }
}

/// The impact of a hit effect (`EffectSpec.sound`).
fn synth_hit(key: &str) -> Samples {
    let thud = |f: f64| tones(&[n(f, 0.18).bend(-0.4 * f)]);
    match key {
        "fire" => mix(&[noise(0.45, 0.7, 0.18, true), noise(0.3, 0.5, 0.1, false), thud(80.0)]),
        "zap" => mix(&[noise(0.12, 0.9, 1.0, false), tones(&[n(2400.0, 0.22).wave(Square).bend(-2200.0).vol(0.7)])]),
        "envelope" => mix(&[noise(0.1, 0.4, 0.6, false), after(0.05, arp(&[1568.0, 1976.0, 2349.0, 1976.0], 0.06, Square))]),
        "blossom" => mix(&[noise(0.25, 0.15, 0.4, true), arp(&[1047.0, 1319.0, 1568.0, 2093.0], 0.07, Sine)]),
        "dragon" => mix(&[
            tones(&[n(90.0, 0.7).wave(Square).bend(70.0).vol(0.9)]),
            noise(0.7, 0.6, 0.2, true),
            after(0.25, tones(&[n(220.0, 0.4).wave(Triangle).bend(-120.0)])),
        ]),
        "bomb" => mix(&[noise(0.6, 1.1, 0.12, false), tones(&[n(70.0, 0.6).wave(Triangle).bend(-40.0).vol(1.2)])]),
        "glove" => mix(&[noise(0.06, 0.9, 0.5, false), thud(160.0), after(0.1, tones(&[n(1200.0, 0.3).vol(0.25)]))]),
        "firecracker" => {
            let pops: Vec<Samples> = (0..6).map(|i| after(0.055 * i as f64, noise(0.05, 0.9 - 0.08 * i as f64, 0.95, false))).collect();
            mix(&pops)
        }
        "tomato" => mix(&[noise(0.14, 0.8, 0.22, false), tones(&[n(240.0, 0.14).bend(-190.0).vol(0.8)])]),
        "mic" => mix(&[thud(120.0), after(0.06, tones(&[n(1900.0, 0.35).wave(Square).bend(500.0).vol(0.25)])), noise(0.1, 0.5, 0.4, false)]),
        "poop" => mix(&[tones(&[n(180.0, 0.28).wave(Square).bend(-110.0).vol(0.6)]), after(0.1, noise(0.16, 0.5, 0.15, false))]),
        "glitch" => tones(&[
            n(1400.0, 0.03).wave(Square).vol(0.6),
            n(300.0, 0.03).wave(Square).vol(0.6),
            n(2100.0, 0.03).wave(Square).vol(0.6),
            n(150.0, 0.05).wave(Square).vol(0.6),
            n(900.0, 0.03).wave(Square).vol(0.6),
            n(90.0, 0.1).wave(Square).vol(0.6),
        ]),
        "chrome" => mix(&[tones(&[n(1200.0, 0.5).bend(900.0).vol(0.5)]), tones(&[n(1803.0, 0.5).bend(900.0).vol(0.35)]), noise(0.1, 0.4, 0.9, false)]),
        "money" => {
            let coins: Vec<Samples> =
                (0..5).map(|i| after(0.06 * i as f64, tones(&[n(1760.0 + 180.0 * i as f64, 0.1).wave(Square).vol(0.35)]))).collect();
            mix(&coins)
        }
        "snow" => mix(&[noise(0.5, 0.4, 0.7, true), tones(&[n(2093.0, 0.3).vol(0.3)]), after(0.08, tones(&[n(2637.0, 0.3).vol(0.25)]))]),
        "hearts" => mix(&[thud(110.0), after(0.16, thud(110.0)), after(0.1, arp(&[784.0, 988.0, 1175.0], 0.08, Sine))]),
        // boom and anything unknown
        _ => mix(&[noise(0.14, 0.9, 0.35, false), tones(&[n(95.0, 0.18).bend(-40.0)])]),
    }
}

/// How loud a sound should feel: interface clicks stay softer than rewards and hits.
fn loudness(id: SoundId) -> f64 {
    use SoundId::*;
    match id {
        Tap | TabSwitch | SheetOpen | SheetClose | ReelTick => 0.45,
        ToggleOn | ToggleOff | Swoosh | Tick | MicOn | MicOff | NewWord => 0.65,
        _ => 1.0,
    }
}

/// Brings a sound up to the level of the spoken voice: the peak to full scale, then a soft limiter lifts the quiet
/// parts (text-to-speech is heavily compressed, plain tones would sound faint next to it). 16-bit little-endian.
fn pcm(s: Samples, level: f64) -> Vec<u8> {
    const DRIVE: f64 = 2.6;
    let peak = s.iter().fold(1e-9f64, |m, v| m.max(v.abs()));
    let top = DRIVE.tanh();
    s.into_iter()
        .flat_map(|v| ((((v / peak * DRIVE).tanh() / top * 0.97 * level) * i16::MAX as f64).round() as i16).to_le_bytes())
        .collect()
}

/// 16-bit little-endian mono PCM at 44.1 kHz.
#[uniffi::export]
pub fn sound_pcm(id: SoundId) -> Vec<u8> {
    pcm(synth(id), loudness(id))
}

/// The sound of a hit effect cosmetic, by its `EffectSpec.sound`.
#[uniffi::export]
pub fn hit_sound_pcm(key: String) -> Vec<u8> {
    pcm(synth_hit(&key), 1.0)
}

#[uniffi::export]
pub fn sound_sample_rate() -> u32 {
    SAMPLE_RATE
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loud(bytes: &[u8]) -> i32 {
        bytes.chunks(2).map(|b| (i16::from_le_bytes([b[0], b[1]]) as i32).abs()).max().unwrap_or(0)
    }

    #[test]
    fn every_sound_is_short_and_audible() {
        let all = all_sounds();
        let unique: std::collections::HashSet<_> = all.iter().collect();
        assert_eq!(unique.len(), all.len());
        for id in all {
            let b = sound_pcm(id);
            let secs = b.len() as f64 / 2.0 / SAMPLE_RATE as f64;
            assert!(b.len() % 2 == 0 && (0.02..2.5).contains(&secs), "{id:?} lasts {secs}");
            assert!(loud(&b) > 13_000, "{id:?} can be heard");
            assert_eq!(b, sound_pcm(id), "{id:?} is always the same");
        }
    }

    /// Loudness of the loudest tenth of a second, 0–1.
    fn rms(bytes: &[u8]) -> f64 {
        let v: Vec<f64> = bytes.chunks(2).map(|b| i16::from_le_bytes([b[0], b[1]]) as f64 / 32768.0).collect();
        v.chunks((SAMPLE_RATE / 10) as usize).map(|c| (c.iter().map(|x| x * x).sum::<f64>() / c.len() as f64).sqrt()).fold(0.0, f64::max)
    }

    #[test]
    fn as_loud_as_speech() {
        // recorded speech sits around 0.1–0.2
        use SoundId::*;
        for id in [Correct, Wrong, HeartLost, Coin, Win, Lose, LevelUp, Jackpot, Countdown, Crit, Ko, Victory] {
            assert!(rms(&sound_pcm(id)) > 0.18, "{id:?}: {}", rms(&sound_pcm(id)));
        }
        assert!(rms(&sound_pcm(Tap)) < rms(&sound_pcm(Correct)), "taps stay in the background");
    }

    #[test]
    fn every_hit_effect_sounds_different() {
        let mut seen = std::collections::HashSet::new();
        for id in crate::effects::HIT_EFFECTS {
            let key = crate::effects::hit_info(id.to_string()).sound;
            let b = hit_sound_pcm(key.clone());
            assert!(loud(&b) > 30_000, "{id}");
            assert!(seen.insert(b), "{id} shares its sound ({key})");
        }
        assert_eq!(hit_sound_pcm("nope".into()), hit_sound_pcm("boom".into()));
    }
}
