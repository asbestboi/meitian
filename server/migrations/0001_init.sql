-- Online profiles. The secret is only stored as a SHA-256 hash.
CREATE TABLE players (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  nickname TEXT NOT NULL,
  tag TEXT NOT NULL,
  friend_code TEXT NOT NULL UNIQUE,
  level INTEGER NOT NULL DEFAULT 0,
  streak INTEGER NOT NULL DEFAULT 0,
  xp_total INTEGER NOT NULL DEFAULT 0,
  xp_week INTEGER NOT NULL DEFAULT 0,
  rating INTEGER NOT NULL DEFAULT 1000,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  cosmetics TEXT NOT NULL DEFAULT '{}',
  avatar_version INTEGER NOT NULL DEFAULT 0,
  -- 0 until the first stats sync (existing progress doesn't count toward this week)
  xp_synced_at INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);
CREATE INDEX players_week ON players(xp_week DESC);
CREATE INDEX players_rating ON players(rating DESC);

-- One profile picture per player: uploading a new one replaces (deletes) the old one.
CREATE TABLE avatars (
  player_id TEXT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  bytes BLOB NOT NULL
);

-- Friendships go both ways once accepted; a pending request is a single row with accepted = 0.
CREATE TABLE friends (
  a TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  b TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  accepted INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL,
  PRIMARY KEY (a, b)
);
CREATE INDEX friends_b ON friends(b);

-- Battle rooms (quick matches and friend challenges).
CREATE TABLE rooms (
  id TEXT PRIMARY KEY,
  a TEXT NOT NULL,
  b TEXT NOT NULL,
  mode TEXT NOT NULL,
  challenge INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open',   -- open | declined | done
  created INTEGER NOT NULL
);
CREATE INDEX rooms_b ON rooms(b, status);

CREATE TABLE reports (
  target TEXT NOT NULL,
  reporter TEXT NOT NULL,
  created INTEGER NOT NULL,
  PRIMARY KEY (target, reporter)
);

CREATE TABLE register_log (ip TEXT NOT NULL, at INTEGER NOT NULL);
CREATE INDEX register_log_ip ON register_log(ip, at);
