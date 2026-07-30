-- Test bootstrap: the minimum Supabase-provided surface the migrations depend on.
--
-- US-207: the migrations in backend/migrations/ reference auth.users, auth.uid(),
-- storage.buckets, storage.objects, storage.foldername(), and the anon /
-- authenticated / service_role roles. On a real deployment GoTrue and
-- storage-api create those. This file recreates just enough of them that the
-- migrations apply *verbatim* — no test-only edits to the migrations themselves,
-- because a policy that only passes against a modified schema proves nothing.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS tests;

-- Roles PostgREST switches into. NOLOGIN: they are only ever reached via SET ROLE.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
END
$$;

-- ============================================================
-- auth schema
-- ============================================================

CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT,
    raw_user_meta_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Mirrors Supabase's implementation: reads the JWT subject out of the request
-- GUCs that PostgREST sets per request.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('request.jwt.claim.sub', true), ''),
        (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(current_setting('request.jwt.claim.role', true), ''),
        (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
        'authenticated'
    )
$$;

-- ============================================================
-- storage schema
-- ============================================================

CREATE TABLE IF NOT EXISTS storage.buckets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner UUID,
    public BOOLEAN NOT NULL DEFAULT false,
    file_size_limit BIGINT,
    allowed_mime_types TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id TEXT NOT NULL REFERENCES storage.buckets(id),
    name TEXT NOT NULL,
    owner UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (bucket_id, name)
);

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Splits an object name into its path segments, as Supabase does. The audio
-- policies index [1] to require the first segment to be the owning user's id.
CREATE OR REPLACE FUNCTION storage.foldername(name TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    parts TEXT[];
BEGIN
    parts := string_to_array(name, '/');
    RETURN parts[1:array_length(parts, 1) - 1];
END
$$;

-- ============================================================
-- Grants
-- ============================================================

GRANT USAGE ON SCHEMA public, auth, storage TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA storage
    TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- ============================================================
-- Assertion helpers
-- ============================================================

CREATE OR REPLACE FUNCTION tests.fail(label TEXT, detail TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'ASSERTION FAILED: % — %', label, detail USING ERRCODE = 'P0001';
END
$$;

CREATE OR REPLACE FUNCTION tests.assert_equals(actual ANYELEMENT, expected ANYELEMENT, label TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        PERFORM tests.fail(label, format('expected %L, got %L', expected, actual));
    END IF;
    RAISE NOTICE '  ok: %', label;
END
$$;

/**
 * Runs `statement` as the given authenticated user and asserts it is rejected.
 *
 * A silent zero-row result and a hard permission error are both acceptable
 * outcomes for an RLS denial, so this accepts either — what it must never see is
 * the statement succeeding in a way that touched another tenant's data.
 */
CREATE OR REPLACE FUNCTION tests.assert_raises(statement TEXT, label TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '  ok: % (rejected: %)', label, SQLERRM;
        RETURN;
    END;
    PERFORM tests.fail(label, 'statement succeeded but should have been rejected');
END
$$;

/** Switches the session to an authenticated request for `p_auth_id`. */
CREATE OR REPLACE FUNCTION tests.act_as(p_auth_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, false);
    PERFORM set_config('request.jwt.claims', json_build_object(
        'sub', p_auth_id::text, 'role', 'authenticated'
    )::text, false);
END
$$;

GRANT USAGE ON SCHEMA tests TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tests TO authenticated, service_role;
