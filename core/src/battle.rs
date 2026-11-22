//! The battle itself: one state machine per phone, for 2–4 players. The app feeds it what arrives on the room's
//! WebSocket, the player's answers and the clock (`tick`, about ten times a second), sends out what it returns,
//! and draws `view()`.
//!
//! One phone is the host and referees; the server names it, and names the next one when it drops. Every phone
//! keeps the whole state, so a new host carries on where the old one stopped. Reaction times are measured on each
//! phone from when its question appeared, so a slow connection doesn't cost anyone a round.
//!
//! Messages (JSON, relayed by the server's room with the sender's id as `from`):
//! hello · start · round · answer · result · progress · score · finished · lobby · resume · leave · report

use std::collections::BTreeMap;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::game::*;
use crate::online::{profile_from, OnlineProfile};
use crate::sounds::SoundId;

/// Version of the messages above. Apps up to 1.12 speak version 1 (two players only) and can't play with newer ones.
pub const PROTOCOL: u32 = 2;

const COUNT_MS: u64 = 800;
/// After a right answer arrives, wait this long for a faster one still on its way.
const GRACE_MS: u64 = 300;
const RESULT_MS: u64 = 1_600;
const LONG_RESULT_MS: u64 = 2_800;
const RESTART_MS: u64 = 1_200;
/// Battle Royale: from this round on, the slowest right answer is knocked out too.
const ROYALE_SLOWEST_FROM: u32 = 14;
/// Public groups start without players who haven't connected by then.
const LATE_MS: u64 = 12_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BattlePhase {
    /// Not in the room yet (or the first player there).
    Waiting,
    Lobby,
    Countdown,
    Playing,
    RoundResult,
    Finished,
    /// The room is gone, or refused us.
    Gone,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BattlePlayer {
    pub id: String,
    pub name: String,
    /// Their app's player card (JSON), "" until it arrives.
    pub card: String,
    pub profile: Option<OnlineProfile>,
    pub level: u8,
    pub here: bool,
    pub hp: u32,
    pub score: u32,
    /// Knocked out (or gone): watching.
    pub out: bool,
    pub done: bool,
    pub team: u32,
    pub place: u32,
    /// Already answered this round (host only knows about others).
    pub answered: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BattleResult {
    /// 1 = first. Players who tie share a place.
    pub place: u32,
    pub players: u32,
    /// Two players: win, loss or draw. Groups: first place is a win, last a loss.
    pub outcome: Outcome,
    /// A 1v1 between two matched players: counts for wins, losses, streak and rating.
    pub ranked: bool,
    /// HP left / 5, or the score.
    pub bonus: u32,
    pub damage: u32,
    pub fastest_ms: Option<u32>,
    /// Coins for a group game (1v1 pays by outcome and streak, see `match_coins`).
    pub group_coins: u32,
    /// The other player in a 1v1.
    pub rival: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum BattleOut {
    /// Send this on the socket.
    Send { json: String },
    Sound { sound: SoundId },
    /// Fly the attacker's hit effect at the targets.
    Hit { attacker: String, targets: Vec<String>, damage: u32, crit: bool },
    /// Pay out and record.
    Finished { result: BattleResult },
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BattleView {
    pub phase: BattlePhase,
    /// Why the battle can't go on (`Gone`), in plain words.
    pub problem: String,
    pub mode: Option<BattleMode>,
    pub me: String,
    pub host: String,
    pub is_host: bool,
    /// A party or public group (as opposed to a 1v1).
    pub group: bool,
    pub party: bool,
    /// In playing order; the roster order in the lobby.
    pub players: Vec<BattlePlayer>,
    pub count: u32,
    pub question: Option<BattleQuestion>,
    pub index: u32,
    pub my_option: Option<u32>,
    pub answered: bool,
    pub locked: bool,
    /// Show the right answer.
    pub reveal: bool,
    pub round_winner: String,
    pub last_damage: u32,
    pub last_ms: u32,
    pub time_left_ms: u64,
    pub time_total_ms: u64,
    pub lives: u32,
    pub max_lives: u32,
    /// Points modes: the score that wins.
    pub target: u32,
    /// I'm out and watching.
    pub spectating: bool,
    /// Everybody else dropped, or I did: the game waits.
    pub paused: bool,
    pub connected: bool,
    pub can_start: bool,
    pub can_rematch: bool,
    pub result: Option<BattleResult>,
    pub rating: Option<BattleRating>,
    /// A short note ("Anna left"), "" when there's nothing to say.
    pub notice: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct BattleRating {
    pub counted: bool,
    pub rating: i32,
    pub delta: i32,
}

#[derive(Debug, Clone, Default)]
struct P {
    id: String,
    profile: Option<OnlineProfile>,
    card: String,
    name: String,
    level: u8,
    swears: bool,
    /// Protocol of their app; 0 until their hello arrives.
    v: u32,
    here: bool,
    /// In the current game.
    playing: bool,
    hp: u32,
    score: u32,
    out: bool,
    forfeit: bool,
    done: bool,
    team: u32,
    place: u32,
}

/// A player's part of the state, as it goes over the wire.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Standing {
    id: String,
    hp: u32,
    score: u32,
    out: bool,
    #[serde(default)]
    place: u32,
    #[serde(default)]
    done: bool,
    #[serde(default)]
    team: u32,
    #[serde(default)]
    forfeit: bool,
}

impl From<&P> for Standing {
    fn from(p: &P) -> Self {
        Standing { id: p.id.clone(), hp: p.hp, score: p.score, out: p.out, place: p.place, done: p.done, team: p.team, forfeit: p.forfeit }
    }
}

struct State {
    card: Value,
    me: String,
    host: String,
    kind: String,
    connected: bool,
    joined_at: u64,
    players: Vec<P>,
    phase: BattlePhase,
    problem: String,
    mode: BattleMode,
    /// Played as soon as everybody is here.
    auto: Option<BattleMode>,
    qs: Vec<BattleQuestion>,
    index: u32,
    /// Bumped whenever a round is shown, so late timers and answers can't hit the wrong one.
    round_at: u64,
    deadline: u64,
    total: u64,
    grace: Option<u64>,
    /// Rounds that wait to (re)start: host only.
    next_round: Option<(u32, u64)>,
    answers: BTreeMap<String, (bool, u32)>,
    my_option: Option<u32>,
    answered: bool,
    locked_until: u64,
    reveal: bool,
    round_winner: String,
    last_damage: u32,
    last_ms: u32,
    last_count: u32,
    count_ends: u64,
    /// Race: when my next question comes.
    next_at: Option<u64>,
    lives: u32,
    damage_dealt: u32,
    fastest: Option<u32>,
    was_paused: bool,
    result: Option<BattleResult>,
    rating: Option<BattleRating>,
    notice: String,
    notice_until: u64,
    out: Vec<BattleOut>,
}

impl State {
    fn new(card: Value, auto: Option<BattleMode>) -> State {
        State {
            card,
            me: String::new(),
            host: String::new(),
            kind: "duo".into(),
            connected: false,
            joined_at: 0,
            players: vec![],
            phase: BattlePhase::Waiting,
            problem: String::new(),
            mode: auto.unwrap_or(BattleMode::Duel),
            auto,
            qs: vec![],
            index: 0,
            round_at: 0,
            deadline: 0,
            total: 0,
            grace: None,
            next_round: None,
            answers: BTreeMap::new(),
            my_option: None,
            answered: false,
            locked_until: 0,
            reveal: false,
            round_winner: String::new(),
            last_damage: 0,
            last_ms: 0,
            last_count: 0,
            count_ends: 0,
            next_at: None,
            lives: 0,
            damage_dealt: 0,
            fastest: None,
            was_paused: false,
            result: None,
            rating: None,
            notice: String::new(),
            notice_until: 0,
            out: vec![],
        }
    }

    // MARK: helpers

    fn send(&mut self, v: Value) {
        self.out.push(BattleOut::Send { json: v.to_string() });
    }

    fn sound(&mut self, sound: SoundId) {
        self.out.push(BattleOut::Sound { sound });
    }

    fn say(&mut self, text: String, now: u64) {
        self.notice = text;
        self.notice_until = now + 3_500;
    }

    fn p(&self, id: &str) -> Option<&P> {
        self.players.iter().find(|p| p.id == id)
    }

    fn p_mut(&mut self, id: &str) -> Option<&mut P> {
        self.players.iter_mut().find(|p| p.id == id)
    }

    fn name(&self, id: &str) -> String {
        self.p(id).map(|p| p.name.clone()).filter(|n| !n.is_empty()).unwrap_or_else(|| "someone".into())
    }

    fn is_host(&self) -> bool {
        !self.me.is_empty() && self.host == self.me
    }

    fn in_game(&self) -> bool {
        matches!(self.phase, BattlePhase::Countdown | BattlePhase::Playing | BattlePhase::RoundResult)
    }

    fn duo(&self) -> bool {
        self.kind == "duo"
    }

    /// Players still in the game.
    fn alive(&self) -> impl Iterator<Item = &P> {
        self.players.iter().filter(|p| p.playing && !p.out)
    }

    fn game_size(&self) -> u32 {
        self.players.iter().filter(|p| p.playing).count() as u32
    }

    /// Rounds wait while fewer than two players who are still in it are connected.
    fn paused(&self) -> bool {
        if !self.in_game() {
            return false;
        }
        let here = self.alive().filter(|p| p.here).count();
        !self.connected || (!self.mode.is_race() && here < 2 && self.alive().count() >= 2)
    }

    fn standings(&self) -> Vec<Standing> {
        self.players.iter().filter(|p| p.playing).map(Standing::from).collect()
    }

    fn apply(&mut self, list: Vec<Standing>) {
        for s in list {
            let me = s.id == self.me;
            if let Some(p) = self.p_mut(&s.id) {
                p.playing = true;
                p.hp = s.hp;
                p.out = s.out;
                p.place = s.place;
                p.team = s.team;
                p.forfeit = s.forfeit;
                // in a race I know my own score best
                if !me || !p.done {
                    p.score = p.score.max(s.score);
                }
                p.done |= s.done;
            }
        }
    }

    // MARK: lobby

    fn hello(&mut self) {
        let card = self.card.clone();
        self.send(json!({ "t": "hello", "v": PROTOCOL, "card": card }));
    }

    /// `[{id, here, profile}]` from the server. Keeps what we know about players who stay.
    fn roster(&mut self, list: &Value, remove: bool) {
        let Some(list) = list.as_array() else { return };
        let mut ids = Vec::new();
        for e in list {
            let Some(id) = e["id"].as_str() else { continue };
            ids.push(id.to_string());
            let profile = profile_from(&e["profile"]);
            let here = e["here"].as_bool().unwrap_or(false);
            if self.p(id).is_none() {
                self.players.push(P { id: id.into(), level: 1, hp: MAX_HP, ..Default::default() });
            }
            let p = self.p_mut(id).unwrap();
            p.here = here;
            if let Some(profile) = profile {
                if p.name.is_empty() {
                    p.name = profile.nickname.clone();
                    p.level = profile.level.clamp(1, 9) as u8;
                }
                p.profile = Some(profile);
            }
        }
        if remove {
            let in_game = self.in_game();
            for p in self.players.iter_mut().filter(|p| !ids.contains(&p.id)) {
                p.here = false;
            }
            // someone who left mid-game stays on the scoreboard until it's over
            self.players.retain(|p| ids.contains(&p.id) || (in_game && p.playing));
        }
    }

    /// Our own hello never comes back to us: fill in our own entry.
    fn fill_me(&mut self) {
        let card = self.card.clone();
        let me = self.me.clone();
        if let Some(p) = self.p_mut(&me) {
            p.read_card(&card);
            p.v = PROTOCOL;
            p.here = true;
        }
    }

    fn ready(&self) -> Vec<String> {
        self.players.iter().filter(|p| p.here && p.v == PROTOCOL).map(|p| p.id.clone()).collect()
    }

    fn can_start(&self) -> bool {
        self.is_host() && self.connected && matches!(self.phase, BattlePhase::Lobby) && self.ready().len() >= 2
    }

    fn check_compatible(&mut self) {
        if !self.duo() || self.in_game() || self.phase == BattlePhase::Finished {
            return;
        }
        let mine = self.p(&self.me).is_some_and(|p| p.swears);
        let Some(other) = self.players.iter().find(|p| p.id != self.me && p.v > 0) else { return };
        let problem = if other.v < PROTOCOL {
            format!("{} has an older version of Měitiān. Both of you need the newest one to battle.", other.name)
        } else if other.v > PROTOCOL {
            "Update Měitiān to battle this player.".to_string()
        } else if !can_match(mine, other.swears) {
            format!(
                "You have swear words {}, {} has them {}. Players can only battle with the same setting (Profile → Settings → Content).",
                if mine { "ON" } else { "OFF" },
                other.name,
                if other.swears { "ON" } else { "OFF" }
            )
        } else {
            return;
        };
        self.problem = problem;
        self.phase = BattlePhase::Gone;
        self.sound(SoundId::Wrong);
    }

    fn auto_start(&mut self, now: u64) {
        let Some(mode) = self.auto else { return };
        if !self.can_start() {
            return;
        }
        let ready = self.ready().len();
        let late = self.kind == "group" && now >= self.joined_at + LATE_MS;
        let min = mode_info(mode).min_players as usize;
        if ready == self.players.len() || (late && ready >= min) {
            self.auto = None;
            self.start(mode, now);
        } else if late && ready >= 2 {
            // too few for this mode: let the host pick another one
            self.auto = None;
            self.say("Not everyone showed up. Pick a game for the players who are here.".into(), now);
        }
    }

    // MARK: a game

    fn start(&mut self, mode: BattleMode, now: u64) {
        if !self.can_start() {
            return;
        }
        let ids = self.ready();
        let info = mode_info(mode);
        if !(info.min_players..=info.max_players).contains(&(ids.len() as u32)) {
            return;
        }
        let playing: Vec<&P> = self.players.iter().filter(|p| ids.contains(&p.id)).collect();
        // everyone should know the words: the lowest level counts, street words only when all have them on
        let level = playing.iter().map(|p| p.level).min().unwrap_or(1);
        let swears = playing.iter().all(|p| p.swears);
        let qs = make_questions(mode, level, swears, fastrand::u64(..));
        if qs.is_empty() {
            return;
        }
        self.send(json!({ "t": "start", "mode": info.wire, "players": ids, "q": qs }));
        self.begin(mode, ids, qs, now);
    }

    fn begin(&mut self, mode: BattleMode, ids: Vec<String>, qs: Vec<BattleQuestion>, now: u64) {
        self.mode = mode;
        self.auto = None;
        self.qs = qs;
        self.index = 0;
        self.rating = None;
        self.result = None;
        self.lives = mode.lives();
        self.damage_dealt = 0;
        self.fastest = None;
        self.next_round = None;
        self.next_at = None;
        self.was_paused = false;
        self.clear_round();
        for p in self.players.iter_mut() {
            let seat = ids.iter().position(|id| *id == p.id);
            p.playing = seat.is_some();
            p.hp = MAX_HP;
            p.score = 0;
            p.out = false;
            p.forfeit = false;
            p.done = false;
            p.place = 0;
            p.team = seat.unwrap_or(0) as u32 % 2;
        }
        // seats decide the teams, so everybody lists the players the same way
        self.players.sort_by_key(|p| ids.iter().position(|id| *id == p.id).unwrap_or(usize::MAX));
        self.phase = BattlePhase::Countdown;
        self.last_count = 3;
        self.count_ends = now + 3 * COUNT_MS;
        self.sound(SoundId::Countdown);
    }

    fn clear_round(&mut self) {
        self.answers.clear();
        self.my_option = None;
        self.answered = false;
        self.locked_until = 0;
        self.reveal = false;
        self.grace = None;
        self.round_winner.clear();
    }

    fn question(&self) -> Option<&BattleQuestion> {
        if self.qs.is_empty() {
            None
        } else {
            self.qs.get(self.index as usize % self.qs.len())
        }
    }

    fn show_round(&mut self, i: u32, ms: u64, now: u64) {
        self.clear_round();
        self.index = i;
        self.round_at = now;
        self.total = ms;
        self.deadline = now + ms;
        self.next_round = None;
        self.phase = BattlePhase::Playing;
    }

    fn host_round(&mut self, i: u32, now: u64) {
        let ms = self.mode.round_ms(i);
        self.send(json!({ "t": "round", "i": i, "ms": ms }));
        self.show_round(i, ms, now);
    }

    fn start_race(&mut self, now: u64) {
        self.clear_round();
        self.index = 0;
        self.round_at = now;
        self.total = self.mode.race_ms();
        self.deadline = now + self.total;
        self.phase = BattlePhase::Playing;
    }

    // MARK: answering

    fn answer(&mut self, a: BattleAnswer, now: u64) {
        if self.phase != BattlePhase::Playing || self.answered || now < self.locked_until || self.paused() {
            return;
        }
        let me = self.me.clone();
        if self.p(&me).is_none_or(|p| !p.playing || p.out || p.done) {
            return;
        }
        let Some(right) = self.question().map(|q| q.is_right(&a)) else { return };
        let ms = now.saturating_sub(self.round_at) as u32;
        if let BattleAnswer::Option { index } = a {
            self.my_option = Some(index);
        }
        self.sound(if right { SoundId::Correct } else { SoundId::Wrong });
        if self.mode.is_race() {
            self.race_answer(right, now);
            return;
        }
        if !right && self.mode.retries() {
            self.locked_until = now + 1_000;
            return;
        }
        self.answered = true;
        if right {
            self.fastest = Some(self.fastest.map_or(ms, |f| f.min(ms)));
        }
        if self.is_host() {
            self.receive(&me, self.index, right, ms, now);
        } else {
            let i = self.index;
            self.send(json!({ "t": "answer", "i": i, "ok": right, "ms": ms }));
        }
    }

    fn race_answer(&mut self, right: bool, now: u64) {
        let me = self.me.clone();
        self.answered = true;
        if right {
            if let Some(p) = self.p_mut(&me) {
                p.score += 1;
            }
            self.next_at = Some(now + 350);
        } else {
            self.reveal = true;
            self.next_at = Some(now + 1_000);
            if self.mode == BattleMode::Survival {
                self.lives = self.lives.saturating_sub(1);
                if self.lives == 0 {
                    if let Some(p) = self.p_mut(&me) {
                        p.done = true; // out of lives: the score stands
                    }
                }
            }
        }
        self.progress(now);
    }

    /// Tell everyone how my race is going.
    fn progress(&mut self, now: u64) {
        let me = self.me.clone();
        let Some((score, done)) = self.p(&me).map(|p| (p.score, p.done)) else { return };
        self.send(json!({ "t": "progress", "s": score, "done": done }));
        self.scoreboard();
        self.check_race(now);
    }

    /// The host's scoreboard, kept by the server for anyone who (re)joins.
    fn scoreboard(&mut self) {
        if self.is_host() {
            let s = self.standings();
            self.send(json!({ "t": "score", "players": s }));
        }
    }

    // MARK: refereeing (host)

    /// Players whose answer the round waits for.
    fn expected(&self) -> Vec<String> {
        self.alive().filter(|p| p.here).map(|p| p.id.clone()).collect()
    }

    fn receive(&mut self, id: &str, i: u32, right: bool, ms: u32, now: u64) {
        if !self.is_host() || i != self.index || self.phase != BattlePhase::Playing || self.answers.contains_key(id) {
            return;
        }
        if self.p(id).is_none_or(|p| !p.playing || p.out) {
            return;
        }
        self.answers.insert(id.to_string(), (right, ms));
        self.check_round(now);
    }

    fn check_round(&mut self, now: u64) {
        if !self.is_host() || self.phase != BattlePhase::Playing || self.mode.is_race() {
            return;
        }
        let last_standing = self.mode.rules() == Rules::LastStanding;
        if !last_standing && self.grace.is_none() && self.answers.values().any(|a| a.0) {
            self.grace = Some(now + GRACE_MS);
        }
        let all_in = self.expected().iter().all(|id| self.answers.contains_key(id));
        if all_in && (last_standing || self.grace.is_none()) {
            self.resolve(now);
        }
    }

    fn resolve(&mut self, now: u64) {
        if !self.is_host() || self.phase != BattlePhase::Playing {
            return;
        }
        let mut targets: Vec<String> = vec![];
        let mut winner = String::new();
        let mut damage = 0;
        let mut ms = 0;
        if self.mode.rules() == Rules::LastStanding {
            let alive: Vec<String> = self.alive().map(|p| p.id.clone()).collect();
            let mut wrong: Vec<String> = alive.iter().filter(|id| !self.answers.get(*id).is_some_and(|a| a.0)).cloned().collect();
            if wrong.is_empty() && self.index >= ROYALE_SLOWEST_FROM && alive.len() > 1 {
                // nobody slips up: the slowest goes, so it ends
                wrong.extend(alive.iter().max_by_key(|id| self.answers.get(*id).map_or(u32::MAX, |a| a.1)).cloned());
            }
            // all wrong: nobody goes, or there'd be no winner
            if wrong.len() < alive.len() {
                targets = wrong;
                self.knock_out(&targets.clone());
            }
        } else {
            let best = self.answers.iter().filter(|(_, a)| a.0).min_by_key(|(_, a)| a.1).map(|(id, a)| (id.clone(), a.1));
            if let Some((id, t)) = best {
                winner = id.clone();
                ms = t;
                if self.mode.rules() == Rules::Points {
                    if let Some(p) = self.p_mut(&id) {
                        p.score += 1;
                    }
                } else {
                    damage = self.mode.damage(t);
                    let team = self.mode == BattleMode::Team2v2;
                    let mine = self.p(&id).map_or(0, |p| p.team);
                    targets = self.alive().filter(|p| p.id != id && (!team || p.team != mine)).map(|p| p.id.clone()).collect();
                    if team {
                        // one health bar for the whole team, knocked out or not
                        for p in self.players.iter_mut().filter(|p| p.playing && p.team != mine) {
                            p.hp = p.hp.saturating_sub(damage);
                        }
                    } else {
                        for p in self.players.iter_mut().filter(|p| targets.contains(&p.id)) {
                            p.hp = p.hp.saturating_sub(damage);
                        }
                    }
                    let dead: Vec<String> = self.alive().filter(|p| p.hp == 0).map(|p| p.id.clone()).collect();
                    self.knock_out(&dead);
                }
            }
        }
        let standings = self.standings();
        let i = self.index;
        self.send(json!({ "t": "result", "i": i, "w": winner, "players": standings, "d": damage, "ms": ms, "to": targets }));
        self.scoreboard();
        self.show_result(winner, targets, damage, ms, now);
        self.deadline = now + if self.mode.retries() { LONG_RESULT_MS } else { RESULT_MS };
    }

    /// Everyone knocked out in the same round shares a place.
    fn knock_out(&mut self, ids: &[String]) {
        let left = self.alive().filter(|p| !ids.contains(&p.id)).count() as u32;
        for p in self.players.iter_mut().filter(|p| ids.contains(&p.id)) {
            p.out = true;
            p.place = left + 1;
        }
    }

    fn show_result(&mut self, winner: String, targets: Vec<String>, damage: u32, ms: u32, _now: u64) {
        self.reveal = true;
        self.phase = BattlePhase::RoundResult;
        self.last_damage = damage;
        self.last_ms = ms;
        let hit = !targets.is_empty() && damage > 0;
        if hit {
            let crit = ms < CRIT_MS;
            if winner == self.me {
                self.damage_dealt += damage;
            }
            if crit {
                self.sound(SoundId::Crit);
            }
            let ko = targets.iter().any(|id| self.p(id).is_some_and(|p| p.out));
            if ko {
                self.sound(SoundId::Ko);
            }
            self.out.push(BattleOut::Hit { attacker: winner.clone(), targets, damage, crit });
        } else if !targets.is_empty() {
            self.sound(SoundId::Ko); // battle royale
        } else if !winner.is_empty() {
            self.sound(if winner == self.me { SoundId::Coin } else { SoundId::Tick });
        }
        self.round_winner = winner;
    }

    /// Is there a winner? (Between rounds, or after someone left.)
    fn is_over(&self) -> bool {
        match self.mode.rules() {
            Rules::Hp | Rules::LastStanding => {
                if self.mode == BattleMode::Team2v2 {
                    let teams: std::collections::HashSet<u32> = self.alive().map(|p| p.team).collect();
                    teams.len() <= 1
                } else {
                    self.alive().count() <= 1
                }
            }
            Rules::Points => {
                let (target, rounds) = self.mode.target();
                self.alive().count() <= 1 || self.alive().any(|p| p.score >= target) || self.index + 1 >= rounds
            }
            Rules::Race => self.alive().count() <= 1 || self.alive().all(|p| p.done),
        }
    }

    /// Final places: 1 = best, ties share, people who left come last.
    fn places(&self) -> Vec<(String, u32)> {
        let playing: Vec<&P> = self.players.iter().filter(|p| p.playing).collect();
        if self.mode == BattleMode::Team2v2 {
            let best = self.alive().map(|p| p.team).next();
            return playing.iter().map(|p| (p.id.clone(), if Some(p.team) == best { 1 } else { 2 })).collect();
        }
        match self.mode.rules() {
            Rules::Hp | Rules::LastStanding => {
                playing.iter().map(|p| (p.id.clone(), if p.out { p.place.max(1) } else { 1 })).collect()
            }
            Rules::Points | Rules::Race => {
                let key = |p: &P| (!p.forfeit, p.score);
                playing.iter().map(|p| (p.id.clone(), 1 + playing.iter().filter(|o| key(o) > key(p)).count() as u32)).collect()
            }
        }
    }

    fn check_race(&mut self, now: u64) {
        if !self.is_host() || !self.mode.is_race() || !self.in_game() || self.phase == BattlePhase::Countdown {
            return;
        }
        // a phone that went quiet doesn't hold up the result for long
        if self.is_over() || now > self.deadline + 6_000 {
            self.host_finish(now);
        }
    }

    fn host_finish(&mut self, now: u64) {
        let places = self.places();
        let wire: Vec<Value> = places.iter().map(|(id, n)| json!({ "id": id, "place": n })).collect();
        let standings = self.standings();
        self.send(json!({ "t": "finished", "places": wire, "players": standings }));
        self.scoreboard();
        self.finish(places, now);
    }

    fn finish(&mut self, places: Vec<(String, u32)>, _now: u64) {
        if self.phase == BattlePhase::Finished {
            return;
        }
        for (id, place) in &places {
            if let Some(p) = self.p_mut(id) {
                p.place = *place;
            }
        }
        self.phase = BattlePhase::Finished;
        self.next_round = None;
        self.reveal = true;
        let me = self.me.clone();
        let Some(mine) = self.p(&me).filter(|p| p.playing).cloned() else { return };
        let players = self.game_size();
        let place = mine.place.max(1);
        let last = places.iter().map(|(_, n)| *n).max().unwrap_or(1);
        let first_shared = places.iter().filter(|(_, n)| *n == 1).count() > 1;
        let team = self.mode == BattleMode::Team2v2;
        let outcome = match place {
            1 if first_shared && !team => Outcome::Draw,
            1 => Outcome::Win,
            n if n == last => Outcome::Loss,
            _ => Outcome::Draw,
        };
        let ranked = self.duo();
        let rival = self.players.iter().find(|p| p.playing && p.id != me).map(|p| p.id.clone()).unwrap_or_default();
        let result = BattleResult {
            place,
            players,
            outcome,
            ranked,
            bonus: if self.mode.rules() == Rules::Hp { mine.hp / 5 } else { mine.score },
            damage: self.damage_dealt,
            fastest_ms: self.fastest,
            group_coins: if ranked { 0 } else { group_coins(if team && place == 2 { 3 } else { place }, players) },
            rival,
        };
        if ranked {
            let won = match outcome {
                Outcome::Win => Some(true),
                Outcome::Loss => Some(false),
                Outcome::Draw => None,
            };
            self.send(json!({ "t": "report", "won": won }));
        }
        self.sound(match outcome {
            Outcome::Win => SoundId::Victory,
            Outcome::Loss => SoundId::Defeat,
            Outcome::Draw => SoundId::Draw,
        });
        self.result = Some(result.clone());
        self.out.push(BattleOut::Finished { result });
    }

    fn enter_lobby(&mut self) {
        self.phase = BattlePhase::Lobby;
        self.next_round = None;
        self.result = None;
        self.rating = None;
        self.clear_round();
        // people who left during the game disappear now (in a 1v1 the other player is still expected)
        if !self.duo() {
            self.players.retain(|p| p.here || !p.forfeit);
        }
        for p in self.players.iter_mut() {
            p.playing = false;
        }
    }

    // MARK: people coming and going

    fn forfeit(&mut self, id: &str, now: u64) {
        let name = self.name(id);
        let host_gone = self.host == id;
        let playing = self.in_game() && self.p(id).is_some_and(|p| p.playing && !p.forfeit);
        if let Some(p) = self.p_mut(id) {
            p.here = false;
        }
        if host_gone {
            if let Some(next) = self.players.iter().find(|p| p.here && p.id != id) {
                self.host = next.id.clone();
            }
        }
        if !playing {
            return;
        }
        if self.p(id).is_some_and(|p| !p.out) {
            self.knock_out(&[id.to_string()]);
        }
        if let Some(p) = self.p_mut(id) {
            p.forfeit = true;
            p.done = true;
        }
        self.say(format!("{name} left"), now);
        if self.is_host() {
            self.scoreboard();
            if self.phase != BattlePhase::Countdown && self.is_over() && (self.mode.is_race() || self.alive().count() <= 1 || self.mode == BattleMode::Team2v2) {
                self.host_finish(now);
            } else if host_gone && !self.mode.is_race() && self.phase != BattlePhase::Countdown {
                self.next_round = Some((self.index, now + RESTART_MS));
            } else {
                self.check_round(now);
            }
        }
    }

    fn set_host(&mut self, id: &str, now: u64) {
        let was = self.is_host();
        self.host = id.to_string();
        if self.is_host() && !was && self.in_game() {
            if self.phase != BattlePhase::Countdown && !self.mode.is_race() {
                // carry on where the old host stopped, with the same question again
                self.next_round = Some((self.index, now + RESTART_MS));
                self.phase = BattlePhase::RoundResult;
            }
            self.scoreboard();
            self.check_race(now);
        } else if !self.is_host() {
            self.next_round = None;
        }
    }

    fn resume_for(&mut self, id: &str, now: u64) {
        let places: Vec<Value> = self.players.iter().filter(|p| p.playing).map(|p| json!({ "id": p.id, "place": p.place })).collect();
        let order: Vec<String> = self.players.iter().filter(|p| p.playing).map(|p| p.id.clone()).collect();
        let left = self.deadline.saturating_sub(now);
        self.send(json!({
            "t": "resume", "to": id, "mode": mode_info(self.mode).wire, "q": self.qs, "order": order, "i": self.index,
            "players": self.standings(), "inGame": self.in_game(), "finished": self.phase == BattlePhase::Finished,
            "places": places, "left": left,
        }));
    }

    fn peer(&mut self, id: &str, up: bool, now: u64) {
        let known = self.p(id).is_some();
        if let Some(p) = self.p_mut(id) {
            p.here = up;
        }
        if up {
            self.hello();
            if self.is_host() && (self.in_game() || self.phase == BattlePhase::Finished) && known {
                self.resume_for(id, now);
                let waiting = matches!(self.phase, BattlePhase::Playing | BattlePhase::RoundResult);
                if self.was_paused && waiting && !self.mode.is_race() {
                    self.next_round = Some((self.index, now + RESTART_MS));
                    self.phase = BattlePhase::RoundResult;
                }
            }
        } else if self.in_game() && self.is_host() {
            self.check_round(now);
        }
    }

    // MARK: messages

    fn on_text(&mut self, text: &str, now: u64) {
        let Ok(v) = serde_json::from_str::<Value>(text) else { return };
        let t = v["t"].as_str().unwrap_or_default();
        let from = v["from"].as_str().unwrap_or_default().to_string();
        let from_host = from == self.host;
        let id = v["id"].as_str().unwrap_or_default().to_string();
        let num = |k: &str| v[k].as_u64().unwrap_or(0);
        match t {
            "_room" => {
                self.me = v["you"].as_str().unwrap_or_default().into();
                self.kind = v["kind"].as_str().unwrap_or("duo").into();
                self.connected = true;
                self.joined_at = now;
                self.roster(&v["players"], true);
                self.fill_me();
                if matches!(self.phase, BattlePhase::Waiting | BattlePhase::Gone) {
                    self.phase = BattlePhase::Lobby;
                    self.problem.clear();
                }
                let host = v["host"].as_str().unwrap_or_default().to_string();
                self.set_host(&host, now);
                self.hello();
                if self.mode.is_race() && self.in_game() {
                    self.progress(now);
                }
            }
            "_players" => {
                self.roster(&v["players"], true);
                self.fill_me();
                if let Some(h) = v["host"].as_str().map(str::to_string) {
                    self.set_host(&h, now);
                }
            }
            "_peer" => self.peer(&id, v["up"].as_bool().unwrap_or(false), now),
            "_host" => {
                let me = self.is_host();
                self.set_host(&id, now);
                if !me && self.is_host() && self.party() && !self.in_game() {
                    self.say("You're the host now".into(), now);
                }
            }
            "_forfeit" => self.forfeit(&id, now),
            "_score" => {
                if !self.is_host() && self.in_game() {
                    if let Ok(list) = serde_json::from_value::<Vec<Standing>>(v["players"].clone()) {
                        self.apply(list);
                    }
                }
            }
            "_rating" => {
                let int = |k: &str| v[k].as_i64().unwrap_or(0) as i32;
                self.rating = Some(BattleRating { counted: v["counted"].as_bool().unwrap_or(false), rating: int("rating"), delta: int("delta") });
            }
            "hello" => {
                let version = num("v").max(1) as u32;
                if let Some(p) = self.p_mut(&from) {
                    p.read_card(&v["card"]);
                    p.v = version;
                    p.here = true;
                }
                self.check_compatible();
            }
            "start" if from_host => {
                let mode = battle_mode(v["mode"].as_str().unwrap_or_default().into());
                let ids = serde_json::from_value::<Vec<String>>(v["players"].clone());
                let qs = serde_json::from_value::<Vec<BattleQuestion>>(v["q"].clone());
                if let (Some(mode), Ok(ids), Ok(qs)) = (mode, ids, qs) {
                    self.begin(mode, ids, qs, now);
                }
            }
            "round" if from_host && self.in_game() => self.show_round(num("i") as u32, num("ms"), now),
            "answer" => self.receive(&from, num("i") as u32, v["ok"].as_bool().unwrap_or(false), num("ms") as u32, now),
            "result" if from_host && self.in_game() => {
                if let Ok(list) = serde_json::from_value::<Vec<Standing>>(v["players"].clone()) {
                    self.apply(list);
                }
                let to = serde_json::from_value::<Vec<String>>(v["to"].clone()).unwrap_or_default();
                let winner = v["w"].as_str().unwrap_or_default().to_string();
                self.index = num("i") as u32;
                self.show_result(winner, to, num("d") as u32, num("ms") as u32, now);
            }
            "progress" => {
                let (score, done) = (num("s") as u32, v["done"].as_bool().unwrap_or(false));
                if let Some(p) = self.p_mut(&from) {
                    p.score = score;
                    p.done |= done;
                }
                self.scoreboard();
                self.check_race(now);
            }
            "finished" if from_host && self.phase != BattlePhase::Lobby => {
                if let Ok(list) = serde_json::from_value::<Vec<Standing>>(v["players"].clone()) {
                    self.apply(list);
                }
                self.finish(read_places(&v["places"]), now);
            }
            "lobby" if (from_host || self.duo()) && self.phase != BattlePhase::Waiting => self.enter_lobby(),
            "resume" if from_host && v["to"].as_str() == Some(&self.me) => self.resume(&v, now),
            _ => {}
        }
        self.auto_start(now);
    }

    /// The host tells me where the game is (I dropped, or my app restarted).
    fn resume(&mut self, v: &Value, now: u64) {
        if v["finished"].as_bool().unwrap_or(false) {
            if self.in_game() {
                if let Ok(list) = serde_json::from_value::<Vec<Standing>>(v["players"].clone()) {
                    self.apply(list);
                }
                self.finish(read_places(&v["places"]), now);
            }
            return;
        }
        if !v["inGame"].as_bool().unwrap_or(false) {
            if self.in_game() {
                self.enter_lobby();
            }
            return;
        }
        let (Some(mode), Ok(qs), Ok(order)) = (
            battle_mode(v["mode"].as_str().unwrap_or_default().into()),
            serde_json::from_value::<Vec<BattleQuestion>>(v["q"].clone()),
            serde_json::from_value::<Vec<String>>(v["order"].clone()),
        ) else {
            return;
        };
        let same = self.in_game() && self.qs == qs && self.mode == mode;
        if !same {
            self.begin(mode, order, qs, now);
            self.out.retain(|o| !matches!(o, BattleOut::Sound { .. }));
        }
        if let Ok(list) = serde_json::from_value::<Vec<Standing>>(v["players"].clone()) {
            self.apply(list);
        }
        if mode.is_race() {
            // a race runs on each phone: keep my place in it, or pick it up where my score says
            if !same {
                self.start_race(now);
                let left = v["left"].as_u64().unwrap_or(0);
                self.deadline = now + left;
                self.index = self.p(&self.me).map_or(0, |p| p.score);
            }
        } else if self.phase != BattlePhase::Playing || !same {
            self.index = v["i"].as_u64().unwrap_or(0) as u32;
            self.phase = BattlePhase::RoundResult; // the host is about to show the next round
        }
    }

    fn party(&self) -> bool {
        self.kind == "party"
    }

    // MARK: the clock

    fn tick(&mut self, now: u64) {
        if now > self.notice_until {
            self.notice.clear();
        }
        self.auto_start(now);
        let paused = self.paused();
        if self.is_host() && paused && !self.was_paused {
            self.was_paused = true;
        }
        match self.phase {
            BattlePhase::Countdown => {
                if now >= self.count_ends {
                    self.sound(SoundId::Go);
                    if self.mode.is_race() {
                        self.start_race(now);
                    } else if self.is_host() && !paused {
                        self.host_round(0, now);
                    } else {
                        // the host's first round is on its way
                        self.phase = BattlePhase::RoundResult;
                        if self.is_host() {
                            self.next_round = Some((0, now));
                        }
                    }
                } else {
                    let left = ((self.count_ends - now).div_ceil(COUNT_MS)).max(1) as u32;
                    if left != self.last_count {
                        self.last_count = left;
                        self.sound(SoundId::Countdown);
                    }
                }
            }
            BattlePhase::Playing if self.mode.is_race() => self.tick_race(now),
            BattlePhase::Playing if self.is_host() && !paused => {
                if self.grace.is_some_and(|g| now >= g) || now >= self.deadline {
                    self.resolve(now);
                }
            }
            BattlePhase::RoundResult if self.is_host() && !paused => {
                if let Some((i, at)) = self.next_round {
                    if now >= at {
                        self.was_paused = false;
                        if self.is_over() && self.alive().count() <= 1 {
                            self.host_finish(now);
                        } else {
                            self.host_round(i, now);
                        }
                    }
                } else if now >= self.deadline {
                    if self.is_over() {
                        self.host_finish(now);
                    } else {
                        self.host_round(self.index + 1, now);
                    }
                }
            }
            _ => {}
        }
    }

    fn tick_race(&mut self, now: u64) {
        let me = self.me.clone();
        let mine_done = self.p(&me).is_none_or(|p| p.done);
        if !mine_done {
            if now >= self.deadline {
                if let Some(p) = self.p_mut(&me) {
                    p.done = true;
                }
                self.progress(now);
            } else if self.next_at.is_some_and(|at| now >= at) {
                self.next_at = None;
                self.index += 1;
                self.round_at = now;
                self.clear_round();
            }
        }
        self.check_race(now);
    }

    fn view(&self, now: u64) -> BattleView {
        let me = self.p(&self.me);
        let race = self.mode.is_race();
        let game = self.in_game() || self.phase == BattlePhase::Finished;
        let (time_left, time_total) = match self.phase {
            BattlePhase::Playing => (self.deadline.saturating_sub(now).min(self.total), self.total),
            _ => (0, 0),
        };
        BattleView {
            phase: self.phase,
            problem: self.problem.clone(),
            mode: (game || self.auto.is_some()).then_some(self.mode),
            me: self.me.clone(),
            host: self.host.clone(),
            is_host: self.is_host(),
            group: !self.duo(),
            party: self.party(),
            players: self
                .players
                .iter()
                .filter(|p| !game || p.playing)
                .map(|p| BattlePlayer {
                    id: p.id.clone(),
                    name: if p.name.is_empty() { "Player".into() } else { p.name.clone() },
                    card: p.card.clone(),
                    profile: p.profile.clone(),
                    level: p.level,
                    here: p.here,
                    hp: p.hp,
                    score: p.score,
                    out: p.out,
                    done: p.done,
                    team: p.team,
                    place: p.place,
                    answered: self.answers.contains_key(&p.id) || (p.id == self.me && self.answered),
                })
                .collect(),
            count: self.last_count,
            question: if self.in_game() && self.phase != BattlePhase::Countdown { self.question().cloned() } else { None },
            index: self.index,
            my_option: self.my_option,
            answered: self.answered,
            locked: now < self.locked_until || (self.answered && self.reveal),
            reveal: self.reveal,
            round_winner: self.round_winner.clone(),
            last_damage: self.last_damage,
            last_ms: self.last_ms,
            time_left_ms: time_left,
            time_total_ms: time_total,
            lives: self.lives,
            max_lives: self.mode.lives(),
            target: if self.mode.rules() == Rules::Points { self.mode.target().0 } else { 0 },
            spectating: self.in_game() && me.is_some_and(|p| !p.playing || p.out || (race && p.done)),
            paused: self.paused(),
            connected: self.connected,
            can_start: self.can_start(),
            can_rematch: self.phase == BattlePhase::Finished && (self.is_host() || self.duo()),
            result: self.result.clone(),
            rating: self.rating.clone(),
            notice: self.notice.clone(),
        }
    }
}

impl P {
    fn read_card(&mut self, card: &Value) {
        if !card.is_object() {
            return;
        }
        self.card = card.to_string();
        if let Some(n) = card["name"].as_str().filter(|n| !n.trim().is_empty()) {
            self.name = n.chars().take(24).collect();
        }
        self.level = card["level"].as_u64().unwrap_or(1).clamp(1, 9) as u8;
        self.swears = card["swears"].as_bool().unwrap_or(false);
    }
}

fn read_places(v: &Value) -> Vec<(String, u32)> {
    v.as_array()
        .map(|a| a.iter().filter_map(|e| Some((e["id"].as_str()?.to_string(), e["place"].as_u64()? as u32))).collect())
        .unwrap_or_default()
}

/// One phone's side of a battle.
#[derive(uniffi::Object)]
pub struct Battle {
    s: Mutex<State>,
}

#[uniffi::export]
impl Battle {
    /// `card` is this player's card as JSON; `auto` starts that mode by itself once everybody is in the room.
    #[uniffi::constructor]
    pub fn new(card: String, auto: Option<BattleMode>) -> std::sync::Arc<Battle> {
        let card = serde_json::from_str(&card).unwrap_or(Value::Null);
        std::sync::Arc::new(Battle { s: Mutex::new(State::new(card, auto)) })
    }

    /// Something arrived on the room's socket.
    pub fn on_text(&self, text: String, now_ms: u64) -> Vec<BattleOut> {
        self.run(|s| s.on_text(&text, now_ms))
    }

    /// The socket closed; the app reconnects by itself.
    pub fn on_closed(&self) -> Vec<BattleOut> {
        self.run(|s| s.connected = false)
    }

    /// The server refused the room (HTTP status): it's over.
    pub fn on_refused(&self, status: u16) -> Vec<BattleOut> {
        self.run(|s| {
            s.connected = false;
            s.problem = match status {
                401 => "Sign in again to battle.",
                404 => "There's no battle with that code (it may have ended).",
                409 => "That party is full or already playing.",
                412 => "That party plays with a different swear-word setting.",
                _ => "This battle isn't available any more (declined or expired).",
            }
            .into();
            s.phase = BattlePhase::Gone;
        })
    }

    /// Call about ten times a second.
    pub fn tick(&self, now_ms: u64) -> Vec<BattleOut> {
        self.run(|s| s.tick(now_ms))
    }

    /// Host: start a game with everyone in the lobby.
    pub fn start(&self, mode: BattleMode, now_ms: u64) -> Vec<BattleOut> {
        self.run(|s| s.start(mode, now_ms))
    }

    pub fn answer(&self, answer: BattleAnswer, now_ms: u64) -> Vec<BattleOut> {
        self.run(|s| s.answer(answer, now_ms))
    }

    /// After a game: back to the lobby with the same people (rematch).
    pub fn rematch(&self) -> Vec<BattleOut> {
        self.run(|s| {
            if s.phase == BattlePhase::Finished && (s.is_host() || s.duo()) {
                s.send(json!({ "t": "lobby" }));
                s.enter_lobby();
            }
        })
    }

    /// The player closes the battle for good.
    pub fn leave(&self) -> Vec<BattleOut> {
        self.run(|s| s.send(json!({ "t": "leave" })))
    }

    pub fn view(&self, now_ms: u64) -> BattleView {
        self.lock().view(now_ms)
    }
}

impl Battle {
    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.s.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn run(&self, f: impl FnOnce(&mut State)) -> Vec<BattleOut> {
        let mut s = self.lock();
        f(&mut s);
        std::mem::take(&mut s.out)
    }
}

#[cfg(test)]
#[path = "battle_tests.rs"]
mod tests;
