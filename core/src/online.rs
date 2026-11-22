//! Online play: the server's JSON (profiles, friends, leaderboards, live events) parsed once here, so the
//! iPhone and Android apps read it identically. What happens inside a room is handled by `battle.rs`.

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
    /// Equipped cosmetics as sent by their app (`aura`, `fx`, `title`…; older apps also send `avatar`, which is ignored).
    pub cosmetic_aura: String,
    pub cosmetic_fx: String,
    pub cosmetic_title: String,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
pub(crate) struct RawProfile {
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
            cosmetic_aura: cos("aura"),
            cosmetic_fx: cos("fx"),
            cosmetic_title: cos("title"),
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
    /// An invitation to a party: its code ("" for a 1v1 challenge).
    pub party: String,
    pub from: OnlineProfile,
}

#[derive(Deserialize)]
struct RawChallenge {
    room: String,
    mode: String,
    #[serde(default)]
    party: Option<String>,
    from: RawProfile,
}

impl From<RawChallenge> for OnlineChallenge {
    fn from(c: RawChallenge) -> Self {
        OnlineChallenge { room: c.room, mode: c.mode, party: c.party.unwrap_or_default(), from: c.from.into() }
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

/// The battle protocol this app speaks.
const SERVER_PROTOCOL: u64 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ServerState {
    Offline,
    /// The server speaks an older protocol: battles would hang, so they wait until it's updated.
    Outdated,
    Ready,
}

/// From the answer to `GET /` (None: no answer).
#[uniffi::export]
pub fn server_state(answer: Option<String>) -> ServerState {
    let Some(v) = answer.and_then(|a| serde_json::from_str::<serde_json::Value>(&a).ok()) else {
        return ServerState::Offline;
    };
    match v["v"].as_u64() {
        Some(v) if v >= SERVER_PROTOCOL => ServerState::Ready,
        _ => ServerState::Outdated,
    }
}

/// What a notification (or banner) about an invitation says.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct InviteText {
    pub title: String,
    pub body: String,
}

#[uniffi::export]
pub fn invite_text(invite: OnlineChallenge) -> InviteText {
    let who = &invite.from.nickname;
    if !invite.party.is_empty() {
        return InviteText { title: format!("🎉 {who} 邀请你！"), body: format!("{who} invites you to a party. Tap to join.") };
    }
    let (emoji, mode) = crate::game::battle_mode(invite.mode.clone())
        .map(crate::game::mode_info)
        .map_or(("⚔️".to_string(), "battle".to_string()), |m| (m.emoji, m.title));
    InviteText { title: format!("{emoji} {who} 向你挑战！"), body: format!("{who} challenges you: {mode}. Tap to play.") }
}

/// The invitations nobody has told the learner about yet (`told` = rooms already announced).
#[uniffi::export]
pub fn new_invites(inbox: OnlineInbox, told: Vec<String>) -> Vec<OnlineChallenge> {
    inbox.challenges.into_iter().filter(|c| !told.contains(&c.room)).collect()
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

/// What the server says while waiting for a quick match.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum QueueEvent {
    Queued,
    /// Waiting for a group: how many players there are so far.
    Waiting { count: u32 },
    /// Matched: join this room.
    Matched { room: String, mode: String, opponents: Vec<OnlineProfile> },
    Ignore,
}

pub(crate) fn profile_from(v: &Value) -> Option<OnlineProfile> {
    v.is_object().then(|| serde_json::from_value::<RawProfile>(v.clone()).ok()).flatten().map(OnlineProfile::from)
}

/// Why quick match stopped. `status` is the HTTP status when the server refused, 0 for a lost connection.
#[uniffi::export]
pub fn queue_problem(status: u16) -> String {
    match status {
        400 | 404 => "The battle server doesn't know this game yet: it needs its update. Try Duel, or come back later.",
        401 => "Sign in again to battle.",
        429 => "Too many tries. Wait a moment.",
        0 => "Lost the connection to the server. Check your internet and try again.",
        _ => "The battle server has a problem right now. Try again in a bit.",
    }
    .into()
}

#[uniffi::export]
pub fn queue_event(json: String) -> QueueEvent {
    let Ok(v) = serde_json::from_str::<Value>(&json) else {
        return QueueEvent::Ignore;
    };
    let s = |k: &str| v.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    match s("t").as_str() {
        "queued" => QueueEvent::Queued,
        "waiting" => QueueEvent::Waiting { count: v.get("count").and_then(Value::as_u64).unwrap_or(1) as u32 },
        "matched" => {
            let opponents: Vec<OnlineProfile> = match v.get("players").and_then(Value::as_array) {
                Some(list) => list.iter().filter_map(profile_from).collect(),
                None => v.get("opponent").and_then(profile_from).into_iter().collect(),
            };
            QueueEvent::Matched { room: s("room"), mode: s("mode"), opponents }
        }
        _ => QueueEvent::Ignore,
    }
}

/// Query string for the quick-match queue. `group`: 3–4 players instead of a rated 1v1.
#[uniffi::export]
pub fn queue_path(mode: crate::game::BattleMode, group: bool, swears: bool) -> String {
    format!(
        "/v1/queue?mode={}&size={}&swears={}&v={}",
        crate::game::mode_info(mode).wire,
        if group { 4 } else { 2 },
        swears as u8,
        crate::battle::PROTOCOL
    )
}

/// The code in `POST /v1/party`'s answer.
#[uniffi::export]
pub fn online_parse_party(json: String) -> Result<String, OnlineError> {
    #[derive(Deserialize)]
    struct P {
        code: String,
    }
    Ok(parse::<P>(&json)?.code)
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

/// A nickname made from the name someone typed in onboarding: allowed characters only, "learner" if nothing's left.
#[uniffi::export]
pub fn nickname_from(name: String) -> String {
    let clean: String = name.chars().filter(|c| c.is_alphanumeric() || matches!(c, ' ' | '_' | '.' | '-')).take(16).collect();
    let clean = clean.trim().to_string();
    if nickname_ok(clean.clone()) {
        clean
    } else {
        "learner".into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const P: &str = r#"{"id":"u1","nickname":"小明","tag":"1234","level":2,"streak":5,"xpTotal":900,"xpWeek":40,
      "rating":1016,"wins":1,"losses":0,"cosmetics":{"avatar":"av.panda","aura":"au.fire","title":"ti.boss"},
      "avatar":"/v1/avatars/u1/2","online":true,"friendCode":"ABC234"}"#;

    #[test]
    fn invitations() {
        assert_eq!(server_state(None), ServerState::Offline);
        assert_eq!(server_state(Some("<html>".into())), ServerState::Offline);
        assert_eq!(server_state(Some(r#"{"name":"meitian","ok":true}"#.into())), ServerState::Outdated);
        assert_eq!(server_state(Some(r#"{"name":"meitian","ok":true,"v":2}"#.into())), ServerState::Ready);
        let inbox = online_parse_inbox(format!(
            r#"{{"requests":0,"challenges":[{{"room":"r1","mode":"PinyinType","from":{P}}},{{"room":"r2","mode":"Party","party":"ABCDEF","from":{P}}}]}}"#
        ))
        .unwrap();
        let fresh = new_invites(inbox.clone(), vec!["r1".into()]);
        assert_eq!(fresh.iter().map(|c| c.room.as_str()).collect::<Vec<_>>(), vec!["r2"]);
        assert!(new_invites(inbox.clone(), vec!["r1".into(), "r2".into()]).is_empty(), "told once");
        let t = invite_text(inbox.challenges[0].clone());
        assert!(t.title.contains("小明") && t.body.contains("Pinyin"), "{t:?}");
        assert!(invite_text(inbox.challenges[1].clone()).body.contains("party"));
        assert!(queue_problem(400).contains("update") && queue_problem(0).contains("internet"));
    }

    #[test]
    fn profiles_and_lists() {
        let p = online_parse_profile(format!(r#"{{"profile":{P}}}"#)).unwrap();
        assert_eq!(p.nickname, "小明");
        assert_eq!(p.cosmetic_aura, "au.fire");
        assert_eq!(p.cosmetic_title, "ti.boss");
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
    fn queue() {
        assert_eq!(queue_event(r#"{"t":"queued"}"#.into()), QueueEvent::Queued);
        assert_eq!(queue_event(r#"{"t":"waiting","count":3}"#.into()), QueueEvent::Waiting { count: 3 });
        assert!(matches!(
            queue_event(format!(r#"{{"t":"matched","room":"r1","mode":"Blitz","opponent":{P},"players":[{P},{P}]}}"#)),
            QueueEvent::Matched { ref room, ref opponents, .. } if room == "r1" && opponents.len() == 2
        ));
        assert!(matches!(
            queue_event(format!(r#"{{"t":"matched","room":"r1","mode":"Blitz","opponent":{P}}}"#)),
            QueueEvent::Matched { ref opponents, .. } if opponents.len() == 1
        ));
        assert_eq!(queue_event("pong".into()), QueueEvent::Ignore);
        assert_eq!(queue_path(crate::game::BattleMode::ToneClash, true, false), "/v1/queue?mode=ToneClash&size=4&swears=0&v=2");
        assert_eq!(online_parse_party(r#"{"code":"ABC234"}"#.into()).unwrap(), "ABC234");
        let inbox = online_parse_inbox(format!(
            r#"{{"requests":1,"challenges":[{{"room":"r","mode":"Party","party":"ABC234","from":{P}}},{{"room":"q","mode":"Duel","party":null,"from":{P}}}]}}"#
        ))
        .unwrap();
        assert_eq!(inbox.challenges[0].party, "ABC234");
        assert_eq!(inbox.challenges[1].party, "");
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
        for (name, want) in [("Anna", "Anna"), (" 小明 ", "小明"), ("A", "learner"), ("Zoë 🎉!", "Zoë"), ("www.spam.com", "learner"), ("abcdefghijklmnopqrstu", "abcdefghijklmnop")] {
            assert_eq!(nickname_from(name.into()), want);
            assert!(nickname_ok(nickname_from(name.into())));
        }
    }
}
