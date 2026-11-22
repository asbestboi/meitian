export interface Env {
  DB: D1Database;
  MATCHMAKER: DurableObjectNamespace;
  ROOMS: DurableObjectNamespace;
}

/** Same names as the battle modes in the Rust core (core/src/battle.rs). */
export const MODES = [
  "Duel",
  "Blitz",
  "Listen",
  "Sudden",
  "Survival",
  "ToneClash",
  "SentenceBuilder",
  "PinyinType",
  "BattleRoyale",
  "Team2v2",
] as const;
export type Mode = (typeof MODES)[number];

/** Most players in a room. */
export const MAX_PLAYERS = 4;

/** Fewest players a mode needs. */
export function minPlayers(mode: string): number {
  return mode === "Team2v2" ? 4 : mode === "BattleRoyale" ? 3 : 2;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

export function now(): number {
  return Date.now();
}

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I

export function randomCode(len: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(len));
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
}

export function randomId(): string {
  return crypto.randomUUID();
}

export function randomSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Nicknames: 2–16 characters of letters (any script, so 小明 works), digits, space, _ - .
 * No links. Kept identical to `nickname_ok` in the Rust core.
 */
export function nicknameOk(name: string): boolean {
  const n = name.trim();
  const chars = [...n];
  if (chars.length < 2 || chars.length > 16 || n !== name) return false;
  if (!/^[\p{L}\p{N} _.\-]+$/u.test(n)) return false;
  const lower = n.toLowerCase();
  return !["http", "www", ".com", ".net", ".org", ".cn"].some((bad) => lower.includes(bad));
}

export function clampInt(v: unknown, min: number, max: number): number | null {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  return Math.max(min, Math.min(max, Math.round(v)));
}

/** Elo with K = 32. Returns the new ratings for a (score 1 = a won, 0.5 = draw, 0 = b won). */
export function elo(ra: number, rb: number, scoreA: number): [number, number] {
  const ea = 1 / (1 + 10 ** ((rb - ra) / 400));
  const delta = Math.round(32 * (scoreA - ea));
  return [ra + delta, rb - delta];
}
