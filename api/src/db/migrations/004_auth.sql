-- Real sign-in replaces the development identity header.
--
-- Passwords are stored only as scrypt hashes, and sessions only as SHA-256
-- hashes of their tokens: a leaked copy of this database cannot be replayed as
-- live logins, and it reveals no password.

ALTER TABLE users ADD COLUMN password_hash TEXT;
ALTER TABLE users ADD COLUMN google_sub TEXT UNIQUE;

CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX sessions_user_idx ON sessions(user_id);
