//! Whole games between simulated phones, through a stand-in for the server's room (server/src/room.ts).

use super::*;
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;

struct Phone {
    id: String,
    battle: Arc<Battle>,
    up: bool,
    /// Answers like this in every round: (right, after ms). None = never answers.
    plan: Option<(bool, u64)>,
    shown: Option<(u32, u64)>,
    result: Option<BattleResult>,
    hits: u32,
    sounds: Vec<SoundId>,
}

struct Room {
    kind: &'static str,
    phones: Vec<Phone>,
    roster: Vec<String>,
    host: String,
    score: Value,
    now: u64,
    queue: VecDeque<(String, String)>,
    types: Vec<String>,
}

impl Room {
    fn new(kind: &'static str, n: usize, auto: Option<BattleMode>) -> Room {
        let mut r = Room {
            kind,
            phones: vec![],
            roster: vec![],
            host: String::new(),
            score: Value::Null,
            now: 1_000,
            queue: VecDeque::new(),
            types: vec![],
        };
        for i in 0..n {
            let id = format!("p{i}");
            let card = json!({ "id": format!("arena-{i}"), "name": format!("Player {i}"), "level": 1 + i, "swears": false });
            r.roster.push(id.clone());
            r.phones.push(Phone {
                id,
                battle: Battle::new(card.to_string(), auto),
                up: false,
                plan: None,
                shown: None,
                result: None,
                hits: 0,
                sounds: vec![],
            });
        }
        r
    }

    fn joined(mut self) -> Room {
        for i in 0..self.phones.len() {
            self.connect(i);
        }
        self.run(300);
        self
    }

    fn at(&self, id: &str) -> usize {
        self.phones.iter().position(|p| p.id == id).unwrap()
    }

    fn players(&self) -> Value {
        json!(self.roster.iter().map(|id| json!({ "id": id, "here": self.phones[self.at(id)].up, "profile": { "id": id, "nickname": id } })).collect::<Vec<_>>())
    }

    fn tell(&mut self, id: &str, v: Value) {
        self.queue.push_back((id.to_string(), v.to_string()));
    }

    fn all(&mut self, v: Value, except: &str) {
        for id in self.roster.clone() {
            if id != except && self.phones[self.at(&id)].up {
                self.tell(&id, v.clone());
            }
        }
    }

    fn connect(&mut self, i: usize) {
        let id = self.phones[i].id.clone();
        self.phones[i].up = true;
        if self.host.is_empty() || !self.phones[self.at(&self.host.clone())].up {
            self.host = id.clone();
        }
        let room = json!({ "t": "_room", "kind": self.kind, "you": id, "host": self.host, "players": self.players(), "score": self.score });
        self.tell(&id, room);
        self.all(json!({ "t": "_peer", "up": true, "id": id }), &id);
        self.all(json!({ "t": "_host", "id": self.host }), &id);
        self.pump();
    }

    fn drop_phone(&mut self, i: usize) {
        let id = self.phones[i].id.clone();
        self.phones[i].up = false;
        self.phones[i].battle.on_closed();
        self.all(json!({ "t": "_peer", "up": false, "id": id }), &id);
        if self.host == id {
            if let Some(next) = self.roster.iter().find(|r| self.phones[self.at(r)].up).cloned() {
                self.host = next.clone();
                self.all(json!({ "t": "_host", "id": next }), &id);
            }
        }
        self.pump();
    }

    fn forfeit(&mut self, i: usize) {
        let id = self.phones[i].id.clone();
        self.phones[i].up = false;
        self.all(json!({ "t": "_forfeit", "id": id }), &id);
        if self.kind != "duo" {
            self.roster.retain(|r| *r != id);
            if self.host == id {
                self.host = self.roster.first().cloned().unwrap_or_default();
            }
            let players = self.players();
            self.all(json!({ "t": "_players", "players": players, "host": self.host }), &id);
        }
        self.pump();
    }

    fn act(&mut self, i: usize, out: Vec<BattleOut>) {
        for o in out {
            match o {
                BattleOut::Send { json } => {
                    if !self.phones[i].up {
                        continue;
                    }
                    let mut v: Value = serde_json::from_str(&json).unwrap();
                    let t = v["t"].as_str().unwrap().to_string();
                    let id = self.phones[i].id.clone();
                    let host_only = ["start", "round", "result", "finished", "lobby", "resume", "score"].contains(&t.as_str());
                    if self.kind != "duo" && host_only {
                        assert_eq!(id, self.host, "only the host sends {t}");
                    }
                    self.types.push(t.clone());
                    if t == "report" || t == "leave" {
                        continue;
                    }
                    if t == "score" {
                        self.score = v["players"].clone();
                        self.all(json!({ "t": "_score", "players": v["players"] }), "");
                        continue;
                    }
                    v["from"] = json!(id);
                    self.all(v, &id);
                }
                BattleOut::Hit { .. } => self.phones[i].hits += 1,
                BattleOut::Finished { result } => {
                    assert!(self.phones[i].result.is_none(), "finished once");
                    self.phones[i].result = Some(result);
                }
                BattleOut::Sound { sound } => self.phones[i].sounds.push(sound),
            }
        }
    }

    fn pump(&mut self) {
        while let Some((id, text)) = self.queue.pop_front() {
            let i = self.at(&id);
            if self.phones[i].up {
                let out = self.phones[i].battle.on_text(text, self.now);
                self.act(i, out);
            }
        }
    }

    fn run(&mut self, ms: u64) {
        let end = self.now + ms;
        while self.now < end {
            self.now += 50;
            for i in 0..self.phones.len() {
                let out = self.phones[i].battle.tick(self.now);
                self.act(i, out);
                self.pump();
                self.play(i);
                self.pump();
            }
        }
    }

    /// Answers according to the plan.
    fn play(&mut self, i: usize) {
        let v = self.view(i);
        if v.phase != BattlePhase::Playing || v.answered || v.spectating {
            return;
        }
        let Some((right, after)) = self.phones[i].plan else { return };
        let key = v.index;
        let since = match self.phones[i].shown {
            Some((k, at)) if k == key => at,
            _ => {
                self.phones[i].shown = Some((key, self.now));
                self.now
            }
        };
        if self.now < since + after {
            return;
        }
        let q = v.question.unwrap();
        let a = match q.ask {
            BattleAsk::Sentence => BattleAnswer::Tiles { tiles: if right { vec![q.solution.clone()] } else { vec!["错".into()] } },
            BattleAsk::Pinyin => BattleAnswer::Text { text: if right { q.solution.clone() } else { "zzz".into() } },
            _ => BattleAnswer::Option { index: if right { q.answer } else { (q.answer + 1) % 4 } },
        };
        let out = self.phones[i].battle.answer(a, self.now);
        self.act(i, out);
    }

    fn view(&self, i: usize) -> BattleView {
        self.phones[i].battle.view(self.now)
    }

    fn start(&mut self, mode: BattleMode) {
        let i = self.at(&self.host.clone());
        let out = self.phones[i].battle.start(mode, self.now);
        self.act(i, out);
        self.pump();
    }

    fn plans(&mut self, plans: &[Option<(bool, u64)>]) {
        for (p, plan) in self.phones.iter_mut().zip(plans) {
            p.plan = *plan;
        }
    }

    fn until_finished(&mut self, max_ms: u64) {
        let end = self.now + max_ms;
        while self.now < end && self.phones.iter().any(|p| p.up && p.battle.view(self.now).phase != BattlePhase::Finished) {
            self.run(50);
        }
        for p in &self.phones {
            let v = p.battle.view(self.now);
            assert!(!p.up || v.phase == BattlePhase::Finished, "{} is still {:?} in {:?} round {}", p.id, v.phase, v.mode, v.index);
        }
        // every phone that was there at the end agrees on the places
        let of = |v: BattleView| v.players.into_iter().map(|p| (p.id, p.place)).collect::<HashMap<_, _>>();
        let mut all = self.phones.iter().filter(|p| p.up).map(|p| of(p.battle.view(self.now)));
        let first = all.next().unwrap();
        for other in all {
            assert_eq!(first, other, "everyone sees the same result");
        }
    }

    fn places(&self) -> Vec<u32> {
        self.phones.iter().map(|p| p.result.as_ref().map_or(0, |r| r.place)).collect()
    }
}

use BattleMode::*;

#[test]
fn every_mode_plays_to_the_end() {
    for players in 2..=4 {
        for info in modes_for(players as u32) {
            let mut r = Room::new(if players == 2 { "duo" } else { "party" }, players, None).joined();
            assert!(r.view(0).can_start && !r.view(1).can_start);
            r.plans(&[Some((true, 700)), Some((true, 1_300)), Some((true, 2_000)), Some((true, 2_200))][..players]);
            r.start(info.mode);
            for i in 0..players {
                assert_eq!(r.view(i).phase, BattlePhase::Countdown);
                assert_eq!(r.view(i).mode, Some(info.mode));
            }
            r.until_finished(400_000);
            let places = r.places();
            assert_eq!(places[0], 1, "{:?} with {players}: the fastest wins, {places:?}", info.mode);
            assert!(places.iter().all(|p| (1..=players as u32).contains(p)), "{:?} {places:?}", info.mode);
            let result = r.phones[0].result.clone().unwrap();
            assert_eq!(result.players, players as u32);
            assert_eq!(result.ranked, players == 2);
            assert_eq!(result.group_coins > 0, players > 2);
            if info.mode != BattleRoyale && info.mode != Blitz && info.mode != Survival {
                assert!(r.phones[0].fastest_ok(700), "{:?} {:?}", info.mode, result.fastest_ms);
            }
            assert!(r.phones[0].sounds.contains(&SoundId::Victory), "{:?}", info.mode);
            assert!(r.phones[players - 1].sounds.contains(&SoundId::Defeat) || places[players - 1] == 1, "{:?} {places:?}", info.mode);
            // a 1v1 is reported to the server by both phones, groups aren't
            assert_eq!(r.types.iter().filter(|t| *t == "report").count(), if players == 2 { 2 } else { 0 });
        }
    }
}

impl Phone {
    fn fastest_ok(&self, around: u32) -> bool {
        self.result.as_ref().and_then(|r| r.fastest_ms).is_some_and(|f| f.abs_diff(around) <= 150)
    }
}

#[test]
fn hp_hits_everybody_else() {
    let mut r = Room::new("party", 4, None).joined();
    r.plans(&[Some((true, 600)), Some((false, 400)), None, None]);
    r.start(Duel);
    r.run(3_000 + 1_500);
    for i in 0..4 {
        let v = r.view(i);
        assert_eq!(v.players.iter().map(|p| p.hp == 100).collect::<Vec<_>>(), vec![true, false, false, false], "phone {i}");
        assert_eq!(v.round_winner, "p0");
        assert!(v.reveal);
        assert_eq!(r.phones[i].hits, 1);
    }
    assert!(r.phones[0].sounds.contains(&SoundId::Crit), "0.6 s is a critical hit");
    r.until_finished(120_000);
    assert_eq!(r.places(), vec![1, 2, 2, 2], "knocked out together, they share second");
    assert!(r.phones[1].sounds.contains(&SoundId::Ko));
}

#[test]
fn the_faster_answer_wins_even_if_it_arrives_later() {
    let mut r = Room::new("duo", 2, None).joined();
    r.start(Duel);
    r.run(2_500);
    let q = r.view(0).question.unwrap();
    // the host answers after 900 ms; the guest's 800 ms answer arrives 200 ms after that
    r.run(900);
    let now = r.now;
    let a = r.phones[0].battle.answer(BattleAnswer::Option { index: q.answer }, now);
    r.act(0, a);
    r.run(200);
    let late = json!({ "t": "answer", "i": 0, "ok": true, "ms": 500, "from": "p1" });
    r.tell("p0", late);
    r.pump();
    r.run(400);
    assert_eq!(r.view(0).round_winner, "p1");
    assert_eq!(r.view(1).round_winner, "p1");
}

#[test]
fn battle_royale_knocks_out_wrong_answers() {
    let mut r = Room::new("group", 4, Some(BattleRoyale)).joined();
    r.plans(&[Some((true, 500)), Some((true, 900)), Some((false, 600)), None]);
    r.run(4_000);
    assert_eq!(r.view(0).mode, Some(BattleRoyale), "starts by itself");
    r.run(10_000);
    let v = r.view(2);
    assert!(v.spectating, "one wrong answer and you watch");
    assert!(r.view(3).spectating, "no answer is a wrong answer");
    assert!(!r.view(0).spectating);
    // both of the last two wrong in the same round: nobody goes
    r.plans(&[Some((false, 500)), Some((false, 500)), None, None]);
    r.run(6_000);
    assert_eq!(r.view(0).players.iter().filter(|p| !p.out).count(), 2);
    r.plans(&[Some((false, 500)), Some((true, 500)), None, None]);
    r.until_finished(60_000);
    assert_eq!(r.places(), vec![2, 1, 3, 3]);
    assert_eq!(r.phones[1].result.as_ref().unwrap().group_coins, group_coins(1, 4));
}

#[test]
fn teams_share_their_health() {
    let mut r = Room::new("party", 4, None).joined();
    // p0 and p2 are a team, p1 and p3 the other
    r.plans(&[Some((true, 2_000)), None, Some((true, 600)), Some((true, 3_000))]);
    r.start(Team2v2);
    r.run(4_200);
    let v = r.view(1);
    let hp: Vec<u32> = v.players.iter().map(|p| p.hp).collect();
    assert_eq!(hp[0], 100);
    assert!(hp[1] < 100 && hp[1] == hp[3] && hp[2] == 100, "{hp:?}");
    r.until_finished(120_000);
    assert_eq!(r.places(), vec![1, 2, 1, 2]);
    assert!(r.phones.iter().all(|p| p.result.as_ref().unwrap().outcome != Outcome::Draw));
    assert_eq!(r.phones[0].result.as_ref().unwrap().group_coins, 70);
    assert_eq!(r.phones[1].result.as_ref().unwrap().group_coins, 20);
}

#[test]
fn points_modes_allow_another_try() {
    let mut r = Room::new("duo", 2, None).joined();
    r.start(PinyinType);
    r.run(2_500);
    let q = r.view(1).question.unwrap();
    let now = r.now;
    let out = r.phones[1].battle.answer(BattleAnswer::Text { text: "zzz".into() }, now);
    r.act(1, out);
    assert!(r.view(1).locked && !r.view(1).answered, "a second's penalty");
    r.run(1_100);
    let now = r.now;
    let out = r.phones[1].battle.answer(BattleAnswer::Text { text: q.solution }, now);
    r.act(1, out);
    r.pump();
    r.run(500);
    let v = r.view(0);
    assert_eq!(v.round_winner, "p1");
    assert_eq!(v.players.iter().find(|p| p.id == "p1").unwrap().score, 1);
    assert_eq!(v.target, 5);
}

#[test]
fn races_rank_by_score() {
    let mut r = Room::new("party", 3, None).joined();
    r.plans(&[Some((true, 3_000)), Some((true, 1_000)), Some((true, 3_000))]);
    r.start(Blitz);
    r.until_finished(60_000);
    assert_eq!(r.places(), vec![2, 1, 2], "a tie shares second place");
    // survival: three wrong answers end it early
    let mut r = Room::new("duo", 2, None).joined();
    r.plans(&[Some((false, 500)), Some((true, 5_000))]);
    r.start(Survival);
    r.run(8_000);
    assert_eq!(r.view(0).lives, 0);
    assert!(r.view(0).spectating);
    r.until_finished(140_000);
    assert_eq!(r.places(), vec![2, 1]);
}

#[test]
fn the_next_player_hosts_when_the_host_drops() {
    let mut r = Room::new("party", 3, None).joined();
    r.plans(&[Some((true, 900)), Some((true, 1_500)), None]);
    r.start(Duel);
    r.run(5_000);
    let hp = r.view(1).players.iter().find(|p| p.id == "p1").unwrap().hp;
    assert!(hp < 100);
    r.drop_phone(0);
    assert_eq!(r.host, "p1");
    r.run(6_000);
    let v = r.view(2);
    assert_eq!(v.host, "p1");
    assert!(!v.paused);
    let p = |id: &str| v.players.iter().find(|p| p.id == id).unwrap().clone();
    assert_eq!(p("p1").hp, hp, "the score so far stands");
    assert!(p("p2").hp < hp, "and the game goes on");
    // the old host comes back as a guest and picks up the game
    r.connect(0);
    r.run(2_000);
    assert_eq!(r.view(0).host, "p1");
    assert!(!r.view(0).is_host);
    assert_eq!(r.view(0).players.iter().map(|p| p.hp).collect::<Vec<_>>(), r.view(1).players.iter().map(|p| p.hp).collect::<Vec<_>>());
    r.until_finished(120_000);
}

#[test]
fn an_app_that_restarts_gets_the_game_back() {
    for mode in [Duel, Blitz] {
        let mut r = Room::new("party", 3, None).joined();
        r.plans(&[Some((true, 900)), Some((true, 1_500)), Some((true, 2_000))]);
        r.start(mode);
        r.run(6_000);
        r.drop_phone(2);
        r.phones[2].battle = Battle::new(json!({ "name": "Player 2", "level": 3 }).to_string(), None);
        r.run(500);
        r.connect(2);
        r.run(3_000);
        let v = r.view(2);
        assert_eq!(v.mode, Some(mode));
        assert!(matches!(v.phase, BattlePhase::Playing | BattlePhase::RoundResult));
        assert_eq!(v.players.len(), 3);
        r.until_finished(120_000);
    }
}

#[test]
fn a_1v1_waits_for_a_dropped_player_and_ends_with_a_forfeit() {
    let mut r = Room::new("duo", 2, None).joined();
    r.plans(&[Some((true, 900)), Some((true, 1_500))]);
    r.start(Duel);
    r.run(5_000);
    r.drop_phone(0); // the host
    r.run(10_000);
    let v = r.view(1);
    assert!(v.paused && v.is_host);
    let hp: Vec<u32> = v.players.iter().map(|p| p.hp).collect();
    r.run(5_000);
    assert_eq!(r.view(1).players.iter().map(|p| p.hp).collect::<Vec<_>>(), hp, "nothing happens while paused");
    r.connect(0);
    r.run(3_000);
    assert!(!r.view(1).paused && !r.view(0).paused);
    assert_eq!(r.view(0).index, r.view(1).index);
    r.drop_phone(0);
    r.forfeit(0);
    assert_eq!(r.view(1).phase, BattlePhase::Finished);
    let result = r.phones[1].result.clone().unwrap();
    assert!(result.ranked && result.outcome == Outcome::Win);
}

#[test]
fn leaving_a_group_doesnt_stop_it() {
    let mut r = Room::new("party", 4, None).joined();
    r.plans(&[Some((true, 900)), Some((true, 1_500)), Some((true, 2_000)), None]);
    r.start(Duel);
    r.run(4_000);
    r.forfeit(3);
    r.run(1_000);
    assert!(r.view(1).players.iter().any(|p| p.id == "p3" && p.out), "still on the scoreboard");
    r.forfeit(0); // the host
    assert_eq!(r.host, "p1");
    r.until_finished(120_000);
    assert_eq!(r.phones[1].result.as_ref().unwrap().place, 1);
    assert_eq!(r.phones[2].result.as_ref().unwrap().place, 2);
    // back in the lobby, the ones who left are gone
    let out = r.phones[1].battle.rematch();
    r.act(1, out);
    r.pump();
    for i in [1, 2] {
        assert_eq!(r.view(i).phase, BattlePhase::Lobby);
        assert_eq!(r.view(i).players.len(), 2);
    }
    assert!(r.view(1).can_start);
    r.phones[1].result = None;
    r.phones[2].result = None;
    r.start(Blitz);
    r.until_finished(60_000);
}

#[test]
fn everyone_leaving_makes_the_last_one_the_winner() {
    for mode in [Duel, Blitz, BattleRoyale, SentenceBuilder] {
        let mut r = Room::new("party", 3, None).joined();
        r.start(mode);
        r.run(3_500);
        r.forfeit(0);
        r.forfeit(2);
        r.run(3_000);
        assert_eq!(r.phones[1].result.as_ref().map(|x| (x.place, x.outcome)), Some((1, Outcome::Win)), "{mode:?}");
    }
}

#[test]
fn quick_matches_start_by_themselves() {
    let mut r = Room::new("duo", 2, Some(ToneClash));
    r.connect(0);
    r.run(20_000);
    assert_eq!(r.view(0).phase, BattlePhase::Lobby, "waits for the other player");
    r.connect(1);
    r.run(200);
    assert_eq!(r.view(0).mode, Some(ToneClash));
    assert_eq!(r.view(1).phase, BattlePhase::Countdown);
    // a group doesn't wait forever for the fourth
    let mut r = Room::new("group", 4, Some(Duel));
    for i in 0..3 {
        r.connect(i);
    }
    r.run(5_000);
    assert_eq!(r.view(0).phase, BattlePhase::Lobby);
    r.run(8_000);
    assert_eq!(r.view(0).players.len(), 3);
    assert!(matches!(r.view(2).phase, BattlePhase::Countdown | BattlePhase::Playing));
}

#[test]
fn who_can_play_together() {
    // different swear settings
    let mut r = Room::new("duo", 2, Some(Duel));
    r.phones[1].battle = Battle::new(json!({ "name": "B", "level": 1, "swears": true }).to_string(), Some(Duel));
    let mut r = r.joined();
    assert_eq!(r.view(0).phase, BattlePhase::Gone);
    assert!(r.view(0).problem.contains("swear"));
    r.start(Duel);
    assert!(!r.types.contains(&"start".to_string()));
    // an app from before groups
    let mut r = Room::new("duo", 2, Some(Duel));
    r.connect(0);
    r.tell("p0", json!({ "t": "_peer", "up": true, "id": "p1" }));
    r.tell("p0", json!({ "t": "hello", "from": "p1", "card": { "name": "Old", "level": 2 } }));
    r.pump();
    assert!(r.view(0).problem.contains("older version"), "{}", r.view(0).problem);
}

#[test]
fn the_host_picks_only_modes_that_fit() {
    let mut r = Room::new("party", 2, None).joined();
    r.start(BattleRoyale);
    assert_eq!(r.view(0).phase, BattlePhase::Lobby);
    r.start(Team2v2);
    assert_eq!(r.view(0).phase, BattlePhase::Lobby);
    let out = r.phones[1].battle.start(Duel, r.now);
    assert!(out.is_empty(), "guests can't start");
    r.start(Duel);
    assert_eq!(r.view(1).phase, BattlePhase::Countdown);
    assert!(!r.phones[0].battle.view(r.now).players[0].card.is_empty());
}

#[test]
fn refusals_and_garbage() {
    let b = Battle::new("{}".into(), None);
    for junk in ["", "nope", "[]", r#"{"t":5}"#, r#"{"t":"result"}"#, r#"{"t":"start","mode":"Duel"}"#, "pong"] {
        b.on_text(junk.into(), 1);
    }
    assert_eq!(b.view(1).phase, BattlePhase::Waiting);
    b.on_refused(409);
    assert_eq!(b.view(1).phase, BattlePhase::Gone);
    assert!(b.view(1).problem.contains("full"));
}
