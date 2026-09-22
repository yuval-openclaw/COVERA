-- Proof of consent to processing health information.
--
-- GDPR Art. 7(1) requires a controller to be able to demonstrate consent, and
-- Washington's My Health My Data Act requires consent before collecting
-- consumer health data. The app asks before the first upload; this records
-- when each account agreed and to which version of the terms, so a later
-- dispute is settled by a row rather than by recollection.
ALTER TABLE users
  ADD COLUMN health_consent_at TIMESTAMPTZ,
  ADD COLUMN health_consent_version TEXT;
