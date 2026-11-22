-- The daily slot machine: when a player last spun (the server's clock decides) and how often.
ALTER TABLE players ADD COLUMN last_spin INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN spins INTEGER NOT NULL DEFAULT 0;
