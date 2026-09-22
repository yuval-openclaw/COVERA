-- Whether a page's text came from transcription rather than an embedded text
-- layer. Citations on transcribed pages are checked against our own reading of
-- the scan, which is a weaker guarantee, and the interface must be able to say so.
ALTER TABLE document_pages ADD COLUMN ocr BOOLEAN NOT NULL DEFAULT false;

-- Deduplication only ever matched successfully extracted documents, but the
-- constraint applied to every row. A transient failure therefore made the file
-- permanently unuploadable — worst at exactly the moment a user is retrying
-- under pressure. Uniqueness now covers only documents that actually succeeded.
DROP INDEX documents_user_sha_idx;
CREATE UNIQUE INDEX documents_user_sha_extracted_idx
  ON documents(user_id, sha256)
  WHERE status = 'extracted';
