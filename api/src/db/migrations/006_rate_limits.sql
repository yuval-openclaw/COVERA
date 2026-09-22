-- Rate limits that survive a restart and are shared by every API process.
--
-- The key is a SHA-256 of what is being limited (an IP, an email, an account),
-- so this table holds no readable personal data. Rows expire with their window
-- and are swept by the limiter itself.
CREATE TABLE rate_limits (
  key_hash TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  reset_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX rate_limits_reset_at_idx ON rate_limits(reset_at);
