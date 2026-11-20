import { Env, elo } from "./util";

/** Writes a finished game: Elo for both, a win/loss each (nothing for a draw). Returns the new ratings. */
export async function recordResult(env: Env, a: string, b: string, scoreA: 1 | 0.5 | 0): Promise<Record<string, number>> {
  const rows = await env.DB.prepare("SELECT id, rating FROM players WHERE id IN (?, ?)")
    .bind(a, b)
    .all<{ id: string; rating: number }>();
  const ra = rows.results.find((r) => r.id === a)?.rating;
  const rb = rows.results.find((r) => r.id === b)?.rating;
  if (ra === undefined || rb === undefined) return {}; // someone deleted their profile mid-game
  const [na, nb] = elo(ra, rb, scoreA);
  const winA = scoreA === 1 ? 1 : 0;
  const winB = scoreA === 0 ? 1 : 0;
  await env.DB.batch([
    env.DB.prepare("UPDATE players SET rating = ?, wins = wins + ?, losses = losses + ? WHERE id = ?").bind(na, winA, winB, a),
    env.DB.prepare("UPDATE players SET rating = ?, wins = wins + ?, losses = losses + ? WHERE id = ?").bind(nb, winB, winA, b),
  ]);
  return { [a]: na, [b]: nb };
}
