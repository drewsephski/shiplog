CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), github_id text UNIQUE NOT NULL, login text NOT NULL,
  time_zone text NOT NULL, finalize_minute int NOT NULL DEFAULT 1200 CHECK(finalize_minute BETWEEN 0 AND 1439),
  access_token text NOT NULL, refresh_token text, token_expires_at timestamptz,
  include_patches boolean NOT NULL DEFAULT false, token_refresh_until timestamptz, disconnected_at timestamptz, finalized_day date, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS connect_attempts (
  state_hash text PRIMARY KEY, challenge text NOT NULL, time_zone text NOT NULL, csrf_hash text,
  access_token text, refresh_token text, token_expires_at timestamptz, oauth_claimed_at timestamptz, selection_claimed_at timestamptz,
  github_id text, login text, code_hash text UNIQUE, user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '15 minutes', consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '90 days'
);
CREATE TABLE IF NOT EXISTS repositories (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE, id text NOT NULL,
  installation_id text NOT NULL, descriptor jsonb NOT NULL, enabled boolean NOT NULL DEFAULT true,
  context jsonb, context_updated_at timestamptz, checkpoint timestamptz,
  PRIMARY KEY(user_id,id)
);
CREATE TABLE IF NOT EXISTS evidence (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE, id text NOT NULL,
  repository_id text NOT NULL, occurred_at timestamptz NOT NULL, payload jsonb NOT NULL,
  PRIMARY KEY(user_id,id), FOREIGN KEY(user_id,repository_id) REFERENCES repositories(user_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS evidence_day ON evidence(user_id,occurred_at);
CREATE TABLE IF NOT EXISTS journals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day date NOT NULL, time_zone text NOT NULL, evidence_hash text, prompt_version text,
  narrative text NOT NULL DEFAULT '', narrative_evidence_ids jsonb NOT NULL DEFAULT '[]',
  narrative_edited boolean NOT NULL DEFAULT false, narrative_deleted boolean NOT NULL DEFAULT false,
  generated_at timestamptz, updated_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(user_id,day,time_zone)
);
CREATE TABLE IF NOT EXISTS entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), journal_id uuid NOT NULL REFERENCES journals(id) ON DELETE CASCADE,
  repository_id text NOT NULL, title text NOT NULL, detail text NOT NULL, kind text NOT NULL,
  confidence double precision NOT NULL CHECK(confidence BETWEEN 0 AND 1), evidence_ids jsonb NOT NULL,
  occurred_at timestamptz NOT NULL, user_edited boolean NOT NULL DEFAULT false,
  user_deleted boolean NOT NULL DEFAULT false, retired boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS generation_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), journal_id uuid NOT NULL REFERENCES journals(id) ON DELETE CASCADE,
  evidence_hash text NOT NULL, prompt_version text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
  UNIQUE(journal_id,evidence_hash,prompt_version)
);
CREATE TABLE IF NOT EXISTS jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day date NOT NULL, time_zone text NOT NULL, status text NOT NULL DEFAULT 'pending',
  attempts int NOT NULL DEFAULT 0, available_at timestamptz NOT NULL DEFAULT now(), lease_until timestamptz,
  lease_token uuid, error_code text, requested_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz, UNIQUE(user_id,day,time_zone)
);
CREATE TABLE IF NOT EXISTS webhook_deliveries (
  id text PRIMARY KEY, event text NOT NULL, payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending', attempts int NOT NULL DEFAULT 0,
  lease_until timestamptz, lease_token uuid, received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);
CREATE TABLE IF NOT EXISTS request_buckets (
  key text PRIMARY KEY, count int NOT NULL DEFAULT 1, reset_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS applied_edits (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE, id uuid NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,id)
);
