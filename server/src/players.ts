import { Env, HttpError, now, sha256 } from "./util";

export interface PlayerRow {
  id: string;
  secret_hash: string;
  nickname: string;
  tag: string;
  friend_code: string;
  level: number;
  streak: number;
  xp_total: number;
  xp_week: number;
  rating: number;
  wins: number;
  losses: number;
  cosmetics: string;
  avatar_version: number;
  xp_synced_at: number;
  created: number;
  last_seen: number;
}

export const ONLINE_MS = 60_000;

/** What other players see. `friendCode` only goes to the player themselves. */
export function publicProfile(p: PlayerRow, self = false) {
  let cosmetics: unknown = {};
  try {
    cosmetics = JSON.parse(p.cosmetics);
  } catch {}
  return {
    id: p.id,
    nickname: p.nickname,
    tag: p.tag,
    level: p.level,
    streak: p.streak,
    xpTotal: p.xp_total,
    xpWeek: p.xp_week,
    rating: p.rating,
    wins: p.wins,
    losses: p.losses,
    cosmetics,
    avatar: p.avatar_version > 0 ? `/v1/avatars/${p.id}/${p.avatar_version}` : null,
    online: now() - p.last_seen < ONLINE_MS,
    ...(self ? { friendCode: p.friend_code } : {}),
  };
}
export type Profile = ReturnType<typeof publicProfile>;

export async function getPlayer(env: Env, id: string): Promise<PlayerRow | null> {
  return env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first<PlayerRow>();
}

/** `Authorization: Bearer <id>.<secret>`. Also marks the player as seen (at most every 20 s). */
export async function authenticate(env: Env, req: Request): Promise<PlayerRow> {
  const header = req.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  const dot = token.indexOf(".");
  if (dot < 1) throw new HttpError(401, "sign in first");
  const id = token.slice(0, dot);
  const player = await getPlayer(env, id);
  if (!player || player.secret_hash !== (await sha256(token.slice(dot + 1)))) {
    throw new HttpError(401, "unknown player or wrong recovery code");
  }
  const t = now();
  if (t - player.last_seen > 20_000) {
    await env.DB.prepare("UPDATE players SET last_seen = ? WHERE id = ?").bind(t, id).run();
    player.last_seen = t;
  }
  return player;
}
