-- Proof that the user accepted the Terms of Use and acknowledged that Covera is
-- not medical, legal or insurance advice. Recorded separately from consent to
-- health-data processing (migration 005): the GDPR does not allow consent to
-- processing to be bundled into acceptance of terms, so each is its own act
-- with its own timestamp. The version is the date of the documents agreed to.
ALTER TABLE users
  ADD COLUMN terms_accepted_at TIMESTAMPTZ,
  ADD COLUMN terms_version TEXT,
  ADD COLUMN not_advice_acknowledged_at TIMESTAMPTZ;
