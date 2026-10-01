-- Accounts that hold both a password and a Google or Apple identity were linked
-- by matching the address alone, before signInWithProvider (auth/link.ts). The
-- provider proved the address; the password never did, and may belong to
-- whoever registered that address first. Remove it and every session — the
-- owner signs back in with the provider and loses nothing.
DELETE FROM sessions
 WHERE user_id IN (SELECT id FROM users
                    WHERE password_hash IS NOT NULL AND (google_sub IS NOT NULL OR apple_sub IS NOT NULL));
UPDATE users SET password_hash = NULL
 WHERE password_hash IS NOT NULL AND (google_sub IS NOT NULL OR apple_sub IS NOT NULL);
