import { env, runDurableObjectAlarm } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { weeklyReset } from "../src/index";
import { ratingWindow } from "../src/matchmaker";
import { elo, nicknameOk } from "../src/util";
import { call, register, socket } from "./helpers";

const JPEG = (n: number) => new Uint8Array([0xff, 0xd8, 0xff, 0xe0, n, 1, 2, 3]);

describe("rules", () => {
  it("nicknames", () => {
    expect(nicknameOk("小明")).toBe(true);
    expect(nicknameOk("Anna_99")).toBe(true);
    expect(nicknameOk("a")).toBe(false);
    expect(nicknameOk(" spaced")).toBe(false);
    expect(nicknameOk("visit www.x")).toBe(false);
    expect(nicknameOk("x".repeat(17))).toBe(false);
    expect(nicknameOk("<script>")).toBe(false);
  });
  it("elo and the rating window", () => {
    expect(elo(1000, 1000, 1)).toEqual([1016, 984]);
    expect(elo(1000, 1000, 0.5)).toEqual([1000, 1000]);
    expect(ratingWindow(0)).toBe(100);
    expect(ratingWindow(10_000)).toBe(250);
    expect(ratingWindow(30_000)).toBe(Infinity);
  });
});

describe("accounts", () => {
  it("register, auth, recovery code", async () => {
    const { token, profile } = await register("Anna");
    expect(profile.nickname).toBe("Anna");
    expect(profile.friendCode).toMatch(/^[A-Z2-9]{6}$/);
    expect(profile.rating).toBe(1000);
    // the token is the recovery code: it signs in on another phone
    const me = await call("GET", "/v1/me", token);
    expect(me.status).toBe(200);
    expect(me.data.profile.id).toBe(profile.id);
    expect((await call("GET", "/v1/me", profile.id + ".wrong")).status).toBe(401);
    expect((await call("GET", "/v1/me")).status).toBe(401);
  });

  it("rejects bad nicknames and too many sign-ups from one network", async () => {
    expect((await call("POST", "/v1/register", undefined, { nickname: "http://spam" })).status).toBe(400);
    const signUp = () =>
      call("POST", "/v1/register", undefined, { nickname: "same" }).then((r) => r.status);
    const codes = [];
    for (let i = 0; i < 6; i++) codes.push(await signUp());
    expect(codes.slice(0, 5).every((c) => c === 201)).toBe(true);
    expect(codes[5]).toBe(429);
  });

  it("stats sync: first sync doesn't count toward the week, later gains are capped", async () => {
    const { token } = await register("Syncer");
    let r = await call("PUT", "/v1/me", token, { xpTotal: 50_000, level: 3, streak: 12 });
    expect(r.data.profile.xpTotal).toBe(50_000);
    expect(r.data.profile.xpWeek).toBe(0);
    expect(r.data.profile.level).toBe(3);
    // pretend the last sync was a minute ago
    await env.DB.prepare("UPDATE players SET xp_synced_at = xp_synced_at - 60000").run();
    r = await call("PUT", "/v1/me", token, { xpTotal: 50_120 });
    expect(r.data.profile.xpWeek).toBe(120);
    await env.DB.prepare("UPDATE players SET xp_synced_at = xp_synced_at - 60000").run();
    r = await call("PUT", "/v1/me", token, { xpTotal: 999_999 });
    expect(r.data.profile.xpWeek).toBe(120 + 1500);
    // straight after: nothing more counts
    r = await call("PUT", "/v1/me", token, { xpTotal: 1_000_500 });
    expect(r.data.profile.xpWeek).toBe(1620);
  });

  it("delete profile", async () => {
    const { token } = await register("Gone");
    expect((await call("DELETE", "/v1/me", token)).status).toBe(200);
    expect((await call("GET", "/v1/me", token)).status).toBe(401);
  });
});

describe("daily slot machine", () => {
  it("one spin per 24 hours on the server's clock", async () => {
    const { token } = await register("Spinner");
    const spin = async (count = 0) => (await call("POST", "/v1/spin", token, { count })).data;
    const first = await spin();
    expect(first).toMatchObject({ allowed: true, spins: 1 });
    expect(first.wait).toBe(24 * 3_600_000);
    const again = await spin(1);
    expect(again.allowed).toBe(false);
    expect(again.spins).toBe(1);
    expect(again.wait).toBeGreaterThan(23 * 3_600_000);
    // 23 hours later: still not
    await env.DB.prepare("UPDATE players SET last_spin = last_spin - ?").bind(23 * 3_600_000).run();
    expect((await spin(1)).allowed).toBe(false);
    await env.DB.prepare("UPDATE players SET last_spin = last_spin - ?").bind(3_600_000).run();
    expect(await spin(4)).toMatchObject({ allowed: true, spins: 5 });
    // two requests at the same moment: only one counts
    await env.DB.prepare("UPDATE players SET last_spin = 0").run();
    const both = await Promise.all([spin(5), spin(5)]);
    expect(both.filter((r) => r.allowed)).toHaveLength(1);
    expect((await call("POST", "/v1/spin", undefined, {})).status).toBe(401);
  });
});

describe("profile pictures", () => {
  it("a new picture replaces the old one, which is deleted", async () => {
    const { token, profile } = await register("Pic");
    const first = await call("PUT", "/v1/me/avatar", token, JPEG(1));
    expect(first.data.avatar).toBe(`/v1/avatars/${profile.id}/1`);
    const got = await call("GET", first.data.avatar);
    expect(got.status).toBe(200);
    expect(got.res.headers.get("content-type")).toBe("image/jpeg");
    expect(new Uint8Array(await got.res.arrayBuffer())[4]).toBe(1);

    const second = await call("PUT", "/v1/me/avatar", token, JPEG(2));
    expect(second.data.avatar).toBe(`/v1/avatars/${profile.id}/2`);
    expect((await call("GET", first.data.avatar)).status).toBe(404);
    const rows = await env.DB.prepare("SELECT COUNT(*) AS n FROM avatars WHERE player_id = ?").bind(profile.id).first<any>();
    expect(rows.n).toBe(1);

    expect((await call("DELETE", "/v1/me/avatar", token)).status).toBe(200);
    expect((await call("GET", second.data.avatar)).status).toBe(404);
    expect((await call("GET", "/v1/me", token)).data.profile.avatar).toBeNull();
  });

  it("only small JPEG/PNG files", async () => {
    const { token } = await register("Pic2");
    expect((await call("PUT", "/v1/me/avatar", token, new Uint8Array([1, 2, 3]))).status).toBe(415);
    const big = new Uint8Array(201 * 1024);
    big.set([0xff, 0xd8, 0xff]);
    expect((await call("PUT", "/v1/me/avatar", token, big)).status).toBe(413);
  });

  it("three reports hide the picture and reset the nickname", async () => {
    const bad = await register("Rude");
    await call("PUT", "/v1/me/avatar", bad.token, JPEG(9));
    for (const name of ["R1", "R2", "R3"]) {
      const r = await register(name);
      expect((await call("POST", `/v1/report/${bad.profile.id}`, r.token)).status).toBe(200);
    }
    const p = (await call("GET", "/v1/me", bad.token)).data.profile;
    expect(p.avatar).toBeNull();
    expect(p.nickname).toBe("player");
  });
});

describe("friends, challenges, leaderboards", () => {
  it("request → accept → challenge → decline", async () => {
    const a = await register("Alice");
    const b = await register("Bob");
    let r = await call("POST", "/v1/friends", a.token, { code: b.profile.friendCode.toLowerCase() });
    expect(r.data.status).toBe("requested");
    let fb = (await call("GET", "/v1/friends", b.token)).data;
    expect(fb.incoming.map((p: any) => p.id)).toEqual([a.profile.id]);
    expect((await call("GET", "/v1/inbox", b.token)).data.requests).toBe(1);
    // can't challenge before they accept
    expect((await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "Duel" })).status).toBe(403);
    expect((await call("POST", `/v1/friends/${a.profile.id}/accept`, b.token)).status).toBe(200);
    fb = (await call("GET", "/v1/friends", b.token)).data;
    expect(fb.friends.map((p: any) => p.id)).toEqual([a.profile.id]);
    expect(fb.friends[0].online).toBe(true);

    r = await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "Survival" });
    expect(r.status).toBe(201);
    const inbox = (await call("GET", "/v1/inbox", b.token)).data;
    expect(inbox.challenges).toHaveLength(1);
    expect(inbox.challenges[0]).toMatchObject({ room: r.data.room, mode: "Survival" });
    expect(inbox.challenges[0].from.id).toBe(a.profile.id);
    await call("POST", `/v1/challenge/${r.data.room}/decline`, b.token);
    expect((await call("GET", "/v1/inbox", b.token)).data.challenges).toHaveLength(0);
  });

  it("adding someone who already asked you makes you friends", async () => {
    const a = await register("Cara");
    const b = await register("Dan");
    await call("POST", "/v1/friends", a.token, { code: b.profile.friendCode });
    const r = await call("POST", "/v1/friends", b.token, { code: a.profile.friendCode });
    expect(r.data.status).toBe("friends");
  });

  it("weekly and rating boards, global and friends; Monday reset", async () => {
    const a = await register("Top");
    const b = await register("Mid");
    await call("PUT", "/v1/me", a.token, { xpTotal: 0 });
    await call("PUT", "/v1/me", b.token, { xpTotal: 0 });
    await env.DB.prepare("UPDATE players SET xp_synced_at = 1").run();
    await call("PUT", "/v1/me", a.token, { xpTotal: 900 });
    await call("PUT", "/v1/me", b.token, { xpTotal: 300 });
    const board = (await call("GET", "/v1/leaderboard?board=week", b.token)).data;
    const ids = board.top.map((e: any) => e.profile.id);
    expect(ids.indexOf(a.profile.id)).toBeLessThan(ids.indexOf(b.profile.id));
    expect(board.me.rank).toBe(ids.indexOf(b.profile.id) + 1);

    const friends = (await call("GET", "/v1/leaderboard?board=week&scope=friends", b.token)).data;
    expect(friends.top.map((e: any) => e.profile.id)).toEqual([b.profile.id]);

    await weeklyReset(env as any);
    const after = (await call("GET", "/v1/me", a.token)).data.profile;
    expect(after.xpWeek).toBe(0);
    expect(after.xpTotal).toBe(900);
  });
});

describe("invitations", () => {
  it("joining answers it, leaving takes it back, old ones expire", async () => {
    expect((await call("GET", "/")).data.v).toBe(2);
    const [a, b] = [await register("Inviter"), await register("Invited")];
    await call("POST", "/v1/friends", a.token, { code: b.profile.friendCode });
    await call("POST", "/v1/friends", b.token, { code: a.profile.friendCode });
    const inbox = async () => (await call("GET", "/v1/inbox", b.token)).data.challenges;
    const invite = async () => (await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "PinyinType" })).data.room;

    // both end up in the room and see each other
    const room = await invite();
    expect(await inbox()).toHaveLength(1);
    const host = await socket(`/v1/rooms/${room}`, a.token);
    const first: any = await host.next((m: any) => m.t === "_room");
    expect(first.host).toBe(a.profile.id);
    expect(await inbox(), "the host being there doesn't answer it").toHaveLength(1);
    const guest = await socket(`/v1/rooms/${room}`, b.token);
    const second: any = await guest.next((m: any) => m.t === "_room");
    expect(second.players.filter((p: any) => p.here)).toHaveLength(2);
    expect(await host.next((m: any) => m.t === "_peer" && m.up)).toMatchObject({ id: b.profile.id });
    expect(await inbox()).toHaveLength(0);
    host.ws.close();
    guest.ws.close();

    // the host gave up waiting
    const second_room = await invite();
    await call("POST", `/v1/challenge/${second_room}/decline`, a.token);
    expect(await inbox()).toHaveLength(0);

    await invite();
    await env.DB.prepare("UPDATE rooms SET created = created - ?").bind(29 * 60_000).run();
    expect(await inbox(), "still there after 29 minutes").toHaveLength(1);
    await env.DB.prepare("UPDATE rooms SET created = created - ?").bind(2 * 60_000).run();
    expect(await inbox()).toHaveLength(0);
  });
});

describe("live play", () => {
  it("quick match pairs two players and the room relays the battle; agreeing reports change ratings", async () => {
    const a = await register("Quick1");
    const b = await register("Quick2");
    const qa = await socket("/v1/queue?mode=Blitz", a.token);
    await qa.next((m) => m.t === "queued");
    const qb = await socket("/v1/queue?mode=Blitz", b.token);
    const ma = await qa.next((m) => m.t === "matched");
    const mb = await qb.next((m) => m.t === "matched");
    expect(ma.room).toBe(mb.room);
    expect(ma.opponent.id).toBe(b.profile.id);
    expect(mb.opponent.id).toBe(a.profile.id);

    const ra = await socket(`/v1/rooms/${ma.room}`, a.token);
    const hello = await ra.next((m) => m.t === "_room");
    expect(hello.peer).toBe(false);
    expect(hello.opponent.id).toBe(b.profile.id);
    const rb = await socket(`/v1/rooms/${ma.room}`, b.token);
    expect((await rb.next((m) => m.t === "_room")).peer).toBe(true);
    await ra.next((m) => m.t === "_peer" && m.up === true);

    // the battle protocol passes through untouched
    ra.send({ t: "start", mode: "Blitz", q: [{ w: "1-你好", k: 0, o: ["1-你好", "1-好"] }] });
    expect((await rb.next((m) => m.t === "start")).q[0].w).toBe("1-你好");
    rb.send({ t: "progress", s: 3, done: true });
    expect((await ra.next((m) => m.t === "progress")).s).toBe(3);
    // clients can't fake server messages
    rb.send({ t: "_rating", counted: true, rating: 9999 });

    ra.send({ t: "report", won: true });
    rb.send({ t: "report", won: false });
    const resA = await ra.next((m) => m.t === "_rating");
    const resB = await rb.next((m) => m.t === "_rating");
    expect(resA).toMatchObject({ counted: true, rating: 1016, delta: 16 });
    expect(resB).toMatchObject({ counted: true, rating: 984, delta: -16 });
    expect((await call("GET", "/v1/me", a.token)).data.profile.wins).toBe(1);
    expect((await call("GET", "/v1/me", b.token)).data.profile.losses).toBe(1);
  });

  it("different modes or swear settings don't match", async () => {
    const a = await register("Mode1");
    const b = await register("Mode2");
    const c = await register("Mode3");
    const qa = await socket("/v1/queue?mode=Duel", a.token);
    const qb = await socket("/v1/queue?mode=Listen", b.token);
    const qc = await socket("/v1/queue?mode=Duel&swears=1", c.token);
    await new Promise((r) => setTimeout(r, 300));
    for (const q of [qa, qb, qc]) expect(q.inbox.some((m) => m.t === "matched")).toBe(false);
  });

  it("disagreeing reports don't count; a player who drops mid-game forfeits", async () => {
    const a = await register("Drop1");
    const b = await register("Drop2");
    await call("POST", "/v1/friends", a.token, { code: b.profile.friendCode });
    await call("POST", `/v1/friends/${a.profile.id}/accept`, b.token);
    const { room } = (await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "Duel" })).data;
    const ra = await socket(`/v1/rooms/${room}`, a.token);
    const rb = await socket(`/v1/rooms/${room}`, b.token);
    await ra.next((m) => m.t === "_peer");

    // game 1: both claim the win
    ra.send({ t: "start", mode: "Duel", q: [] });
    await rb.next((m) => m.t === "start");
    ra.send({ t: "report", won: true });
    rb.send({ t: "report", won: true });
    expect((await ra.next((m) => m.t === "_rating")).counted).toBe(false);
    expect((await call("GET", "/v1/me", a.token)).data.profile.rating).toBe(1000);

    // game 2 (rematch): b drops and never comes back
    ra.send({ t: "start", mode: "Duel", q: [] });
    await rb.next((m) => m.t === "start");
    rb.ws.close(1000, "bye");
    await ra.next((m) => m.t === "_peer" && m.up === false);
    const stub = env.ROOMS.get(env.ROOMS.idFromName(room));
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    await ra.next((m) => m.t === "_forfeit");
    expect((await ra.next((m) => m.t === "_rating")).delta).toBe(16);
    expect((await call("GET", "/v1/me", b.token)).data.profile.losses).toBe(1);
  });

  it("only the two players can join a room", async () => {
    const a = await register("Own1");
    const b = await register("Own2");
    const x = await register("Intruder");
    await call("POST", "/v1/friends", a.token, { code: b.profile.friendCode });
    await call("POST", `/v1/friends/${a.profile.id}/accept`, b.token);
    const { room } = (await call("POST", "/v1/challenge", a.token, { friendId: b.profile.id, mode: "Duel" })).data;
    await expect(socket(`/v1/rooms/${room}`, x.token)).rejects.toThrow(/404/);
  });
});
