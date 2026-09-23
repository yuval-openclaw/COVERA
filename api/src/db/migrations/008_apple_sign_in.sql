-- Sign in with Apple. Apple's `sub` is the stable identity, like google_sub in
-- migration 004: the address can change, or be a private relay that Apple can
-- rotate, so the subject is what an account is matched on.
ALTER TABLE users ADD COLUMN apple_sub TEXT UNIQUE;
