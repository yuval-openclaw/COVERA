-- Embeddings move from Voyage voyage-3 (1024 dims) to Gemini
-- gemini-embedding-001 at 768 dims. Vectors from different models are not
-- comparable, so existing ones are cleared rather than kept alongside new ones;
-- at the time of this migration no embeddings had ever been stored.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT indexname FROM pg_indexes
           WHERE tablename = 'document_chunks' AND indexdef ILIKE '%hnsw%'
  LOOP
    EXECUTE format('DROP INDEX %I', r.indexname);
  END LOOP;
END $$;

ALTER TABLE document_chunks ALTER COLUMN embedding TYPE vector(768) USING NULL;

CREATE INDEX document_chunks_embedding_idx
  ON document_chunks USING hnsw (embedding vector_cosine_ops);
