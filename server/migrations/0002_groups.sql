-- Group play: rooms with more than two players, and private parties joined by code.
ALTER TABLE rooms ADD COLUMN players TEXT;  -- JSON array of player ids (NULL: just a and b)
ALTER TABLE rooms ADD COLUMN party TEXT;    -- party code, when this row is an invitation to a party

CREATE TABLE parties (
  code TEXT PRIMARY KEY,
  room TEXT NOT NULL,
  host TEXT NOT NULL,
  swears INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL
);
CREATE INDEX parties_host ON parties(host);
