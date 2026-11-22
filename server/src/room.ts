import { DurableObject } from "cloudflare:workers";
import { recordResult } from "./rating";
import { Env, MAX_PLAYERS, json, now } from "./util";

/** How long a dropped player has to come back before they forfeit (or lose their place in a party). */
export const FORFEIT_MS = 30_000;

/** duo: a rated 1v1 (quick match, friend challenge). group: a public group match. party: joined by code. */
export type RoomKind = "duo" | "group" | "party";

interface Meta {
  room: string;
  kind: RoomKind;
  /** In joining order; the next connected one takes over when the host leaves. */
  players: string[];
  /** The player whose phone referees. Null until somebody connects. */
  host: string | null;
}

interface Game {
  /** Bumped by every "start" the host sends (a rematch is a new game). */
  number: number;
  started: boolean;
  recorded: boolean;
  /** Each player's own outcome: true = I won, false = I lost, null = draw. */
  reports: Record<string, boolean | null>;
}

/** Only the host may send these (the referee's decisions). Not enforced in duos, where app versions up to
 *  1.12 pick their own referee. */
const HOST_ONLY = new Set(["start", "round", "result", "finished", "lobby", "resume", "score"]);

/**
 * One battle between 2–4 players. The phones speak the JSON battle protocol (the host's phone referees, see
 * core/src/battle.rs); this object relays it to everybody else, stamped with `from`, and adds:
 * - `_room` on joining: who is in the room, who is here, who hosts, and the last scoreboard
 * - `{"t":"_peer","up":bool,"id":…}` when a player connects or drops
 * - `{"t":"_host","id":…}` when the host drops and the next player takes over
 * - `{"t":"_players",…}` when the roster changes (parties), `_score` with the host's scoreboard
 * - `{"t":"_forfeit","id":…}` for a player who left mid-game, or dropped and didn't return within 30 s
 * - ratings (duos only): after a game each phone sends `{"t":"report","won":true|false|null}`. The result is
 *   written once both reports agree; a forfeit counts as a loss.
 */
export class Room extends DurableObject<Env> {
  async fetch(req: Request): Promise<Response> {
    const h = req.headers;
    const player = h.get("x-player")!;
    const fromHeader = <T>(k: string, fallback: T): T => JSON.parse(decodeURIComponent(h.get(k) ?? "null")) ?? fallback;
    const kind = (h.get("x-kind") ?? "duo") as RoomKind;
    let meta = await this.ctx.storage.get<Meta>("meta");
    if (!meta) {
      meta = { room: h.get("x-room")!, kind, players: fromHeader<string[]>("x-players", []), host: null };
    }
    const profiles = (await this.ctx.storage.get<Record<string, unknown>>("profiles")) ?? {};
    if (!meta.players.includes(player)) {
      if (meta.kind !== "party") return json({ error: "you left this match" }, 410);
      if (meta.players.length >= MAX_PLAYERS) return json({ error: "this party is full" }, 409);
      if ((await this.game()).started) return json({ error: "this party is already playing" }, 409);
      meta.players.push(player);
    }
    Object.assign(profiles, fromHeader("x-profiles", {}));
    for (const id of Object.keys(profiles)) if (!meta.players.includes(id)) delete profiles[id];

    for (const ws of this.ctx.getWebSockets(player)) ws.close(4000, "replaced");
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [player]);
    pair[1].serializeAttachment({ player });
    if (!meta.host || !this.here(meta.host)) meta.host = player;
    await this.ctx.storage.put({ meta, profiles });
    const away = await this.away();
    delete away[player];
    await this.setAway(away);

    const others = meta.players.filter((p) => p !== player);
    const roster = this.roster(meta, profiles);
    pair[1].send(
      JSON.stringify({
        t: "_room",
        room: meta.room,
        kind: meta.kind,
        you: player,
        host: meta.host,
        players: roster,
        score: (await this.ctx.storage.get("score")) ?? null,
        // apps up to 1.12 read these two
        opponent: others.length ? (profiles[others[0]] ?? null) : null,
        peer: others.some((p) => this.here(p)),
      }),
    );
    if (meta.kind === "party") this.broadcast(meta, { t: "_players", players: roster, host: meta.host }, player);
    this.broadcast(meta, { t: "_peer", up: true, id: player }, player);
    this.broadcast(meta, { t: "_host", id: meta.host }, player);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  // MARK: sockets

  private sockets(player: string): WebSocket[] {
    return this.ctx.getWebSockets(player).filter((ws) => ws.readyState === WebSocket.OPEN);
  }

  private here(player: string): boolean {
    return this.sockets(player).length > 0;
  }

  private sendTo(player: string, msg: unknown) {
    const text = typeof msg === "string" ? msg : JSON.stringify(msg);
    for (const ws of this.sockets(player)) {
      try {
        ws.send(text);
      } catch {}
    }
  }

  private broadcast(meta: Meta, msg: unknown, except?: string) {
    const text = JSON.stringify(msg);
    for (const p of meta.players) if (p !== except) this.sendTo(p, text);
  }

  private playerOf(ws: WebSocket): string | null {
    return (ws.deserializeAttachment() as { player?: string } | null)?.player ?? null;
  }

  private roster(meta: Meta, profiles: Record<string, unknown>) {
    return meta.players.map((id) => ({ id, here: this.here(id), profile: profiles[id] ?? null }));
  }

  private async game(): Promise<Game> {
    return (await this.ctx.storage.get<Game>("game")) ?? { number: 0, started: false, recorded: false, reports: {} };
  }

  /** Players who dropped, and when. */
  private async away(): Promise<Record<string, number>> {
    return (await this.ctx.storage.get<Record<string, number>>("away")) ?? {};
  }

  private async setAway(away: Record<string, number>) {
    const since = Object.values(away);
    if (!since.length) {
      await this.ctx.storage.delete(["away", "due"]);
      await this.ctx.storage.deleteAlarm();
      return;
    }
    const due = Math.min(...since) + FORFEIT_MS;
    await this.ctx.storage.put({ away, due });
    await this.ctx.storage.setAlarm(due);
  }

  // MARK: messages

  async webSocketMessage(ws: WebSocket, msg: string | ArrayBuffer) {
    if (typeof msg !== "string") return;
    if (msg === "ping") {
      ws.send("pong");
      return;
    }
    const player = this.playerOf(ws);
    const meta = await this.ctx.storage.get<Meta>("meta");
    if (!player || !meta || !meta.players.includes(player)) return;
    let parsed: any;
    try {
      parsed = JSON.parse(msg);
    } catch {
      return;
    }
    const t: string = typeof parsed?.t === "string" ? parsed.t : "";
    if (!t || t.startsWith("_")) return; // server-only messages can't be forged by a client
    if (meta.kind !== "duo" && HOST_ONLY.has(t) && player !== meta.host) return;
    if (t === "report") {
      await this.report(meta, player, parsed.won);
      return;
    }
    if (t === "leave") {
      await this.leave(meta, player);
      try {
        ws.close(1000, "left");
      } catch {}
      return;
    }
    if (t === "score") {
      // the host's scoreboard: kept for players who (re)join, and shown to everybody
      await this.ctx.storage.put("score", parsed.players ?? null);
      this.broadcast(meta, { t: "_score", players: parsed.players ?? [] });
      return;
    }
    const g = await this.game();
    if (t === "start") {
      await this.ctx.storage.put("game", { number: g.number + 1, started: true, recorded: false, reports: {} });
      await this.ctx.storage.delete("score");
    } else if (t === "lobby") {
      // back to the lobby before a result: the game is called off without a rating change
      if (!g.recorded) await this.ctx.storage.put("game", { ...g, started: false });
    } else if (t === "finished" && meta.kind !== "duo") {
      await this.ctx.storage.put("game", { ...g, started: false, recorded: true });
    }
    this.broadcast(meta, { ...parsed, from: player }, player);
  }

  // MARK: ratings (duos)

  private async report(meta: Meta, player: string, won: unknown) {
    const g = await this.game();
    if (meta.kind !== "duo" || !g.started || g.recorded) return;
    g.reports[player] = won === true ? true : won === false ? false : null;
    const [a, b] = meta.players;
    const ra = g.reports[a];
    const rb = g.reports[b];
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
      this.broadcast(meta, { t: "_rating", counted: false });
      return;
    }
    await this.finish(meta, ra === null ? 0.5 : ra ? 1 : 0);
  }

  private async finish(meta: Meta, scoreA: 1 | 0.5 | 0) {
    const [a, b] = meta.players;
    const before = await this.env.DB.prepare("SELECT id, rating FROM players WHERE id IN (?, ?)")
      .bind(a, b)
      .all<{ id: string; rating: number }>();
    const after = await recordResult(this.env, a, b, scoreA);
    await this.env.DB.prepare("UPDATE rooms SET status = 'done' WHERE id = ?").bind(meta.room).run();
    for (const p of [a, b]) {
      const old = before.results.find((r) => r.id === p)?.rating ?? 0;
      if (after[p] !== undefined) this.sendTo(p, { t: "_rating", counted: true, rating: after[p], delta: after[p] - old });
    }
  }

  // MARK: leaving

  /** Someone closed the battle on purpose. */
  private async leave(meta: Meta, player: string) {
    const away = await this.away();
    delete away[player];
    await this.setAway(away);
    if (meta.kind === "duo") {
      this.broadcast(meta, { t: "_peer", up: false, id: player }, player);
      await this.forfeitDuo(meta, player);
      return;
    }
    if ((await this.game()).started) this.broadcast(meta, { t: "_forfeit", id: player }, player);
    await this.remove(meta, player);
  }

  /** Takes a player off the roster of a group or party. */
  private async remove(meta: Meta, player: string) {
    meta.players = meta.players.filter((p) => p !== player);
    if (meta.host === player) meta.host = meta.players.find((p) => this.here(p)) ?? null;
    if (!meta.players.length) {
      await this.env.DB.prepare("DELETE FROM parties WHERE room = ?").bind(meta.room).run();
      await this.ctx.storage.deleteAll();
      await this.ctx.storage.deleteAlarm();
      return;
    }
    await this.ctx.storage.put("meta", meta);
    const profiles = (await this.ctx.storage.get<Record<string, unknown>>("profiles")) ?? {};
    this.broadcast(meta, { t: "_players", players: this.roster(meta, profiles), host: meta.host });
    if (meta.host) this.broadcast(meta, { t: "_host", id: meta.host });
  }

  private async forfeitDuo(meta: Meta, loser: string) {
    const g = await this.game();
    if (!g.started || g.recorded) return;
    const winner = meta.players.find((p) => p !== loser)!;
    if (!this.here(winner)) return; // both gone: abandoned, no rating change
    g.recorded = true;
    g.started = false;
    await this.ctx.storage.put("game", g);
    this.sendTo(winner, { t: "_forfeit", id: loser });
    await this.finish(meta, winner === meta.players[0] ? 1 : 0);
  }

  async webSocketClose(ws: WebSocket, code: number) {
    try {
      ws.close(code === 1005 ? 1000 : code, "bye");
    } catch {}
    const player = this.playerOf(ws);
    const meta = await this.ctx.storage.get<Meta>("meta");
    if (!player || !meta || !meta.players.includes(player)) return; // unknown, or left on purpose
    if (this.here(player)) return; // replaced by a newer connection
    this.broadcast(meta, { t: "_peer", up: false, id: player }, player);
    if (meta.host === player) {
      const next = meta.players.find((p) => p !== player && this.here(p));
      if (next) {
        meta.host = next;
        await this.ctx.storage.put("meta", meta);
        this.broadcast(meta, { t: "_host", id: next });
      }
    }
    const g = await this.game();
    if (meta.kind === "party" || (g.started && !g.recorded)) {
      const away = await this.away();
      away[player] = now();
      await this.setAway(away);
    }
  }

  async webSocketError(ws: WebSocket) {
    await this.webSocketClose(ws, 1011);
  }

  /** Someone dropped and didn't come back in time. */
  async alarm() {
    const meta = await this.ctx.storage.get<Meta>("meta");
    const due = (await this.ctx.storage.get<number>("due")) ?? now();
    const away = await this.away();
    if (!meta) return;
    const gone = Object.keys(away).filter((p) => away[p] + FORFEIT_MS <= due && !this.here(p));
    for (const p of Object.keys(away)) if (gone.includes(p) || this.here(p)) delete away[p];
    await this.setAway(away);
    for (const p of gone) {
      if (meta.kind === "duo") {
        await this.forfeitDuo(meta, p);
      } else {
        if ((await this.game()).started) this.broadcast(meta, { t: "_forfeit", id: p }, p);
        await this.remove(meta, p);
      }
    }
  }
}
