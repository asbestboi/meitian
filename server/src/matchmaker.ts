import { DurableObject } from "cloudflare:workers";
import { Env, MAX_PLAYERS, minPlayers, now, randomId } from "./util";

interface Waiting {
  id: string;
  rating: number;
  mode: string;
  swears: boolean;
  /** 2 = rated 1v1, 4 = public group. */
  size: number;
  /** Battle protocol version of the app: different ones can't play each other. */
  v: number;
  profile: unknown;
  since: number;
}

/** A group starts with three players if a fourth hasn't turned up after this long. */
export const GROUP_WAIT_MS = 20_000;

/** How far apart two ratings may be after someone has waited `ms`: tight at first, anyone after 30 s. */
export function ratingWindow(ms: number): number {
  if (ms >= 30_000) return Infinity;
  return 100 + Math.floor(ms / 5000) * 75;
}

/** How many of `waiting` players (the first one waited `ms`) start a group match now; 0 = keep waiting. */
export function groupSize(mode: string, waiting: number, ms: number): number {
  if (waiting >= MAX_PLAYERS) return MAX_PLAYERS;
  const min = Math.max(3, minPlayers(mode));
  return waiting >= min && ms >= GROUP_WAIT_MS ? waiting : 0;
}

type Entry = [WebSocket, Waiting];

/**
 * Quick match: one global instance holds everyone waiting (as hibernating WebSockets, so idle queues cost
 * nothing). Players are matched within the same mode, swear setting and app protocol: closest rating first in
 * 1v1, longest wait first in groups (which are unrated).
 */
export class Matchmaker extends DurableObject<Env> {
  async fetch(req: Request): Promise<Response> {
    const h = req.headers;
    const me: Waiting = {
      id: h.get("x-player")!,
      rating: Number(h.get("x-rating")),
      mode: h.get("x-mode")!,
      swears: h.get("x-swears") === "1",
      size: Number(h.get("x-size") ?? 2),
      v: Number(h.get("x-v") ?? 1),
      profile: JSON.parse(decodeURIComponent(h.get("x-profile") ?? "null")),
      since: now(),
    };
    // one queue entry per player: a second phone or a retry replaces the first
    for (const ws of this.ctx.getWebSockets(me.id)) ws.close(4000, "replaced");
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [me.id]);
    pair[1].serializeAttachment(me);
    pair[1].send(JSON.stringify({ t: "queued" }));
    await this.match();
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, msg: string | ArrayBuffer) {
    if (msg === "ping") ws.send("pong");
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try {
      ws.close(code === 1005 ? 1000 : code, "bye");
    } catch {}
    this.countGroups();
  }

  async alarm() {
    await this.match();
  }

  private waiting(): Entry[] {
    return this.ctx
      .getWebSockets()
      .filter((ws) => ws.readyState === WebSocket.OPEN)
      .map((ws) => [ws, ws.deserializeAttachment() as Waiting] as Entry)
      .filter(([, w]) => !!w)
      .sort((x, y) => x[1].since - y[1].since);
  }

  private groups(list: Entry[]): Entry[][] {
    const by = new Map<string, Entry[]>();
    for (const e of list) {
      const w = e[1];
      if (w.size <= 2) continue;
      const key = `${w.mode}|${w.swears}|${w.v}`;
      by.set(key, [...(by.get(key) ?? []), e]);
    }
    return [...by.values()];
  }

  /** Tells everyone waiting for a group how many are there. */
  private countGroups() {
    for (const group of this.groups(this.waiting())) {
      for (const [ws] of group) {
        try {
          ws.send(JSON.stringify({ t: "waiting", count: group.length }));
        } catch {}
      }
    }
  }

  private async match() {
    const list = this.waiting();
    const taken = new Set<string>();
    const t = now();
    for (const [ws, w] of list) {
      if (w.size > 2 || taken.has(w.id)) continue;
      let best: Entry | null = null;
      for (const other of list) {
        const o = other[1];
        if (o.id === w.id || taken.has(o.id) || o.size > 2 || o.mode !== w.mode || o.swears !== w.swears || o.v !== w.v) continue;
        const gap = Math.abs(o.rating - w.rating);
        if (gap > ratingWindow(t - Math.min(w.since, o.since))) continue;
        if (!best || gap < Math.abs(best[1].rating - w.rating)) best = other;
      }
      if (!best) continue;
      await this.start([[ws, w], best], taken);
    }
    for (const group of this.groups(list)) {
      let rest = group.filter(([, w]) => !taken.has(w.id));
      for (;;) {
        const n = rest.length ? groupSize(rest[0][1].mode, rest.length, t - rest[0][1].since) : 0;
        if (!n) break;
        await this.start(rest.slice(0, n), taken);
        rest = rest.slice(n);
      }
    }
    this.countGroups();
    // keep looking while people wait (the rating window widens, groups settle for three)
    if (this.waiting().length > 1) await this.ctx.storage.setAlarm(now() + 5000);
  }

  private async start(entries: Entry[], taken: Set<string>) {
    const room = randomId();
    const players = entries.map(([, w]) => w.id);
    players.forEach((id) => taken.add(id));
    const mode = entries[0][1].mode;
    // the player who waited longest goes first in the room record
    await this.env.DB.prepare("INSERT INTO rooms (id, a, b, mode, challenge, created, players) VALUES (?, ?, ?, ?, 0, ?, ?)")
      .bind(room, players[0], players[1], mode, now(), players.length > 2 ? JSON.stringify(players) : null)
      .run();
    for (const [sock, w] of entries) {
      const others = entries.filter(([, o]) => o.id !== w.id).map(([, o]) => o.profile);
      try {
        sock.send(JSON.stringify({ t: "matched", room, mode, opponent: others[0], players: others }));
        sock.close(1000, "matched");
      } catch {}
    }
  }
}
