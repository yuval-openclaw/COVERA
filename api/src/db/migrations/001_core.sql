CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- Family members covered by the account holder's policies.
CREATE TABLE members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  date_of_birth DATE,
  relationship TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX members_user_id_idx ON members(user_id);

CREATE TYPE document_status AS ENUM ('uploaded', 'extracting', 'extracted', 'failed');

CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  storage_key TEXT NOT NULL,
  original_filename TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size BIGINT NOT NULL,
  -- Identifies re-uploads of an identical file without re-running extraction.
  sha256 TEXT NOT NULL,
  page_count INTEGER,
  status document_status NOT NULL DEFAULT 'uploaded',
  failure_reason TEXT,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX documents_user_id_idx ON documents(user_id);
CREATE UNIQUE INDEX documents_user_sha_idx ON documents(user_id, sha256);

-- Page text is retained verbatim because citation verification compares
-- quoted spans against it. Without this, a citation cannot be checked.
CREATE TABLE document_pages (
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  page INTEGER NOT NULL CHECK (page > 0),
  text TEXT NOT NULL,
  PRIMARY KEY (document_id, page)
);

CREATE TYPE policy_type AS ENUM (
  'private_health', 'supplementary_shaban', 'critical_illness', 'dental', 'travel', 'other'
);

-- policy_group_id links successive versions of the same underlying policy so a
-- renewal can be diffed against what it replaced. Superseded rows are retained.
CREATE TABLE policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  policy_group_id UUID NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  policy_type policy_type NOT NULL,
  extraction JSONB NOT NULL,
  effective_date DATE,
  renewal_date DATE,
  superseded_by UUID REFERENCES policies(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (policy_group_id, version)
);
CREATE INDEX policies_user_id_idx ON policies(user_id);
CREATE INDEX policies_extraction_idx ON policies USING gin (extraction jsonb_path_ops);
CREATE INDEX policies_active_idx ON policies(user_id) WHERE superseded_by IS NULL;

CREATE TABLE policy_members (
  policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  PRIMARY KEY (policy_id, member_id)
);

-- Retrieval unit for the guidance engine. Page is carried through so every
-- retrieved snippet can be cited without a second lookup.
CREATE TABLE document_chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  page INTEGER NOT NULL,
  chunk_index INTEGER NOT NULL,
  text TEXT NOT NULL,
  embedding vector(1024),
  UNIQUE (document_id, chunk_index)
);
CREATE INDEX document_chunks_user_id_idx ON document_chunks(user_id);
CREATE INDEX document_chunks_embedding_idx ON document_chunks
  USING hnsw (embedding vector_cosine_ops);

CREATE TYPE claim_status AS ENUM (
  'draft', 'submitted', 'awaiting_documents', 'approved', 'rejected', 'reimbursed'
);

CREATE TABLE claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_id UUID REFERENCES members(id) ON DELETE SET NULL,
  policy_id UUID REFERENCES policies(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  status claim_status NOT NULL DEFAULT 'draft',
  submitted_at TIMESTAMPTZ,
  -- Sourced from the policy's stated submission window, never assumed.
  deadline_at TIMESTAMPTZ,
  amount_claimed NUMERIC(12, 2),
  amount_reimbursed NUMERIC(12, 2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX claims_user_id_idx ON claims(user_id);

CREATE TABLE claim_documents (
  claim_id UUID NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  PRIMARY KEY (claim_id, document_id)
);
