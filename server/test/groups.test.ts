import { env, runDurableObjectAlarm } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { groupSize, GROUP_WAIT_MS } from "../src/matchmaker";
import { minPlayers, MODES } from "../src/util";
import { call, register, socket } from "./helpers";

type Player = Awaited<ReturnType<typeof register>>;
const friends = async (a: Player, b: Player) => {
  await call("POST", "/v1/friends", a.token, { code: b.profile.friendCode });
  await call("POST", `/v1/friends/${a.profile.id}/accept`, b.token);
};
const newParty = async (host: Player) => (await call("POST", "/v1/party", host.token, {})).data.code as string;
const join = async (code: string, p: Player) => {
  const ws = await socket(`/v1/party/${code}`, p.token);
  return { ws, room: await ws.next((m) => m.t === "_room") };
};
const ids = (m: any) => m.players.map((p: any) => p.id);
const roomOf = async (code: string) =>
  (await env.DB.prepare("SELECT room FROM parties WHERE code = ?").bind(code).first<{ room: string }>())!.room;

describe("group rules", () => {
  it("modes and their smallest group", () => {
    for (const m of ["ToneClash", "SentenceBuilder", "PinyinType", "BattleRoyale", "Team2v2"]) expect(MODES).toContain(m);
    expect(minPlayers("Duel")).toBe(2);
    expect(minPlayers("BattleRoyale")).toBe(3);
    expect(minPlayers("Team2v2")).toBe(4);
  });

  it("a group starts with four, or with three after twenty seconds", () => {
    expect(groupSize("Duel", 4, 0)).toBe(4);
    expect(groupSize("Duel", 3, GROUP_WAIT_MS - 1)).toBe(0);
    expect(groupSize("Duel", 3, GROUP_WAIT_MS)).toBe(3);
    expect(groupSize("Duel", 2, 10 * GROUP_WAIT_MS)).toBe(0);
    expect(groupSize("Team2v2", 3, 10 * GROUP_WAIT_MS)).toBe(0);
    expect(groupSize("Duel", 7, 0)).toBe(4);
  });
});

describe("public groups", () => {
  it("four players in the queue get one room; everything is relayed with its sender", async () => {
    const players = await Promise.all(["G1", "G2", "G3", "G4"].map(register));
    const queue = [];
    for (const p of players) queue.push(await socket("/v1/queue?mode=BattleRoyale&size=4&v=2", p.token));
    const matched = await Promise.all(queue.map((q) => q.next((m) => m.t === "matched")));
    expect(new Set(matched.map((m) => m.room)).size).toBe(1);
    expect(matched[0].players).toHaveLength(3);
    expect(await queue[0].next((m) => m.t === "waiting" && m.count >= 2)).toBeTruthy();

    const socks = [];
    for (const p of players) socks.push(await socket(`/v1/rooms/${matched[0].room}`, p.token));
    const rooms = await Promise.all(socks.map((s) => s.next((m) => m.t === "_room")));
    expect(rooms[3].kind).toBe("group");
    expect(rooms[3].you).toBe(players[3].profile.id);
    expect(rooms[3].host).toBe(players[0].profile.id);
    expect(ids(rooms[3])).toEqual(players.map((p) => p.profile.id));
    expect(rooms[3].players.every((p: any) => p.here)).toBe(true);
    expect(rooms[0].players[0].profile.nickname).toBe("G1");
    expect((await socks[0].next((m) => m.t === "_peer" && m.id === players[3].profile.id)).up).toBe(true);

    socks[0].send({ t: "start", mode: "BattleRoyale", q: [] });
    for (const s of socks.slice(1)) expect((await s.next((m) => m.t === "start")).from).toBe(players[0].profile.id);
    socks[2].send({ t: "answer", i: 0, ok: true, ms: 800, from: "someone else" });
    for (const i of [0, 1, 3]) expect((await socks[i].next((m) => m.t === "answer")).from).toBe(players[2].profile.id);

    // the host's scoreboard goes to everybody, and to players who come back
    const score = [{ id: players[0].profile.id, score: 3, hp: 100, out: false }];
    socks[0].send({ t: "score", players: score });
    for (const s of socks) expect((await s.next((m) => m.t === "_score")).players).toEqual(score);
    const again = await socket(`/v1/rooms/${matched[0].room}`, players[3].token);
    expect((await again.next((m) => m.t === "_room")).score).toEqual(score);

    // only the host referees, and nobody fakes the server
    socks[1].send({ t: "result", i: 0, w: "me" });
    socks[1].send({ t: "_forfeit", id: players[0].profile.id });
    socks[1].send({ t: "progress", s: 1, done: false });
    await socks[0].next((m) => m.t === "progress");
    expect(socks[0].inbox.some((m) => m.t === "result" || m.t === "_forfeit")).toBe(false);

    // unrated
    for (const s of socks.slice(0, 3)) s.send({ t: "report", won: true });
    socks[0].send({ t: "finished", places: [] });
    await socks[1].next((m) => m.t === "finished");
    expect((await call("GET", "/v1/me", players[0].token)).data.profile).toMatchObject({ rating: 1000, wins: 0 });
  });

  it("three players don't start at once; groups and 1v1 don't mix; old apps only meet old apps", async () => {
    const players = await Promise.all(["W1", "W2", "W3", "W4"].map(register));
    const group = [];
    for (const p of players.slice(0, 3)) group.push(await socket("/v1/queue?mode=Blitz&size=4&v=2", p.token));
    const duo = await socket("/v1/queue?mode=Blitz&v=2", players[3].token);
    const old = await register("OldApp");
    const oldDuo = await socket("/v1/queue?mode=Blitz", old.token);
    await new Promise((r) => setTimeout(r, 300));
    for (const q of [...group, duo, oldDuo]) expect(q.inbox.some((m) => m.t === "matched")).toBe(false);
    for (const q of [...group, duo, oldDuo]) q.ws.close(1000, "bye");
  });

  it("group modes are refused in 1v1", async () => {
    const a = await register("Solo1");
    const b = await register("Solo2");
    await friends(a, b);
    await expect(socket("/v1/queue?mode=Team2v2", a.token)).rejects.toThrow(/400/);
    await expect(socket("/v1/queue?mode=Nope&size=4", a.token)).rejects.toThrow(/400/);
    expect((await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "BattleRoyale" })).status).toBe(400);
    expect((await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "ToneClash" })).status).toBe(201);
  });
});

describe("parties", () => {
  it("code, lobby, full party, start locks the door", async () => {
    const [a, b, c, d, e] = await Promise.all(["PA", "PB", "PC", "PD", "PE"].map(register));
    const code = await newParty(a);
    expect(code).toMatch(/^[A-Z2-9]{6}$/);
    const A = await join(code, a);
    expect(A.room).toMatchObject({ kind: "party", host: a.profile.id, you: a.profile.id });
    const B = await join(code.toLowerCase(), b);
    expect(ids(B.room)).toEqual([a.profile.id, b.profile.id]);
    const roster = await A.ws.next((m) => m.t === "_players" && m.players.length === 2);
    expect(roster.players[1].profile.nickname).toBe("PB");
    await expect(socket("/v1/party/ZZZZZZ", c.token)).rejects.toThrow(/404/);
    await expect(socket(`/v1/party/${code}?swears=1`, c.token)).rejects.toThrow(/412/);

    const C = await join(code, c);
    // started: nobody new gets in, members can come back
    A.ws.send({ t: "start", mode: "Duel", q: [] });
    await B.ws.next((m) => m.t === "start");
    await expect(socket(`/v1/party/${code}`, d.token)).rejects.toThrow(/409/);
    const back = await join(code, c);
    expect(back.room.players).toHaveLength(3);
    A.ws.send({ t: "finished", places: [] });
    await B.ws.next((m) => m.t === "finished");
    const D = await join(code, d);
    expect(D.room.players).toHaveLength(4);
    await expect(socket(`/v1/party/${code}`, e.token)).rejects.toThrow(/409/);
    // a party room can't be entered as a normal room
    await expect(socket(`/v1/rooms/${await roomOf(code)}`, a.token)).rejects.toThrow(/404/);
  });

  it("invitations land in a friend's inbox", async () => {
    const a = await register("InvA");
    const b = await register("InvB");
    const x = await register("InvX");
    const code = await newParty(a);
    expect((await call("POST", `/v1/party/${code}/invite`, a.token, { friendId: b.profile.id })).status).toBe(403);
    await friends(a, b);
    await call("POST", `/v1/party/${code}/invite`, a.token, { friendId: b.profile.id });
    expect((await call("POST", `/v1/party/${code}/invite`, a.token, { friendId: b.profile.id })).status).toBe(201);
    const inbox = (await call("GET", "/v1/inbox", b.token)).data;
    expect(inbox.challenges).toHaveLength(1);
    expect(inbox.challenges[0]).toMatchObject({ mode: "Party", party: code });
    expect((await call("GET", "/v1/inbox", x.token)).data.challenges).toHaveLength(0);
    await join(code, a);
    await join(code, b);
    expect((await call("GET", "/v1/inbox", b.token)).data.challenges, "joining answers the invitation").toHaveLength(0);
  });

  it("the host leaving hands the party to the next player; the last one out closes it", async () => {
    const [a, b, c] = await Promise.all(["HA", "HB", "HC"].map(register));
    const code = await newParty(a);
    const A = await join(code, a);
    const B = await join(code, b);
    const C = await join(code, c);
    A.ws.send({ t: "leave" });
    expect((await B.ws.next((m) => m.t === "_players" && m.players.length === 2)).host).toBe(b.profile.id);
    expect((await C.ws.next((m) => m.t === "_host" && m.id === b.profile.id)).id).toBe(b.profile.id);
    // the new host can start
    B.ws.send({ t: "start", mode: "Blitz", q: [] });
    expect((await C.ws.next((m) => m.t === "start")).from).toBe(b.profile.id);
    // leaving mid-game is a forfeit for that player only
    C.ws.send({ t: "leave" });
    expect((await B.ws.next((m) => m.t === "_forfeit")).id).toBe(c.profile.id);
    B.ws.send({ t: "leave" });
    await B.ws.next((m) => m.t === "never", 300).catch(() => {});
    await expect(socket(`/v1/party/${code}`, a.token)).rejects.toThrow(/404/);
  });

  it("a host who drops mid-game: the next player hosts at once, and the drop is a forfeit after 30 s", async () => {
    const [a, b, c] = await Promise.all(["DA", "DB", "DC"].map(register));
    const code = await newParty(a);
    const A = await join(code, a);
    const B = await join(code, b);
    const C = await join(code, c);
    A.ws.send({ t: "start", mode: "Duel", q: [] });
    await C.ws.next((m) => m.t === "start");
    A.ws.ws.close(1000, "lost signal");
    expect(await C.ws.next((m) => m.t === "_peer" && m.up === false)).toMatchObject({ id: a.profile.id });
    await C.ws.next((m) => m.t === "_host" && m.id === b.profile.id);
    // back in time: still in the game, but no longer the host
    const back = await join(code, a);
    expect(back.room.host).toBe(b.profile.id);
    back.ws.ws.close(1000, "lost again");
    await C.ws.next((m) => m.t === "_peer" && m.up === false);
    const stub = env.ROOMS.get(env.ROOMS.idFromName(await roomOf(code)));
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    expect((await B.ws.next((m) => m.t === "_forfeit")).id).toBe(a.profile.id);
    expect((await B.ws.next((m) => m.t === "_players" && m.players.length === 2)).host).toBe(b.profile.id);
  });

  it("leaving a 1v1 on purpose loses it right away", async () => {
    const a = await register("QuitA");
    const b = await register("QuitB");
    await friends(a, b);
    const { room } = (await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "Duel" })).data;
    const ra = await socket(`/v1/rooms/${room}`, a.token);
    const rb = await socket(`/v1/rooms/${room}`, b.token);
    await ra.next((m) => m.t === "_peer");
    ra.send({ t: "start", mode: "Duel", q: [] });
    await rb.next((m) => m.t === "start");
    rb.send({ t: "leave" });
    expect((await ra.next((m) => m.t === "_forfeit")).id).toBe(b.profile.id);
    expect((await ra.next((m) => m.t === "_rating")).delta).toBe(16);
  });
});
