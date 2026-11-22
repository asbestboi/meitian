import { authenticate, getPlayer, PlayerRow, publicProfile } from "./players";
import { clampInt, Env, HttpError, json, MAX_PLAYERS, minPlayers, MODES, nicknameOk, now, randomCode, randomId, randomSecret, sha256 } from "./util";

export { Matchmaker } from "./matchmaker";
export { Room } from "./room";

const MAX_AVATAR = 200 * 1024;
/** Most XP one stats sync can add to the weekly board, and how often it may add any. */
const MAX_XP_PER_SYNC = 1500;
const XP_SYNC_GAP_MS = 30_000;
const CHALLENGE_TTL_MS = 10 * 60_000;
const PARTY_TTL_MS = 12 * 3_600_000;
/** One slot machine spin per rolling 24 hours. */
const SPIN_GAP_MS = 24 * 3_600_000;

type Handler = (req: Request, env: Env, params: string[], url: URL) => Promise<Response>;
const routes: [string, RegExp, Handler][] = [];
const route = (method: string, pattern: string, h: Handler) =>
  routes.push([method, new RegExp("^" + pattern.replace(/:\w+/g, "([^/]+)") + "$"), h]);

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    try {
      for (const [method, re, h] of routes) {
        const m = url.pathname.match(re);
        if (m && method === req.method) return await h(req, env, m.slice(1).map(decodeURIComponent), url);
      }
      throw new HttpError(404, "not found");
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error(e);
      return json({ error: "server error" }, 500);
    }
  },

  /** Monday 00:00 UTC: the weekly board starts again. */
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    await weeklyReset(env);
  },
};

export async function weeklyReset(env: Env) {
  await env.DB.prepare("UPDATE players SET xp_week = 0 WHERE xp_week != 0").run();
  await env.DB.prepare("DELETE FROM register_log WHERE at < ?").bind(now() - 86_400_000).run();
  await env.DB.prepare("DELETE FROM rooms WHERE created < ?").bind(now() - 7 * 86_400_000).run();
  await env.DB.prepare("DELETE FROM parties WHERE created < ?").bind(now() - PARTY_TTL_MS).run();
}

async function body<T>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw new HttpError(400, "expected JSON");
  }
}

route("GET", "/", async () => json({ name: "meitian", ok: true }));

// MARK: accounts

route("POST", "/v1/register", async (req, env) => {
  const { nickname } = await body<{ nickname?: string }>(req);
  if (typeof nickname !== "string" || !nicknameOk(nickname)) {
    throw new HttpError(400, "nicknames are 2–16 letters or numbers, no links");
  }
  const ip = req.headers.get("cf-connecting-ip") ?? "local";
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM register_log WHERE ip = ? AND at > ?")
    .bind(ip, now() - 3_600_000)
    .first<{ n: number }>();
  if ((recent?.n ?? 0) >= 5) throw new HttpError(429, "too many new profiles from this network, try later");
  const id = randomId();
  const secret = randomSecret();
  const tag = String(1000 + Math.floor(Math.random() * 9000));
  const t = now();
  for (let attempt = 0; ; attempt++) {
    try {
      await env.DB.prepare(
        `INSERT INTO players (id, secret_hash, nickname, tag, friend_code, created, last_seen)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
        .bind(id, await sha256(secret), nickname, tag, randomCode(6), t, t)
        .run();
      break;
    } catch (e) {
      if (attempt >= 3) throw e; // friend code collision: try another
    }
  }
  await env.DB.prepare("INSERT INTO register_log (ip, at) VALUES (?, ?)").bind(ip, t).run();
  const player = (await getPlayer(env, id))!;
  // the token is also the recovery code: id.secret
  return json({ token: `${id}.${secret}`, profile: publicProfile(player, true) }, 201);
});

route("GET", "/v1/me", async (req, env) => {
  const me = await authenticate(env, req);
  return json({ profile: publicProfile(me, true) });
});

route("PUT", "/v1/me", async (req, env) => {
  const me = await authenticate(env, req);
  const b = await body<{
    nickname?: string;
    level?: number;
    streak?: number;
    xpTotal?: number;
    cosmetics?: unknown;
  }>(req);
  const sets: string[] = [];
  const vals: unknown[] = [];
  const set = (col: string, v: unknown) => {
    sets.push(`${col} = ?`);
    vals.push(v);
  };
  if (b.nickname !== undefined) {
    if (typeof b.nickname !== "string" || !nicknameOk(b.nickname)) {
      throw new HttpError(400, "nicknames are 2–16 letters or numbers, no links");
    }
    set("nickname", b.nickname);
  }
  const level = clampInt(b.level, 0, 9);
  if (level !== null) set("level", level);
  const streak = clampInt(b.streak, 0, 100_000);
  if (streak !== null) set("streak", streak);
  const xp = clampInt(b.xpTotal, 0, 100_000_000);
  if (xp !== null) {
    const t = now();
    // the first sync brings existing progress along without counting it toward this week;
    // after that, gains count (a bounded amount per sync, so a tampered app can't jump the board)
    const gain = me.xp_synced_at === 0 ? 0 : Math.max(0, xp - me.xp_total);
    const counted = t - me.xp_synced_at < XP_SYNC_GAP_MS ? 0 : Math.min(gain, MAX_XP_PER_SYNC);
    set("xp_total", xp);
    if (counted > 0 || me.xp_synced_at === 0) {
      set("xp_week", me.xp_week + counted);
      set("xp_synced_at", t);
    }
  }
  if (b.cosmetics !== undefined) {
    const text = JSON.stringify(b.cosmetics);
    if (text.length > 1000 || typeof b.cosmetics !== "object" || b.cosmetics === null) {
      throw new HttpError(400, "cosmetics too big");
    }
    set("cosmetics", text);
  }
  if (sets.length) {
    await env.DB.prepare(`UPDATE players SET ${sets.join(", ")} WHERE id = ?`).bind(...vals, me.id).run();
  }
  return json({ profile: publicProfile((await getPlayer(env, me.id))!, true) });
});

route("DELETE", "/v1/me", async (req, env) => {
  const me = await authenticate(env, req);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM avatars WHERE player_id = ?").bind(me.id),
    env.DB.prepare("DELETE FROM friends WHERE a = ? OR b = ?").bind(me.id, me.id),
    env.DB.prepare("DELETE FROM reports WHERE target = ? OR reporter = ?").bind(me.id, me.id),
    env.DB.prepare("DELETE FROM rooms WHERE a = ? OR b = ?").bind(me.id, me.id),
    env.DB.prepare("DELETE FROM parties WHERE host = ?").bind(me.id),
    env.DB.prepare("DELETE FROM players WHERE id = ?").bind(me.id),
  ]);
  return json({ deleted: true });
});

// MARK: daily slot machine

/**
 * Records a spin, if 24 hours have passed on the server's clock. The app sends how many spins it knows about
 * (`count`, so spins made offline aren't lost); the answer's `spins` is this spin's number. `wait` is how long until
 * the next one, so the phone's clock doesn't matter.
 */
route("POST", "/v1/spin", async (req, env) => {
  const me = await authenticate(env, req);
  const { count } = await body<{ count?: number }>(req);
  const t = now();
  const known = clampInt(count, 0, 100_000) ?? 0;
  // one statement, so two requests at once can't both win
  const r = await env.DB.prepare("UPDATE players SET last_spin = ?1, spins = MAX(spins, ?2) + 1 WHERE id = ?3 AND last_spin <= ?4")
    .bind(t, known, me.id, t - SPIN_GAP_MS)
    .run();
  const p = (await getPlayer(env, me.id))!;
  const wait = Math.max(0, p.last_spin + SPIN_GAP_MS - t);
  return json({ allowed: r.meta.changes > 0, spins: p.spins, wait }, 200);
});

// MARK: profile pictures

function imageType(bytes: Uint8Array): string | null {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
  return null;
}

route("PUT", "/v1/me/avatar", async (req, env) => {
  const me = await authenticate(env, req);
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (bytes.length === 0 || bytes.length > MAX_AVATAR) throw new HttpError(413, "picture must be under 200 KB");
  if (!imageType(bytes)) throw new HttpError(415, "send a JPEG or PNG");
  const version = me.avatar_version + 1;
  // one row per player: the new picture replaces the old one, which is gone for good
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO avatars (player_id, version, bytes) VALUES (?, ?, ?)").bind(
      me.id,
      version,
      bytes,
    ),
    env.DB.prepare("UPDATE players SET avatar_version = ? WHERE id = ?").bind(version, me.id),
  ]);
  return json({ avatar: `/v1/avatars/${me.id}/${version}` });
});

route("DELETE", "/v1/me/avatar", async (req, env) => {
  const me = await authenticate(env, req);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM avatars WHERE player_id = ?").bind(me.id),
    env.DB.prepare("UPDATE players SET avatar_version = 0 WHERE id = ?").bind(me.id),
  ]);
  return json({ avatar: null });
});

route("GET", "/v1/avatars/:id/:version", async (_req, env, [id, version]) => {
  const row = await env.DB.prepare("SELECT bytes FROM avatars WHERE player_id = ? AND version = ?")
    .bind(id, Number(version))
    .first<{ bytes: ArrayBuffer | number[] }>();
  if (!row) throw new HttpError(404, "no such picture");
  const bytes = row.bytes instanceof ArrayBuffer ? new Uint8Array(row.bytes) : new Uint8Array(row.bytes);
  return new Response(bytes, {
    headers: {
      "content-type": imageType(bytes) ?? "application/octet-stream",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
});

// MARK: profiles and reports

route("GET", "/v1/players/:id", async (req, env, [id]) => {
  await authenticate(env, req);
  const p = await getPlayer(env, id);
  if (!p) throw new HttpError(404, "no such player");
  return json({ profile: publicProfile(p) });
});

const REPORTS_TO_HIDE = 3;

route("POST", "/v1/report/:id", async (req, env, [id]) => {
  const me = await authenticate(env, req);
  if (id === me.id) throw new HttpError(400, "that's you");
  if (!(await getPlayer(env, id))) throw new HttpError(404, "no such player");
  await env.DB.prepare("INSERT OR IGNORE INTO reports (target, reporter, created) VALUES (?, ?, ?)")
    .bind(id, me.id, now())
    .run();
  const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM reports WHERE target = ?").bind(id).first<{ n: number }>();
  if ((n?.n ?? 0) >= REPORTS_TO_HIDE) {
    // enough people complained: picture gone, nickname reset
    await env.DB.batch([
      env.DB.prepare("DELETE FROM avatars WHERE player_id = ?").bind(id),
      env.DB.prepare("UPDATE players SET avatar_version = 0, nickname = 'player' WHERE id = ?").bind(id),
      env.DB.prepare("DELETE FROM reports WHERE target = ?").bind(id),
    ]);
  }
  return json({ reported: true });
});

// MARK: friends and challenges

async function friendIds(env: Env, id: string): Promise<string[]> {
  const { results } = await env.DB.prepare(
    "SELECT CASE WHEN a = ?1 THEN b ELSE a END AS id FROM friends WHERE (a = ?1 OR b = ?1) AND accepted = 1",
  )
    .bind(id)
    .all<{ id: string }>();
  return results.map((r) => r.id);
}

async function profiles(env: Env, ids: string[]): Promise<PlayerRow[]> {
  if (!ids.length) return [];
  const { results } = await env.DB.prepare(`SELECT * FROM players WHERE id IN (${ids.map(() => "?").join(",")})`)
    .bind(...ids)
    .all<PlayerRow>();
  return results;
}

route("GET", "/v1/friends", async (req, env) => {
  const me = await authenticate(env, req);
  const friends = await profiles(env, await friendIds(env, me.id));
  const incoming = await env.DB.prepare(
    "SELECT p.* FROM friends f JOIN players p ON p.id = f.a WHERE f.b = ? AND f.accepted = 0",
  )
    .bind(me.id)
    .all<PlayerRow>();
  const outgoing = await env.DB.prepare(
    "SELECT p.* FROM friends f JOIN players p ON p.id = f.b WHERE f.a = ? AND f.accepted = 0",
  )
    .bind(me.id)
    .all<PlayerRow>();
  return json({
    friends: friends
      .map((p) => publicProfile(p))
      .sort((x, y) => Number(y.online) - Number(x.online) || x.nickname.localeCompare(y.nickname)),
    incoming: incoming.results.map((p) => publicProfile(p)),
    outgoing: outgoing.results.map((p) => publicProfile(p)),
    challenges: await challenges(env, me.id),
  });
});

async function challenges(env: Env, id: string) {
  const { results } = await env.DB.prepare(
    `SELECT r.id AS room, r.mode, r.party, p.* FROM rooms r JOIN players p ON p.id = r.a
     WHERE r.b = ? AND r.challenge = 1 AND r.status = 'open' AND r.created > ? ORDER BY r.created DESC`,
  )
    .bind(id, now() - CHALLENGE_TTL_MS)
    .all<PlayerRow & { room: string; mode: string; party: string | null }>();
  return results.map((r) => ({ room: r.room, mode: r.mode, party: r.party, from: publicProfile(r) }));
}

/** Cheap poll for the Battle tab: incoming friend requests and challenges. */
route("GET", "/v1/inbox", async (req, env) => {
  const me = await authenticate(env, req);
  const requests = await env.DB.prepare("SELECT COUNT(*) AS n FROM friends WHERE b = ? AND accepted = 0")
    .bind(me.id)
    .first<{ n: number }>();
  return json({ requests: requests?.n ?? 0, challenges: await challenges(env, me.id) });
});

route("POST", "/v1/friends", async (req, env) => {
  const me = await authenticate(env, req);
  const { code } = await body<{ code?: string }>(req);
  const clean = String(code ?? "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  const other = await env.DB.prepare("SELECT * FROM players WHERE friend_code = ?").bind(clean).first<PlayerRow>();
  if (!other) throw new HttpError(404, "no player with that code");
  if (other.id === me.id) throw new HttpError(400, "that's your own code");
  const theirs = await env.DB.prepare("SELECT accepted FROM friends WHERE a = ? AND b = ?")
    .bind(other.id, me.id)
    .first<{ accepted: number }>();
  if (theirs) {
    // they already asked me: adding them back accepts
    await env.DB.prepare("UPDATE friends SET accepted = 1 WHERE a = ? AND b = ?").bind(other.id, me.id).run();
    return json({ status: "friends", profile: publicProfile(other) });
  }
  await env.DB.prepare("INSERT OR IGNORE INTO friends (a, b, accepted, created) VALUES (?, ?, 0, ?)")
    .bind(me.id, other.id, now())
    .run();
  const mine = await env.DB.prepare("SELECT accepted FROM friends WHERE a = ? AND b = ?")
    .bind(me.id, other.id)
    .first<{ accepted: number }>();
  return json({ status: mine?.accepted ? "friends" : "requested", profile: publicProfile(other) });
});

route("POST", "/v1/friends/:id/accept", async (req, env, [id]) => {
  const me = await authenticate(env, req);
  const r = await env.DB.prepare("UPDATE friends SET accepted = 1 WHERE a = ? AND b = ?").bind(id, me.id).run();
  if (!r.meta.changes) throw new HttpError(404, "no request from that player");
  return json({ status: "friends" });
});

route("DELETE", "/v1/friends/:id", async (req, env, [id]) => {
  const me = await authenticate(env, req);
  await env.DB.prepare("DELETE FROM friends WHERE (a = ?1 AND b = ?2) OR (a = ?2 AND b = ?1)").bind(me.id, id).run();
  return json({ status: "removed" });
});

route("POST", "/v1/challenge", async (req, env) => {
  const me = await authenticate(env, req);
  const { friendId, mode } = await body<{ friendId?: string; mode?: string }>(req);
  if (!MODES.includes(mode as never)) throw new HttpError(400, "unknown mode");
  if (minPlayers(String(mode)) > 2) throw new HttpError(400, "that mode needs more players: start a party");
  if (!(await friendIds(env, me.id)).includes(String(friendId))) throw new HttpError(403, "you can only challenge friends");
  const room = randomId();
  await env.DB.prepare("INSERT INTO rooms (id, a, b, mode, challenge, created) VALUES (?, ?, ?, ?, 1, ?)")
    .bind(room, me.id, friendId, mode, now())
    .run();
  return json({ room }, 201);
});

route("POST", "/v1/challenge/:room/decline", async (req, env, [room]) => {
  const me = await authenticate(env, req);
  await env.DB.prepare("UPDATE rooms SET status = 'declined' WHERE id = ? AND (a = ?2 OR b = ?2)")
    .bind(room, me.id)
    .run();
  return json({ status: "declined" });
});

// MARK: parties

/** A private party of up to four: the host shares the code, friends join, the host starts the games. */
route("POST", "/v1/party", async (req, env) => {
  const me = await authenticate(env, req);
  const b = await body<{ swears?: boolean }>(req);
  const t = now();
  await env.DB.prepare("DELETE FROM parties WHERE host = ? OR created < ?").bind(me.id, t - PARTY_TTL_MS).run();
  for (let attempt = 0; ; attempt++) {
    const code = randomCode(6);
    try {
      await env.DB.prepare("INSERT INTO parties (code, room, host, swears, created) VALUES (?, ?, ?, ?, ?)")
        .bind(code, randomId(), me.id, b.swears ? 1 : 0, t)
        .run();
      return json({ code }, 201);
    } catch (e) {
      if (attempt >= 3) throw e; // code collision: try another
    }
  }
});

interface PartyRow {
  code: string;
  room: string;
  host: string;
  swears: number;
}

async function party(env: Env, code: string): Promise<PartyRow> {
  const clean = code.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  const row = await env.DB.prepare("SELECT * FROM parties WHERE code = ? AND created > ?")
    .bind(clean, now() - PARTY_TTL_MS)
    .first<PartyRow>();
  if (!row) throw new HttpError(404, "no party with that code");
  return row;
}

/** Puts an invitation to the party into a friend's inbox. */
route("POST", "/v1/party/:code/invite", async (req, env, [code]) => {
  const me = await authenticate(env, req);
  const { friendId } = await body<{ friendId?: string }>(req);
  const p = await party(env, code);
  if (!(await friendIds(env, me.id)).includes(String(friendId))) throw new HttpError(403, "you can only invite friends");
  // one open invitation per friend and party
  await env.DB.prepare("DELETE FROM rooms WHERE a = ? AND b = ? AND party = ?").bind(me.id, friendId, p.code).run();
  await env.DB.prepare("INSERT INTO rooms (id, a, b, mode, challenge, created, party) VALUES (?, ?, ?, 'Party', 1, ?, ?)")
    .bind(randomId(), me.id, friendId, now(), p.code)
    .run();
  return json({ status: "invited" }, 201);
});

route("GET", "/v1/party/:code", async (req, env, [code], url) => {
  const me = await authenticate(env, req);
  const p = await party(env, code);
  if ((url.searchParams.get("swears") === "1") !== (p.swears === 1)) {
    throw new HttpError(412, "this party has a different swear-word setting");
  }
  await env.DB.prepare("UPDATE rooms SET status = 'done' WHERE b = ? AND party = ?").bind(me.id, p.code).run();
  return forwardSocket(req, env.ROOMS.get(env.ROOMS.idFromName(p.room)), {
    "x-player": me.id,
    "x-room": p.room,
    "x-kind": "party",
    "x-players": encodeURIComponent(JSON.stringify([])),
    "x-profiles": encodeURIComponent(JSON.stringify({ [me.id]: publicProfile(me) })),
  });
});

// MARK: leaderboards

route("GET", "/v1/leaderboard", async (req, env, _p, url) => {
  const me = await authenticate(env, req);
  const board = url.searchParams.get("board") === "rating" ? "rating" : "week";
  const col = board === "rating" ? "rating" : "xp_week";
  const friendsOnly = url.searchParams.get("scope") === "friends";
  let rows: PlayerRow[];
  let rank: number;
  if (friendsOnly) {
    rows = await profiles(env, [me.id, ...(await friendIds(env, me.id))]);
    rows.sort((a, b) => (b as any)[col] - (a as any)[col] || b.xp_total - a.xp_total);
    rank = rows.findIndex((r) => r.id === me.id) + 1;
  } else {
    // weekly board: only people who played this week
    const where = board === "week" ? "WHERE xp_week > 0" : "";
    rows = (
      await env.DB.prepare(`SELECT * FROM players ${where} ORDER BY ${col} DESC, xp_total DESC LIMIT 100`).all<PlayerRow>()
    ).results;
    const above = await env.DB.prepare(`SELECT COUNT(*) AS n FROM players WHERE ${col} > ?`)
      .bind((me as any)[col])
      .first<{ n: number }>();
    rank = (above?.n ?? 0) + 1;
  }
  return json({
    board,
    top: rows.slice(0, 100).map((p, i) => ({ rank: i + 1, profile: publicProfile(p, p.id === me.id) })),
    me: { rank, profile: publicProfile(me, true) },
  });
});

// MARK: live play (WebSockets)

function forwardSocket(req: Request, stub: DurableObjectStub, headers: Record<string, string>): Promise<Response> {
  if (req.headers.get("upgrade")?.toLowerCase() !== "websocket") throw new HttpError(426, "expected a WebSocket");
  const h = new Headers(req.headers);
  for (const [k, v] of Object.entries(headers)) h.set(k, v);
  return stub.fetch(new Request(req.url, { headers: h }));
}

route("GET", "/v1/queue", async (req, env, _p, url) => {
  const me = await authenticate(env, req);
  const mode = url.searchParams.get("mode") ?? "Duel";
  if (!MODES.includes(mode as never)) throw new HttpError(400, "unknown mode");
  const size = url.searchParams.get("size") === "4" ? MAX_PLAYERS : 2;
  if (size < minPlayers(mode)) throw new HttpError(400, "that mode is for groups");
  const stub = env.MATCHMAKER.get(env.MATCHMAKER.idFromName("global"));
  return forwardSocket(req, stub, {
    "x-player": me.id,
    "x-rating": String(me.rating),
    "x-mode": mode,
    "x-swears": url.searchParams.get("swears") === "1" ? "1" : "0",
    "x-size": String(size),
    "x-v": String(clampInt(Number(url.searchParams.get("v") ?? 1), 1, 99) ?? 1),
    "x-profile": encodeURIComponent(JSON.stringify(publicProfile(me))),
  });
});

route("GET", "/v1/rooms/:id", async (req, env, [id]) => {
  const me = await authenticate(env, req);
  const room = await env.DB.prepare("SELECT * FROM rooms WHERE id = ? AND party IS NULL")
    .bind(id)
    .first<{ a: string; b: string; status: string; mode: string; players: string | null }>();
  const players: string[] = !room ? [] : room.players ? JSON.parse(room.players) : [room.a, room.b];
  if (!room || !players.includes(me.id)) throw new HttpError(404, "no such room");
  if (room.status === "declined") throw new HttpError(410, "challenge declined");
  const rows = await profiles(env, players);
  return forwardSocket(req, env.ROOMS.get(env.ROOMS.idFromName(id)), {
    "x-player": me.id,
    "x-room": id,
    "x-kind": players.length > 2 ? "group" : "duo",
    "x-players": encodeURIComponent(JSON.stringify(players)),
    "x-profiles": encodeURIComponent(JSON.stringify(Object.fromEntries(rows.map((p) => [p.id, publicProfile(p)])))),
  });
});
