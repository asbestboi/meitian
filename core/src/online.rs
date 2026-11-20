//! Online play: the server's JSON (profiles, friends, leaderboards, live events) parsed once here, so the
//! iPhone and Android apps read it identically. The battle itself uses the same JSON protocol as the
//! Wi‑Fi link (the server's rooms relay it), so only the server's own messages are decoded here.

use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct OnlineProfile {
    pub id: String,
    pub nickname: String,
    pub tag: String,
    pub level: u32,
    pub streak: u32,
    pub xp_total: u64,
    pub xp_week: u64,
    pub rating: i32,
    pub wins: u32,
    pub losses: u32,
    /// Path like `/v1/avatars/<id>/<version>`, empty when there's no picture.
    pub avatar: String,
    pub online: bool,
    /// Only on your own profile.
    pub friend_code: String,
    /// Equipped cosmetics as sent by their app (`avatar`, `aura`, `fx`, `title`…).
    pub cosmetic_avatar: String,
    pub cosmetic_aura: String,
    pub cosmetic_fx: String,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct RawProfile {
    id: String,
    nickname: String,
    tag: String,
    level: u32,
    streak: u32,
    xp_total: u64,
    xp_week: u64,
    rating: i32,
    wins: u32,
    losses: u32,
    avatar: Option<String>,
    online: bool,
    friend_code: Option<String>,
    cosmetics: Value,
}

impl From<RawProfile> for OnlineProfile {
    fn from(r: RawProfile) -> Self {
        let cos = |k: &str| r.cosmetics.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
        OnlineProfile {
            cosmetic_avatar: cos("avatar"),
            cosmetic_aura: cos("aura"),
            cosmetic_fx: cos("fx"),
            id: r.id,
            nickname: r.nickname,
            tag: r.tag,
            level: r.level,
            streak: r.streak,
            xp_total: r.xp_total,
            xp_week: r.xp_week,
            rating: r.rating,
            wins: r.wins,
            losses: r.losses,
            avatar: r.avatar.unwrap_or_default(),
            online: r.online,
            friend_code: r.friend_code.unwrap_or_default(),
        }
    }
}

#[derive(Debug, uniffi::Error)]
pub enum OnlineError {
    Server { status: u16, reason: String },
    Garbled,
}

impl std::error::Error for OnlineError {}

impl std::fmt::Display for OnlineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OnlineError::Server { reason, .. } => f.write_str(reason),
            OnlineError::Garbled => f.write_str("unexpected answer from the server"),
        }
    }
}

fn parse<T: for<'a> Deserialize<'a>>(json: &str) -> Result<T, OnlineError> {
    serde_json::from_str(json).map_err(|_| OnlineError::Garbled)
}

/// Turns an HTTP status + body into an error when the server refused (its `{"error": "..."}` text is
/// already written for people).
#[uniffi::export]
pub fn online_check(status: u16, body: String) -> Result<(), OnlineError> {
    if (200..300).contains(&status) {
        return Ok(());
    }
    #[derive(Deserialize)]
    struct E {
        error: String,
    }
    let reason = serde_json::from_str::<E>(&body)
        .map(|e| e.error)
        .unwrap_or_else(|_| match status {
            0 => "no connection to the server".into(),
            500.. => "the server is having trouble, try again soon".into(),
            _ => format!("the server said {status}"),
        });
    Err(OnlineError::Server { status, reason })
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct OnlineAccount {
    /// `id.secret`: sent as the bearer token, and shown as the recovery code.
    pub token: String,
    pub profile: OnlineProfile,
}

/// `POST /v1/register` answer.
#[uniffi::export]
pub fn online_parse_account(json: String) -> Result<OnlineAccount, OnlineError> {
    #[derive(Deserialize)]
    struct A {
        token: String,
        profile: RawProfile,
    }
    let a: A = parse(&json)?;
    Ok(OnlineAccount { token: a.token, profile: a.profile.into() })
}

/// Any `{"profile": …}` answer (`/v1/me`, `/v1/players/:id`).
#[uniffi::export]
pub fn online_parse_profile(json: String) -> Result<OnlineProfile, OnlineError> {
    #[derive(Deserialize)]
    struct P {
        profile: RawProfile,
    }
    Ok(parse::<P>(&json)?.profile.into())
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct OnlineChallenge {
    pub room: String,
    pub mode: String,
    pub from: OnlineProfile,
}

#[derive(Deserialize)]
struct RawChallenge {
    room: String,
    mode: String,
    from: RawProfile,
}

impl From<RawChallenge> for OnlineChallenge {
    fn from(c: RawChallenge) -> Self {
        OnlineChallenge { room: c.room, mode: c.mode, from: c.from.into() }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct OnlineFriends {
    pub friends: Vec<OnlineProfile>,
    pub incoming: Vec<OnlineProfile>,
    pub outgoing: Vec<OnlineProfile>,
    pub challenges: Vec<OnlineChallenge>,
}

#[uniffi::export]
pub fn online_parse_friends(json: String) -> Result<OnlineFriends, OnlineError> {
    #[derive(Deserialize, Default)]
    #[serde(default)]
    struct F {
        friends: Vec<RawProfile>,
        incoming: Vec<RawProfile>,
        outgoing: Vec<RawProfile>,
        challenges: Vec<RawChallenge>,
    }
    let f: F = parse(&json)?;
    let conv = |v: Vec<RawProfile>| v.into_iter().map(Into::into).collect();
    Ok(OnlineFriends {
        friends: conv(f.friends),
        incoming: conv(f.incoming),
        outgoing: conv(f.outgoing),
        challenges: f.challenges.into_iter().map(Into::into).collect(),
    })
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct OnlineInbox {
    pub requests: u32,
    pub challenges: Vec<OnlineChallenge>,
}

#[uniffi::export]
pub fn online_parse_inbox(json: String) -> Result<OnlineInbox, OnlineError> {
    #[derive(Deserialize)]
    struct I {
        #[serde(default)]
        requests: u32,
        #[serde(default)]
        challenges: Vec<RawChallenge>,
    }
    let i: I = parse(&json)?;
    Ok(OnlineInbox { requests: i.requests, challenges: i.challenges.into_iter().map(Into::into).collect() })
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LeaderEntry {
    pub rank: u32,
    pub profile: OnlineProfile,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Leaderboard {
    pub board: String,
    pub top: Vec<LeaderEntry>,
    pub me: LeaderEntry,
}

#[uniffi::export]
pub fn online_parse_leaderboard(json: String) -> Result<Leaderboard, OnlineError> {
    #[derive(Deserialize)]
    struct E {
        rank: u32,
        profile: RawProfile,
    }
    #[derive(Deserialize)]
    struct L {
        board: String,
        top: Vec<E>,
        me: E,
    }
    let l: L = parse(&json)?;
    let conv = |e: E| LeaderEntry { rank: e.rank, profile: e.profile.into() };
    Ok(Leaderboard { board: l.board, top: l.top.into_iter().map(conv).collect(), me: conv(l.me) })
}

/// What the server says on the queue and room sockets. Anything else on a room socket is the other
/// phone's battle message (`Battle`), handled by the existing battle code.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum OnlineEvent {
    /// Waiting in the quick-match queue.
    Queued,
    /// Paired: join this room.
    Matched { room: String, mode: String, opponent: OnlineProfile },
    /// Joined a room; `peer` = the opponent is already there.
    Joined { opponent: Option<OnlineProfile>, peer: bool },
    /// The opponent connected (`up`) or dropped.
    Peer { up: bool },
    /// The game's rating result (`counted` = false when the two phones disagreed).
    Rating { counted: bool, rating: i32, delta: i32 },
    /// The opponent left mid-game and didn't come back: you win.
    Forfeit,
    Battle { json: String },
    Ignore,
}

#[uniffi::export]
pub fn online_event(json: String) -> OnlineEvent {
    if json == "pong" {
        return OnlineEvent::Ignore;
    }
    let Ok(v) = serde_json::from_str::<Value>(&json) else {
        return OnlineEvent::Ignore;
    };
    let s = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let profile = |k: &str| {
        v.get(k)
            .filter(|p| p.is_object())
            .and_then(|p| serde_json::from_value::<RawProfile>(p.clone()).ok())
            .map(OnlineProfile::from)
    };
    let int = |k: &str| v.get(k).and_then(Value::as_i64).unwrap_or(0) as i32;
    let flag = |k: &str| v.get(k).and_then(Value::as_bool).unwrap_or(false);
    match s("t").as_str() {
        "queued" => OnlineEvent::Queued,
        "matched" => match profile("opponent") {
            Some(opponent) => OnlineEvent::Matched { room: s("room"), mode: s("mode"), opponent },
            None => OnlineEvent::Ignore,
        },
        "_room" => OnlineEvent::Joined { opponent: profile("opponent"), peer: flag("peer") },
        "_peer" => OnlineEvent::Peer { up: flag("up") },
        "_rating" => OnlineEvent::Rating { counted: flag("counted"), rating: int("rating"), delta: int("delta") },
        "_forfeit" => OnlineEvent::Forfeit,
        t if t.starts_with('_') => OnlineEvent::Ignore,
        _ => OnlineEvent::Battle { json },
    }
}

/// The game report each phone sends when a game ends (`won`: Some(true) win, Some(false) loss, None draw).
#[uniffi::export]
pub fn online_report(won: Option<bool>) -> String {
    serde_json::json!({ "t": "report", "won": won }).to_string()
}

/// Same rule as the server: 2–16 letters (any script) or digits, space, `_ - .`, no links.
#[uniffi::export]
pub fn nickname_ok(name: String) -> bool {
    let n = name.trim();
    let len = n.chars().count();
    if n != name || !(2..=16).contains(&len) {
        return false;
    }
    if !n.chars().all(|c| c.is_alphanumeric() || matches!(c, ' ' | '_' | '.' | '-')) {
        return false;
    }
    let lower = n.to_lowercase();
    !["http", "www", ".com", ".net", ".org", ".cn"].iter().any(|b| lower.contains(b))
}

#[cfg(test)]
mod tests {
    use super::*;

    const P: &str = r#"{"id":"u1","nickname":"小明","tag":"1234","level":2,"streak":5,"xpTotal":900,"xpWeek":40,
      "rating":1016,"wins":1,"losses":0,"cosmetics":{"avatar":"av.panda","aura":"au.fire"},
      "avatar":"/v1/avatars/u1/2","online":true,"friendCode":"ABC234"}"#;

    #[test]
    fn profiles_and_lists() {
        let p = online_parse_profile(format!(r#"{{"profile":{P}}}"#)).unwrap();
        assert_eq!(p.nickname, "小明");
        assert_eq!(p.cosmetic_aura, "au.fire");
        assert_eq!(p.friend_code, "ABC234");
        assert_eq!(p.avatar, "/v1/avatars/u1/2");
        let a = online_parse_account(format!(r#"{{"token":"u1.s","profile":{P}}}"#)).unwrap();
        assert_eq!(a.token, "u1.s");
        let f = online_parse_friends(format!(
            r#"{{"friends":[{P}],"incoming":[],"outgoing":[],"challenges":[{{"room":"r","mode":"Duel","from":{P}}}]}}"#
        ))
        .unwrap();
        assert_eq!(f.friends.len(), 1);
        assert_eq!(f.challenges[0].room, "r");
        let l = online_parse_leaderboard(format!(
            r#"{{"board":"week","top":[{{"rank":1,"profile":{P}}}],"me":{{"rank":7,"profile":{P}}}}}"#
        ))
        .unwrap();
        assert_eq!(l.me.rank, 7);
        // no picture, no cosmetics
        let bare = online_parse_profile(r#"{"profile":{"id":"x","nickname":"ab","avatar":null}}"#.into()).unwrap();
        assert_eq!(bare.avatar, "");
        assert_eq!(bare.rating, 0);
    }

    #[test]
    fn errors() {
        assert!(online_check(200, String::new()).is_ok());
        match online_check(404, r#"{"error":"no player with that code"}"#.into()) {
            Err(OnlineError::Server { status, reason }) => {
                assert_eq!(status, 404);
                assert_eq!(reason, "no player with that code");
            }
            _ => panic!(),
        }
        assert!(matches!(online_check(0, String::new()), Err(OnlineError::Server { .. })));
    }

    #[test]
    fn events() {
        assert_eq!(online_event(r#"{"t":"queued"}"#.into()), OnlineEvent::Queued);
        assert!(matches!(
            online_event(format!(r#"{{"t":"matched","room":"r1","mode":"Blitz","opponent":{P}}}"#)),
            OnlineEvent::Matched { ref room, .. } if room == "r1"
        ));
        assert_eq!(
            online_event(r#"{"t":"_room","opponent":null,"peer":true}"#.into()),
            OnlineEvent::Joined { opponent: None, peer: true }
        );
        assert_eq!(online_event(r#"{"t":"_peer","up":false}"#.into()), OnlineEvent::Peer { up: false });
        assert_eq!(
            online_event(r#"{"t":"_rating","counted":true,"rating":1016,"delta":16}"#.into()),
            OnlineEvent::Rating { counted: true, rating: 1016, delta: 16 }
        );
        let battle = r#"{"t":"answer","i":2,"ok":true,"ms":900}"#.to_string();
        assert_eq!(online_event(battle.clone()), OnlineEvent::Battle { json: battle });
        assert_eq!(online_event("pong".into()), OnlineEvent::Ignore);
        assert_eq!(online_report(Some(true)), r#"{"t":"report","won":true}"#);
        assert_eq!(online_report(None), r#"{"t":"report","won":null}"#);
    }

    #[test]
    fn nicknames_match_the_server() {
        assert!(nickname_ok("小明".into()));
        assert!(nickname_ok("Anna_99".into()));
        assert!(!nickname_ok("a".into()));
        assert!(!nickname_ok(" spaced".into()));
        assert!(!nickname_ok("visit www.x".into()));
        assert!(!nickname_ok("x".repeat(17)));
        assert!(!nickname_ok("<script>".into()));
    }
}
