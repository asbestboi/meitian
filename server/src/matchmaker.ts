import { DurableObject } from "cloudflare:workers";
import { Env, now, randomId } from "./util";

interface Waiting {
  id: string;
  rating: number;
  mode: string;
  swears: boolean;
  profile: unknown;
  since: number;
}

/** How far apart two ratings may be after someone has waited `ms`: tight at first, anyone after 30 s. */
export function ratingWindow(ms: number): number {
  if (ms >= 30_000) return Infinity;
  return 100 + Math.floor(ms / 5000) * 75;
}

/**
 * Quick match: one global instance holds everyone waiting (as hibernating WebSockets, so idle queues cost
 * nothing). Players are paired within the same mode and swear setting, closest rating first.
 */
export class Matchmaker extends DurableObject<Env> {
  async fetch(req: Request): Promise<Response> {
    const h = req.headers;
    const me: Waiting = {
      id: h.get("x-player")!,
      rating: Number(h.get("x-rating")),
      mode: h.get("x-mode")!,
      swears: h.get("x-swears") === "1",
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
  }

  async alarm() {
    await this.match();
  }

  private waiting(): [WebSocket, Waiting][] {
    return this.ctx
      .getWebSockets()
      .filter((ws) => ws.readyState === WebSocket.OPEN)
      .map((ws) => [ws, ws.deserializeAttachment() as Waiting] as [WebSocket, Waiting])
      .filter(([, w]) => !!w)
      .sort((x, y) => x[1].since - y[1].since);
  }

  private async match() {
    const list = this.waiting();
    const taken = new Set<string>();
    const t = now();
    for (const [ws, w] of list) {
      if (taken.has(w.id)) continue;
      let best: [WebSocket, Waiting] | null = null;
      for (const other of list) {
        const o = other[1];
        if (o.id === w.id || taken.has(o.id) || o.mode !== w.mode || o.swears !== w.swears) continue;
        const gap = Math.abs(o.rating - w.rating);
        if (gap > ratingWindow(t - Math.min(w.since, o.since))) continue;
        if (!best || gap < Math.abs(best[1].rating - w.rating)) best = other;
      }
      if (!best) continue;
      taken.add(w.id);
      taken.add(best[1].id);
      const room = randomId();
      // the player who waited longest goes first in the room record
      await this.env.DB.prepare("INSERT INTO rooms (id, a, b, mode, challenge, created) VALUES (?, ?, ?, ?, 0, ?)")
        .bind(room, w.id, best[1].id, w.mode, t)
        .run();
      for (const [sock, opp] of [
        [ws, best[1]],
        [best[0], w],
      ] as const) {
        try {
          sock.send(JSON.stringify({ t: "matched", room, mode: w.mode, opponent: opp.profile }));
          sock.close(1000, "matched");
        } catch {}
      }
    }
    // keep looking while people wait (the rating window widens over time)
    if (this.waiting().length > 1) await this.ctx.storage.setAlarm(now() + 5000);
  }
}
