import { DurableObject } from "cloudflare:workers";
import { recordResult } from "./rating";
import { Env, now } from "./util";

/** How long a dropped player has to come back before an unfinished game counts as their loss. */
export const FORFEIT_MS = 30_000;

interface Meta {
  room: string;
  a: string;
  b: string;
}

interface Game {
  /** Bumped by every "start" the host sends (a rematch is a new game). */
  number: number;
  started: boolean;
  recorded: boolean;
  /** Each player's own outcome: true = I won, false = I lost, null = draw. */
  reports: Record<string, boolean | null>;
}

/**
 * One battle between two players. The phones speak the same JSON battle protocol as on the iPhone ↔ Android
 * Wi‑Fi link (host referees, see DuelMatch / Battle.kt); this object relays it and adds:
 * - `{"t":"_peer","up":bool}` when the other player connects or drops (drives the apps' reconnect logic)
 * - ratings: after a game each phone sends `{"t":"report","won":true|false|null}`. The result is written once
 *   both reports agree; a player who drops mid-game and doesn't return within 30 s forfeits.
 */
export class Room extends DurableObject<Env> {
  async fetch(req: Request): Promise<Response> {
    const h = req.headers;
    const player = h.get("x-player")!;
    const meta: Meta = { room: h.get("x-room")!, a: h.get("x-a")!, b: h.get("x-b")! };
    await this.ctx.storage.put("meta", meta);
    for (const ws of this.ctx.getWebSockets(player)) ws.close(4000, "replaced");
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [player]);
    pair[1].serializeAttachment({ player });
    const other = player === meta.a ? meta.b : meta.a;
    const otherHere = this.sockets(other).length > 0;
    pair[1].send(
      JSON.stringify({
        t: "_room",
        room: meta.room,
        opponent: JSON.parse(decodeURIComponent(h.get("x-opponent") ?? "null")),
        peer: otherHere,
      }),
    );
    this.sendTo(other, { t: "_peer", up: true });
    if (otherHere) await this.ctx.storage.deleteAlarm();
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  private sockets(player: string): WebSocket[] {
    return this.ctx.getWebSockets(player).filter((ws) => ws.readyState === WebSocket.OPEN);
  }

  private sendTo(player: string, msg: unknown) {
    const text = typeof msg === "string" ? msg : JSON.stringify(msg);
    for (const ws of this.sockets(player)) {
      try {
        ws.send(text);
      } catch {}
    }
  }

  private playerOf(ws: WebSocket): string | null {
    return (ws.deserializeAttachment() as { player?: string } | null)?.player ?? null;
  }

  private async game(): Promise<Game> {
    return (await this.ctx.storage.get<Game>("game")) ?? { number: 0, started: false, recorded: false, reports: {} };
  }

  async webSocketMessage(ws: WebSocket, msg: string | ArrayBuffer) {
    if (typeof msg !== "string") return;
    if (msg === "ping") {
      ws.send("pong");
      return;
    }
    const player = this.playerOf(ws);
    const meta = await this.ctx.storage.get<Meta>("meta");
    if (!player || !meta) return;
    const other = player === meta.a ? meta.b : meta.a;
    let t = "";
    let parsed: any = null;
    try {
      parsed = JSON.parse(msg);
      t = typeof parsed?.t === "string" ? parsed.t : "";
    } catch {
      return;
    }
    if (t === "report") {
      await this.report(meta, player, parsed.won);
      return;
    }
    if (t === "start") {
      const g = await this.game();
      await this.ctx.storage.put("game", { number: g.number + 1, started: true, recorded: false, reports: {} });
    } else if (t === "lobby") {
      // back to the lobby before a result: the game is called off without a rating change
      const g = await this.game();
      if (!g.recorded) await this.ctx.storage.put("game", { ...g, started: false });
    }
    if (t.startsWith("_")) return; // server-only messages can't be forged by a client
    this.sendTo(other, msg);
  }

  private async report(meta: Meta, player: string, won: unknown) {
    const g = await this.game();
    if (!g.started || g.recorded) return;
    g.reports[player] = won === true ? true : won === false ? false : null;
    const ra = g.reports[meta.a];
    const rb = g.reports[meta.b];
    if (ra === undefined || rb === undefined) {
      await this.ctx.storage.put("game", g);
      return;
    }
    // both phones must tell the same story: one won and the other lost, or both say draw
    const agree = (ra === null && rb === null) || (ra !== null && rb !== null && ra === !rb);
    g.recorded = true;
    g.started = false;
    await this.ctx.storage.put("game", g);
    if (!agree) {
      for (const p of [meta.a, meta.b]) this.sendTo(p, { t: "_rating", counted: false });
      return;
    }
    await this.finish(meta, ra === null ? 0.5 : ra ? 1 : 0);
  }

  private async finish(meta: Meta, scoreA: 1 | 0.5 | 0) {
    const before = await this.env.DB.prepare("SELECT id, rating FROM players WHERE id IN (?, ?)")
      .bind(meta.a, meta.b)
      .all<{ id: string; rating: number }>();
    const after = await recordResult(this.env, meta.a, meta.b, scoreA);
    await this.env.DB.prepare("UPDATE rooms SET status = 'done' WHERE id = ?").bind(meta.room).run();
    for (const p of [meta.a, meta.b]) {
      const old = before.results.find((r) => r.id === p)?.rating ?? 0;
      if (after[p] !== undefined) this.sendTo(p, { t: "_rating", counted: true, rating: after[p], delta: after[p] - old });
    }
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try {
      ws.close(code === 1005 ? 1000 : code, "bye");
    } catch {}
    const player = this.playerOf(ws);
    const meta = await this.ctx.storage.get<Meta>("meta");
    if (!player || !meta) return;
    if (this.sockets(player).length > 0) return; // replaced by a newer connection
    const other = player === meta.a ? meta.b : meta.a;
    this.sendTo(other, { t: "_peer", up: false });
    const g = await this.game();
    if (g.started && !g.recorded) await this.ctx.storage.setAlarm(now() + FORFEIT_MS);
  }

  async webSocketError(ws: WebSocket) {
    await this.webSocketClose(ws, 1011);
  }

  /** A player dropped mid-game and didn't come back: the one still here wins. */
  async alarm() {
    const meta = await this.ctx.storage.get<Meta>("meta");
    const g = await this.game();
    if (!meta || !g.started || g.recorded) return;
    const aHere = this.sockets(meta.a).length > 0;
    const bHere = this.sockets(meta.b).length > 0;
    if (aHere === bHere) return; // both back, or both gone (abandoned: no rating change)
    g.recorded = true;
    g.started = false;
    await this.ctx.storage.put("game", g);
    const winner = aHere ? meta.a : meta.b;
    this.sendTo(winner, { t: "_forfeit" });
    await this.finish(meta, aHere ? 1 : 0);
  }
}
